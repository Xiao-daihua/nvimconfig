-- physnav/ui.lua  v7  "biblio-style blocks"
--
-- Layout (each block is its own floating window with a rounded border):
--
--   ╭─ PhysNav ───────────────────────────────────────────────────────╮
--   │  ›  type to search · Esc normal · q close                      │
--   ╰────────────────────────────────────────────────────────────────╯
--   ╭─ Tags ──╮ ╭─ Projects ──────────────╮ ╭─ Preview ──────────╮
--   │ * All   │ │ * project-a  [typ] +  E │ │ name               │
--   │   phys  │ │   project-b  [tex] .  N │ │ type, cat, path …  │
--   │   math  │ │   project-c  [typ] +2 E │ │ tags               │
--   │ …       │ │ …                       │ │ keybinds           │
--   ╰─────────╯ ╰─────────────────────────╯ ╰────────────────────╯
--   ╭─ hints ────────────────────────────────────────────────────────╮
--   │  / search   T tags   n new   d del   g push   l log   ? help   │
--   ╰────────────────────────────────────────────────────────────────╯
--
-- All previous v6 behaviour is preserved — same keymaps, same data flow,
-- same actions. Only the rendering changed from a single big float with
-- hand-drawn separators to five discrete rounded panels.

local M = {}
local api = vim.api
local proj_mod = require("physnav.projects")
local hl_mod = require("physnav.highlights")
local git_mod = require("physnav.git")

-- -----------------------------------------------------------------
--  State
-- -----------------------------------------------------------------
local PANES = { "search", "tags", "list", "preview", "hints" }

local state = {
	cfg = nil,
	wins = {}, -- pane -> winid
	bufs = {}, -- pane -> bufnr
	ns = {}, -- pane -> namespace id (for extmarks)

	projects = {},
	filtered = {},
	selected = 1,
	query = "",
	active_tags = {},
	mode = "normal", -- "normal" | "tags"
	tag_cursor = 1,
	tag_multi = false, -- false = single-select (default), true = multi-select
	tag_and = false, -- OR (default) vs AND logic (only meaningful when multi)
	all_tags = {},
	git_status = {},

	geom = nil,
}

-- Tag colour cache — stable colour per tag name.
local TAG_HLS = {
	"PhysNavTagC1",
	"PhysNavTagC2",
	"PhysNavTagC3",
	"PhysNavTagC4",
	"PhysNavTagC5",
	"PhysNavTagC6",
}
local tag_color_cache = {}
local tag_color_idx = 0
local function reset_tag_colors()
	for k in pairs(tag_color_cache) do
		tag_color_cache[k] = nil
	end
	tag_color_idx = 0
end
local function tag_hl(tag)
	if not tag_color_cache[tag] then
		tag_color_idx = (tag_color_idx % #TAG_HLS) + 1
		tag_color_cache[tag] = TAG_HLS[tag_color_idx]
	end
	return tag_color_cache[tag]
end

-- -----------------------------------------------------------------
--  Helpers
-- -----------------------------------------------------------------
local function is_open()
	if not state.wins or vim.tbl_isempty(state.wins) then
		return false
	end
	for _, pane in ipairs(PANES) do
		local w = state.wins[pane]
		if not w or not api.nvim_win_is_valid(w) then
			return false
		end
	end
	return true
end

local function dw(s)
	return vim.fn.strdisplaywidth(s)
end
local function trunc(s, max_w)
	if dw(s) <= max_w then
		return s
	end
	local r = s
	while dw(r) > max_w - 1 and #r > 0 do
		r = r:sub(1, -2)
	end
	return r .. "…"
end

local function set_lines(buf, lines, leave_modifiable)
	if not buf or not api.nvim_buf_is_valid(buf) then
		return
	end
	vim.bo[buf].modifiable = true
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	if not leave_modifiable then
		vim.bo[buf].modifiable = false
	end
end

-- Panes that should get one row of empty top/bottom padding inside the
-- rounded border. search + hints are single-line and stay flush; tags /
-- list / preview get a bit of breathing room.
local PAD_TOP = { tags = 1, list = 1, preview = 1 }

-- Apply vertical padding to a rendered pane. Given a list of content
-- lines and a list of (group, line, col_s, col_e) highlight ops in
-- content-coords, this shifts everything down by PAD_TOP[pane] rows and
-- appends a trailing blank row. Returns the padded (lines, hl_ops).
local function pad_vertical(pane, lines, hl_ops)
	local n = PAD_TOP[pane] or 0
	if n == 0 then
		return lines, hl_ops
	end
	local padded = {}
	for _ = 1, n do
		table.insert(padded, "")
	end
	for _, l in ipairs(lines) do
		table.insert(padded, l)
	end
	table.insert(padded, "") -- bottom padding
	local shifted = {}
	for _, h in ipairs(hl_ops or {}) do
		table.insert(shifted, { h[1], h[2] + n, h[3], h[4] })
	end
	return padded, shifted
end

local function clear_hl(pane)
	local buf = state.bufs[pane]
	local ns = state.ns[pane]
	if buf and ns then
		api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	end
end

local function add_hl(pane, group, line, col_start, col_end)
	local buf = state.bufs[pane]
	local ns = state.ns[pane]
	if not (buf and ns) then
		return
	end
	pcall(api.nvim_buf_add_highlight, buf, ns, group, line, col_start, col_end or -1)
end

-- -----------------------------------------------------------------
--  Geometry — five panels arranged like biblio's dashboard
-- -----------------------------------------------------------------
local function compute_geometry(cfg)
	local total_cols = vim.o.columns
	local total_lines = vim.o.lines - vim.o.cmdheight - 2

	-- Outer size (driven by user config width/height fractions).
	local outer_w = math.max(80, math.floor(total_cols * (cfg.width or 0.92)))
	local outer_h = math.max(20, math.floor(total_lines * (cfg.height or 0.88)))
	outer_w = math.min(outer_w, total_cols - 2)
	outer_h = math.min(outer_h, total_lines)
	local outer_row = math.floor((total_lines - outer_h) / 2)
	local outer_col = math.floor((total_cols - outer_w) / 2)

	local search_h = 3 -- 1 content row + rounded border (2)
	local hints_h = 3
	local gap_v = 1 -- vertical gap between rows of panels
	local gap_h = 1 -- horizontal gap between side-by-side panels
	local body_h = outer_h - search_h - hints_h - gap_v * 2
	-- Body pains (tags/list/preview) each reserve 1 interior padding row at
	-- the top, so we want at least ~12 lines of body to have meaningful
	-- space for content.
	if body_h < 12 then
		body_h = 12
	end

	-- Widths (follow cfg.sidebar_width / preview_width when possible).
	local tags_w = math.max(14, cfg.sidebar_width or 22)
	local preview_w = math.max(22, cfg.preview_width or 32)
	-- Middle pane fills what's left, minus two horizontal gaps.
	local list_w = outer_w - tags_w - preview_w - gap_h * 2
	if list_w < 24 then
		-- Squeeze side panels if window is too narrow.
		local overflow = 24 - list_w
		local take_tags = math.min(overflow, tags_w - 14)
		tags_w = tags_w - take_tags
		overflow = overflow - take_tags
		if overflow > 0 then
			preview_w = math.max(18, preview_w - overflow)
		end
		list_w = outer_w - tags_w - preview_w - gap_h * 2
	end

	return {
		search = { row = outer_row, col = outer_col, width = outer_w, height = search_h },
		tags = {
			row = outer_row + search_h + gap_v,
			col = outer_col,
			width = tags_w,
			height = body_h,
		},
		list = {
			row = outer_row + search_h + gap_v,
			col = outer_col + tags_w + gap_h,
			width = list_w,
			height = body_h,
		},
		preview = {
			row = outer_row + search_h + gap_v,
			col = outer_col + tags_w + gap_h + list_w + gap_h,
			width = preview_w,
			height = body_h,
		},
		hints = {
			row = outer_row + search_h + gap_v + body_h + gap_v,
			col = outer_col,
			width = outer_w,
			height = hints_h,
		},
	}
end

-- -----------------------------------------------------------------
--  Git status (batched, async)
-- -----------------------------------------------------------------
local function load_git_statuses()
	local cb_map = {}
	for _, p in ipairs(state.projects) do
		local name = p.name
		cb_map[name] = function(s)
			state.git_status[name] = s or ""
			vim.schedule(function()
				if is_open() then
					M._render_list()
					M._render_preview()
				end
			end)
		end
	end
	git_mod.status_async_batch(state.projects, cb_map)
end

-- -----------------------------------------------------------------
--  Render: search bar
-- -----------------------------------------------------------------
local SEARCH_PROMPT = "  ›  "
local SEARCH_PLACEHOLDER = "type to filter · <CR> open · <Esc> back to list · t tags · ? help"

-- Guard so that programmatic writes in _render_search don't trigger the
-- search-text-changed autocmd (which would recurse).
local SEARCH_RENDER_GUARD = false

function M._render_search()
	local q = state.query or ""
	local line
	if q == "" and state.mode ~= "tags" then
		line = SEARCH_PROMPT .. SEARCH_PLACEHOLDER
	else
		line = SEARCH_PROMPT .. q
	end
	SEARCH_RENDER_GUARD = true
	set_lines(state.bufs.search, { line }, true) -- keep buffer modifiable
	SEARCH_RENDER_GUARD = false
	clear_hl("search")
	add_hl("search", "PhysNavSearchPrompt", 0, 0, #SEARCH_PROMPT)
	if q == "" and state.mode ~= "tags" then
		add_hl("search", "PhysNavSearchHint", 0, #SEARCH_PROMPT, -1)
	else
		add_hl("search", "PhysNavSearchText", 0, #SEARCH_PROMPT, -1)
	end
end

-- -----------------------------------------------------------------
--  Render: tags sidebar
-- -----------------------------------------------------------------
function M._render_tags()
	local lines = {}
	-- Top padding row — keeps the first item off the rounded top edge.
	table.insert(lines, "")

	local all_active = (#state.active_tags == 0)
	local all_mark = all_active and "●" or "○"
	table.insert(lines, string.format(" %s All  (%d)", all_mark, #state.projects))

	for _, tag in ipairs(state.all_tags) do
		local cnt = 0
		for _, p in ipairs(state.projects) do
			for _, t in ipairs(p.tags or {}) do
				if t == tag then
					cnt = cnt + 1
					break
				end
			end
		end
		local active = vim.tbl_contains(state.active_tags, tag)
		local mark = active and "●" or "○"
		table.insert(lines, string.format(" %s %s  (%d)", mark, tag, cnt))
	end

	set_lines(state.bufs.tags, lines)
	clear_hl("tags")

	-- Content rows begin at buffer line 1 (0-indexed) because of the pad row.
	-- "All" lives at line 1.
	local all_ln = 1
	if all_active then
		add_hl("tags", "PhysNavTagMarker", all_ln, 1, 4)
		add_hl("tags", "PhysNavAccent", all_ln, 4, -1)
	else
		add_hl("tags", "PhysNavDim", all_ln, 1, 4)
		add_hl("tags", "PhysNavMuted", all_ln, 4, -1)
	end

	-- Tags follow "All" at lines 2 .. 1+#tags.
	for i, tag in ipairs(state.all_tags) do
		local ln = all_ln + i
		local active = vim.tbl_contains(state.active_tags, tag)
		if active then
			add_hl("tags", "PhysNavTagActive", ln, 1, 4)
		else
			add_hl("tags", "PhysNavDim", ln, 1, 4)
		end
		local name_start = 5
		local name_end = name_start + #tag
		add_hl("tags", tag_hl(tag), ln, name_start, name_end)
		add_hl("tags", "PhysNavTagCount", ln, name_end, -1)
	end

	-- Cursor placement.
	--   tag_cursor == 0  → "All"             → buffer row = 2 (1-indexed: pad + all)
	--   tag_cursor == i  → state.all_tags[i] → buffer row = 2 + i
	if state.wins.tags and api.nvim_win_is_valid(state.wins.tags) then
		local row
		if state.mode == "tags" then
			local tc = state.tag_cursor
			if tc < 0 then
				tc = 0
			end
			if tc > #state.all_tags then
				tc = #state.all_tags
			end
			row = 2 + tc
		else
			-- In normal mode, don't move cursor onto the padding row.
			row = 2
		end
		pcall(api.nvim_win_set_cursor, state.wins.tags, { row, 0 })
	end
end

-- -----------------------------------------------------------------
--  Render: project list
-- -----------------------------------------------------------------
function M._render_list()
	local geom = state.geom.list
	local inner_w = math.max(10, geom.width - 2) -- minus border padding

	local lines = {}
	-- Top padding row.
	table.insert(lines, "")

	if #state.filtered == 0 then
		table.insert(lines, "  (no projects match)")
	else
		for _, p in ipairs(state.filtered) do
			local typ_str = p.type == "typst" and "[typ]" or "[tex]"
			local pdf_str = p.has_pdf and "+" or "·"
			local lec_str = (p.lec_count and p.lec_count > 0) and string.format(" x%d", p.lec_count) or ""
			local gs = state.git_status[p.name]
			local git_str = (gs and gs ~= "") and (" " .. gs) or ""
			local cat_ch = p.category == "EPFL_lecture" and "E" or "N"

			local right = string.format(" %s%s%s  %s", typ_str, lec_str, git_str, cat_ch)
			local left_fixed = 4 -- "  X "
			local name_w = math.max(4, inner_w - left_fixed - #right - 1)
			local name = trunc(p.name, name_w)
			local row = string.format(
				"  %s %s%s%s",
				pdf_str,
				name .. string.rep(" ", name_w - dw(name)),
				string.rep(" ", 1),
				right
			)
			table.insert(lines, row)
		end
	end

	set_lines(state.bufs.list, lines)
	clear_hl("list")

	-- Highlight each row. The first buffer row (index 0) is the padding
	-- row, so project i (1-based) lives on buffer line i.
	for i, p in ipairs(state.filtered) do
		local ln = i
		local line = lines[i + 1] -- +1 because lines[1] is padding
		if not line then
			goto continue
		end
		add_hl("list", p.has_pdf and "PhysNavPDF" or "PhysNavNoPDF", ln, 2, 3)

		local badge_s, badge_e = line:find("%[typ%]")
		if not badge_s then
			badge_s, badge_e = line:find("%[tex%]")
		end
		if badge_s then
			add_hl("list", p.type == "typst" and "PhysNavTypst" or "PhysNavLatex", ln, badge_s - 1, badge_e)
		end

		local lec_s, lec_e = line:find(" x%d+", badge_e or 1)
		if lec_s then
			add_hl("list", "PhysNavLecCount", ln, lec_s - 1, lec_e)
		end

		local gs = state.git_status[p.name]
		if gs and gs ~= "" then
			local gi = line:find(gs, (lec_e or badge_e or 1) + 1, true)
			if gi then
				add_hl("list", "PhysNavGitDirty", ln, gi - 1, gi - 1 + #gs)
			end
		end

		local trimmed = line:match("^(.-)%s*$") or line
		local cc_end = #trimmed
		local cc_start = cc_end - 1
		add_hl("list", p.category == "EPFL_lecture" and "PhysNavCatEPFL" or "PhysNavCatNotes", ln, cc_start, cc_end)
		::continue::
	end

	-- Selection = CursorLine. Project i → buffer row i+1 (pad + project).
	if state.wins.list and api.nvim_win_is_valid(state.wins.list) then
		local target = math.min(math.max(state.selected, 1), math.max(1, #state.filtered))
		pcall(api.nvim_win_set_cursor, state.wins.list, { target + 1, 0 })
	end
end

-- -----------------------------------------------------------------
--  Render: preview
-- -----------------------------------------------------------------
function M._render_preview()
	local geom = state.geom.preview
	local inner_w = math.max(10, geom.width - 2)

	local sel = state.filtered[state.selected]
	local lines = {}
	local hl_ops = {} -- {group, line, col_s, col_e}  — line is CONTENT-local.
	local function push_hl(g, l, s, e)
		table.insert(hl_ops, { g, l, s, e })
	end

	if not sel then
		table.insert(lines, "")
		table.insert(lines, "  (no selection)")
	else
		-- Title line with type prefix
		local type_badge = sel.type == "typst" and "typ" or "tex"
		local title = string.format(" %s  %s", type_badge, trunc(sel.name, inner_w - 6))
		table.insert(lines, title)
		push_hl(sel.type == "typst" and "PhysNavTypst" or "PhysNavLatex", #lines - 1, 1, 4)
		push_hl("PhysNavPreviewHead", #lines - 1, 5, -1)
		table.insert(lines, "")

		-- Fields
		local gs_val = state.git_status[sel.name]
		local fields = {
			{ "cat", sel.category },
			{ "main", sel.main or "-" },
			{ "path", sel.path or "-" },
			{ "lec", (sel.lec_count and sel.lec_count > 0) and tostring(sel.lec_count) or "-" },
			{ "pdf", sel.has_pdf and "yes" or "no" },
			{ "git", (gs_val and gs_val ~= "") and gs_val or "clean" },
		}
		for _, f in ipairs(fields) do
			local key = f[1]
			local val = trunc(tostring(f[2]), inner_w - #key - 4)
			local row = string.format(" %-5s %s", key, val)
			table.insert(lines, row)
			local ln = #lines - 1
			push_hl("PhysNavPreviewKey", ln, 1, 6)
			-- Colour value by field
			local val_start = 7
			if key == "pdf" then
				push_hl(sel.has_pdf and "PhysNavPDF" or "PhysNavNoPDF", ln, val_start, -1)
			elseif key == "git" then
				push_hl((gs_val and gs_val ~= "") and "PhysNavGitDirty" or "PhysNavGitClean", ln, val_start, -1)
			elseif key == "lec" then
				push_hl("PhysNavLecCount", ln, val_start, -1)
			elseif key == "cat" then
				push_hl(sel.category == "EPFL_lecture" and "PhysNavCatEPFL" or "PhysNavCatNotes", ln, val_start, -1)
			elseif key == "path" then
				push_hl("PhysNavMuted", ln, val_start, -1)
			else
				push_hl("PhysNavPreviewVal", ln, val_start, -1)
			end
		end

		-- Tags
		table.insert(lines, "")
		table.insert(lines, " tags")
		push_hl("PhysNavPreviewHead", #lines - 1, 1, -1)
		if sel.tags and #sel.tags > 0 then
			-- Wrap tags across lines within inner_w, and record the exact
			-- (line_index, col_start, col_end) of every tag we lay down — no
			-- post-hoc substring matching (which would mis-match e.g. "ml"
			-- inside "mlops").
			local current = " " -- current line buffer (display text)
			local current_col = 1 -- byte col of next append in `current`
			local tag_spans = {} -- {line_idx(1-based), col_s, col_e, hl}
			local function flush()
				table.insert(lines, current)
				current = " "
				current_col = 1
			end
			for _, t in ipairs(sel.tags) do
				local piece = t .. "  "
				if dw(current) + dw(piece) > inner_w - 1 and current ~= " " then
					flush()
				end
				-- Tag starts right where current_col points (after the leading
				-- space, possibly after previous pieces).
				local s = current_col
				local e = s + #t
				table.insert(tag_spans, { #lines + 1, s, e, tag_hl(t) })
				current = current .. piece
				current_col = current_col + #piece
			end
			if current ~= " " then
				flush()
			end

			for _, span in ipairs(tag_spans) do
				push_hl(span[4], span[1] - 1, span[2], span[3])
			end
		else
			table.insert(lines, " (no tags — press e)")
			push_hl("PhysNavMuted", #lines - 1, 0, -1)
		end

		-- Keybinds cheatsheet
		table.insert(lines, "")
		table.insert(lines, " keys")
		push_hl("PhysNavPreviewHead", #lines - 1, 1, -1)
		local keybinds = {
			{ "Enter", "open + tree" },
			{ "p", "open PDF" },
			{ "g", "git push" },
			{ "L", "git log" },
			{ "e", "edit tags" },
			{ "t", "tag panel" },
			{ "m", "multi-select tag" },
			{ "n", "new note" },
			{ "d", "delete" },
			{ "/", "search" },
			{ "h / l", "move panel" },
			{ "r", "rescan" },
		}
		for _, kb in ipairs(keybinds) do
			local row = string.format(" %-6s %s", kb[1], kb[2])
			table.insert(lines, row)
			local ln = #lines - 1
			push_hl("PhysNavHintKey", ln, 1, 1 + #kb[1])
			push_hl("PhysNavHintDesc", ln, 1 + #kb[1] + 1, -1)
		end
	end

	-- Final pass: prepend a padding row so the content isn't flush against
	-- the rounded top border. Shift every hl_op down by 1 to compensate.
	table.insert(lines, 1, "")
	set_lines(state.bufs.preview, lines)
	clear_hl("preview")
	for _, op in ipairs(hl_ops) do
		add_hl("preview", op[1], op[2] + 1, op[3], op[4])
	end

	-- Preview never responds to cursor — keep it stable at top.
	if state.wins.preview and api.nvim_win_is_valid(state.wins.preview) then
		pcall(api.nvim_win_set_cursor, state.wins.preview, { 1, 0 })
	end
end

-- -----------------------------------------------------------------
--  Render: hints bar
-- -----------------------------------------------------------------
function M._render_hints()
	local items
	if state.mode == "tags" then
		local ms = state.tag_multi and "multi" or "single"
		items = {
			{ " TAGS ", "mode" },
			{ "j/k", "move" },
			{ "Enter", "pick" },
			{ "Space", "toggle" },
			{ "m", "mode: " .. ms },
		}
		if state.tag_multi then
			table.insert(items, { "a", state.tag_and and "AND→OR" or "OR→AND" })
		end
		table.insert(items, { "l / Esc", "back" })
	else
		items = {
			{ " NAV ", "mode" },
			{ "/", "search" },
			{ "t", "tags" },
			{ "e", "edit" },
			{ "n", "new" },
			{ "d", "del" },
			{ "p", "pdf" },
			{ "g", "push" },
			{ "L", "log" },
			{ "h/l", "panels" },
			{ "r", "rescan" },
			{ "?", "help" },
			{ "q", "quit" },
		}
	end

	-- Build the line and track per-segment ranges.
	local parts = {}
	local ranges = {}
	local col = 0
	local function add(text, kind)
		table.insert(parts, text)
		table.insert(ranges, { kind, col, col + #text })
		col = col + #text
	end
	add(" ", "space")
	add(items[1][1], state.mode == "tags" and "mode_tags" or "mode_normal")

	local suffix_parts = {}
	if state.query ~= "" then
		table.insert(suffix_parts, '/"' .. state.query .. '"')
	end
	if #state.active_tags > 0 then
		local logic = (state.tag_multi and #state.active_tags > 1) and (state.tag_and and "AND" or "OR") or "="
		table.insert(suffix_parts, logic .. ":" .. table.concat(state.active_tags, "+"))
	end

	for i = 2, #items do
		add("  ", "space")
		add(items[i][1], "key")
		add(" ", "space")
		add(items[i][2], "desc")
	end

	if #suffix_parts > 0 then
		add("   ", "space")
		add("[" .. table.concat(suffix_parts, "  ") .. "]", "filter")
	end

	local line = table.concat(parts, "")
	set_lines(state.bufs.hints, { line })
	clear_hl("hints")

	for _, r in ipairs(ranges) do
		local kind, s, e = r[1], r[2], r[3]
		if kind == "mode_normal" then
			add_hl("hints", "PhysNavModeNormal", 0, s, e)
		elseif kind == "mode_tags" then
			add_hl("hints", "PhysNavModeTags", 0, s, e)
		elseif kind == "key" then
			add_hl("hints", "PhysNavHintKey", 0, s, e)
		elseif kind == "desc" then
			add_hl("hints", "PhysNavHintDesc", 0, s, e)
		elseif kind == "filter" then
			add_hl("hints", "PhysNavAccentWarm", 0, s, e)
		end
	end
end

-- -----------------------------------------------------------------
--  Titles on each panel (dynamic: show counts, search, mode)
--  We only call nvim_win_set_config when the title or active state
--  actually changed, to avoid flicker on fast j/k navigation.
-- -----------------------------------------------------------------
local last_title_state = {} -- pane -> { title, active }

local function apply_titles()
	local function set_title(pane, title, is_active)
		local w = state.wins[pane]
		if not w or not api.nvim_win_is_valid(w) then
			return
		end
		local prev = last_title_state[pane]
		if prev and prev.title == title and prev.active == is_active then
			return
		end
		last_title_state[pane] = { title = title, active = is_active }

		if title ~= nil then
			local cfg = api.nvim_win_get_config(w)
			cfg.title = title
			cfg.title_pos = "center"
			pcall(api.nvim_win_set_config, w, cfg)
		end
		local wh = is_active and "NormalFloat:NormalFloat,FloatBorder:PhysNavBorderActive,CursorLine:PhysNavCursorLine"
			or "NormalFloat:NormalFloat,FloatBorder:PhysNavBorder,CursorLine:PhysNavCursorLine"
		pcall(function()
			vim.wo[w].winhighlight = wh
		end)
	end

	set_title(
		"search",
		state.query ~= "" and (' search : "' .. state.query .. '" ') or " PhysNav ",
		state.mode ~= "tags"
	)

	local tag_title = " Tags "
	if #state.active_tags > 0 then
		tag_title = string.format(" Tags [%s:%d] ", state.tag_and and "AND" or "OR", #state.active_tags)
	end
	set_title("tags", tag_title, state.mode == "tags")

	local list_title = string.format(" Projects  %d/%d ", #state.filtered, #state.projects)
	set_title("list", list_title, state.mode == "normal")

	local sel = state.filtered[state.selected]
	set_title("preview", sel and " Preview " or " Preview (empty) ", false)

	set_title("hints", nil, false)
end

-- -----------------------------------------------------------------
--  Full render
-- -----------------------------------------------------------------
function M._render()
	if not is_open() then
		return
	end
	M._render_search()
	M._render_tags()
	M._render_list()
	M._render_preview()
	M._render_hints()
	apply_titles()
end

-- -----------------------------------------------------------------
--  Refresh (recompute filter)
-- -----------------------------------------------------------------
local function refresh()
	if not is_open() then
		return
	end
	state.filtered = proj_mod.filter(state.projects, state.query, state.active_tags, state.cfg.sort_by, state.tag_and)
	state.selected = math.min(math.max(state.selected, 1), math.max(1, #state.filtered))
	M._render()
end

-- -----------------------------------------------------------------
--  Tag filter helpers
--
--  Single-select (default): picking a tag replaces the filter; picking
--  the same tag again clears it.
--  Multi-select (state.tag_multi == true, toggled with `m`): picking
--  toggles the tag in the active set. AND/OR logic (`a`) applies across
--  multiple selected tags.
-- -----------------------------------------------------------------
local function toggle_tag_filter(tag)
	if state.tag_multi then
		local idx = nil
		for i, t in ipairs(state.active_tags) do
			if t == tag then
				idx = i
				break
			end
		end
		if idx then
			table.remove(state.active_tags, idx)
		else
			table.insert(state.active_tags, tag)
		end
	else
		-- Single-select: replace (or clear on re-pick).
		if #state.active_tags == 1 and state.active_tags[1] == tag then
			state.active_tags = {}
		else
			state.active_tags = { tag }
		end
	end
	state.selected = 1
end

-- Select "All" (clear filter) — used when cursor is on the "All" row.
local function select_all_tags()
	state.active_tags = {}
	state.selected = 1
end

-- -----------------------------------------------------------------
--  NeoTree / netrw
-- -----------------------------------------------------------------
local function open_neotree(path)
	local ok = pcall(vim.cmd, "Neotree dir=" .. vim.fn.fnameescape(path) .. " reveal")
	if not ok then
		pcall(vim.cmd, "Explore " .. vim.fn.fnameescape(path))
	end
end

local function refocus_physnav()
	if is_open() then
		pcall(api.nvim_set_current_win, state.wins.list)
	end
end

-- -----------------------------------------------------------------
--  Actions
-- -----------------------------------------------------------------
local function open_project()
	local p = state.filtered[state.selected]
	if not p then
		return
	end
	local target = p.path .. "/" .. (p.main or "main.tex")
	local path = p.path
	local cmd = state.cfg.open_cmd
	proj_mod.touch(state.cfg.data_file, state.projects, p.name)
	M.close()
	vim.cmd(cmd .. " " .. vim.fn.fnameescape(target))
	pcall(vim.cmd, "cd " .. vim.fn.fnameescape(path))
	vim.schedule(function()
		open_neotree(path)
	end)
end

local function open_pdf()
	local p = state.filtered[state.selected]
	if not p then
		return
	end
	local pdf = p.path .. "/main.pdf"
	if vim.fn.filereadable(pdf) == 0 then
		vim.notify("PhysNav: no PDF for " .. p.name, vim.log.levels.WARN)
		return
	end
	for _, o in ipairs({ "xdg-open", "open", "zathura", "evince", "okular" }) do
		if vim.fn.executable(o) == 1 then
			vim.fn.jobstart({ o, pdf }, { detach = true })
			return
		end
	end
	vim.notify("PhysNav: no PDF viewer found", vim.log.levels.WARN)
end

local function do_git_push()
	local p = state.filtered[state.selected]
	if not p then
		return
	end
	git_mod.push_project(p, nil, refocus_physnav)
end

local function do_git_log()
	local p = state.filtered[state.selected]
	if not p then
		return
	end
	git_mod.show_log(p, refocus_physnav)
end

-- Focus the top search bar pane and drop into insert mode. The search bar
-- has a TextChanged/TextChangedI autocmd (registered in open()) that reads
-- the query out of its buffer and refreshes the list live.
--
-- Subtlety: writing to the buffer triggers TextChanged too, which would
-- recurse back into this handler. SEARCH_RENDER_GUARD gates that.
local function focus_search()
	local w = state.wins.search
	local b = state.bufs.search
	if not (w and b and api.nvim_win_is_valid(w) and api.nvim_buf_is_valid(b)) then
		return
	end
	state.mode = "normal"
	api.nvim_set_current_win(w)
	vim.bo[b].modifiable = true
	local line = SEARCH_PROMPT .. (state.query or "")
	SEARCH_RENDER_GUARD = true
	api.nvim_buf_set_lines(b, 0, -1, false, { line })
	SEARCH_RENDER_GUARD = false
	-- Clear the placeholder/hint highlight and re-paint as live text so the
	-- user sees their input in the accent colour, not the muted hint colour.
	clear_hl("search")
	add_hl("search", "PhysNavSearchPrompt", 0, 0, #SEARCH_PROMPT)
	add_hl("search", "PhysNavSearchText", 0, #SEARCH_PROMPT, -1)
	api.nvim_win_set_cursor(w, { 1, #line })
	vim.cmd("startinsert!")
end

-- Parse the search buffer's current line and update state.query live.
-- Then refresh all the *other* panes — crucially NOT _render_search, as
-- that would clobber what the user just typed and move the cursor.
local function on_search_text_changed()
	if SEARCH_RENDER_GUARD then
		return
	end
	if not is_open() then
		return
	end
	local b = state.bufs.search
	if not (b and api.nvim_buf_is_valid(b)) then
		return
	end
	local raw = (api.nvim_buf_get_lines(b, 0, 1, false) or { "" })[1] or ""
	-- Strip the prompt. If the user somehow deleted it, treat everything as query.
	local q
	if raw:sub(1, #SEARCH_PROMPT) == SEARCH_PROMPT then
		q = raw:sub(#SEARCH_PROMPT + 1)
	else
		q = raw
		-- Restore the prompt so subsequent renders stay consistent.
		SEARCH_RENDER_GUARD = true
		api.nvim_buf_set_lines(b, 0, -1, false, { SEARCH_PROMPT .. q })
		SEARCH_RENDER_GUARD = false
		local w = state.wins.search
		if w and api.nvim_win_is_valid(w) then
			pcall(api.nvim_win_set_cursor, w, { 1, #SEARCH_PROMPT + #q })
		end
	end
	if q == state.query then
		-- No change — e.g. cursor move fired TextChanged after enter-insert.
		return
	end
	state.query = q
	state.selected = 1
	state.filtered = proj_mod.filter(state.projects, state.query, state.active_tags, state.cfg.sort_by, state.tag_and)
	-- Repaint the blocks that depend on filter results, but leave search
	-- alone so we don't fight the user's cursor / pending input.
	M._render_tags()
	M._render_list()
	M._render_preview()
	M._render_hints()
	-- Refresh the dynamic title text on the list pane (e.g. "Projects 3/23").
	pcall(apply_titles)
	-- Re-apply the search-pane's live-text highlight (we just painted it in
	-- focus_search, but typing a character doesn't re-run that path).
	clear_hl("search")
	add_hl("search", "PhysNavSearchPrompt", 0, 0, #SEARCH_PROMPT)
	add_hl("search", "PhysNavSearchText", 0, #SEARCH_PROMPT, -1)
end

-- Leave the search pane: stopinsert, move focus to the list pane, and
-- let _render_search repaint with the placeholder/live text as appropriate.
local function leave_search_to_list()
	vim.cmd("stopinsert")
	if state.wins.list and api.nvim_win_is_valid(state.wins.list) then
		api.nvim_set_current_win(state.wins.list)
	end
	-- Full render is safe now that we're out of the search buffer.
	M._render()
end

local function do_tag_edit()
	local p = state.filtered[state.selected]
	if not p then
		return
	end
	vim.ui.input({
		prompt = 'Tags for "' .. p.name .. '" (comma-separated): ',
		default = table.concat(p.tags or {}, ", "),
	}, function(input)
		if input ~= nil then
			local new_tags = {}
			for tag in input:gmatch("[^,]+") do
				local t = vim.trim(tag)
				if t ~= "" then
					table.insert(new_tags, t)
				end
			end
			proj_mod.update_tags(state.cfg.data_file, state.projects, p.name, new_tags)
			state.all_tags = proj_mod.all_tags(state.projects)
			reset_tag_colors()
		end
		if is_open() then
			pcall(api.nvim_set_current_win, state.wins.list)
			refresh()
		end
	end)
end

-- -----------------------------------------------------------------
--  New note wizard
-- -----------------------------------------------------------------
local function do_new_note()
	local cfg = state.cfg

	-- Refocus the dashboard after a wizard step is cancelled.
	-- Works for both the single-window (state.win) and multi-pane
	-- (state.wins.list) layouts.
	local function refocus()
		if not is_open() then
			return
		end
		local target = (state.wins and state.wins.list) or state.win
		if target and vim.api.nvim_win_is_valid(target) then
			pcall(vim.api.nvim_set_current_win, target)
		end
	end

	-- Guard against missing templates config.
	local templates = cfg.templates or {}
	if #templates == 0 then
		vim.notify(
			"PhysNav: no templates configured. Set `templates = {...}` in physnav.setup().",
			vim.log.levels.ERROR
		)
		refocus()
		return
	end

	-- Collect everything first, clone at the end.
	local tmpl, category, name, new_tags

	------------------------------------------------------------------
	-- step 4 : clone the chosen template and register the project
	------------------------------------------------------------------
	local function step4_clone()
		local dest = cfg.root .. "/" .. category .. "/" .. name
		if vim.fn.isdirectory(dest) == 1 then
			vim.notify("PhysNav: already exists: " .. dest, vim.log.levels.ERROR)
			refocus()
			return
		end

		local main_file = tmpl.main or (tmpl.type == "latex" and "main.tex" or "main.typ")
		local proj_type = tmpl.type or "typst"

		vim.notify(string.format("PhysNav: cloning template '%s' …", tmpl.label), vim.log.levels.INFO)

		vim.fn.jobstart({ "git", "clone", "--depth=1", tmpl.url, dest }, {
			on_exit = function(_, code)
				vim.schedule(function()
					if code ~= 0 then
						vim.notify(
							"PhysNav: clone failed (code " .. code .. ") from " .. tmpl.url,
							vim.log.levels.ERROR
						)
						refocus()
						return
					end
					-- Strip .git so the new project isn't tied to the template's repo.
					vim.fn.jobstart({ "rm", "-rf", dest .. "/.git" }, {
						on_exit = function(_, _)
							vim.schedule(function()
								local new_proj = {
									name = name,
									category = category,
									path = dest,
									type = proj_type,
									main = main_file,
									lec_count = 0,
									has_pdf = false,
									tags = new_tags,
									last_opened = os.time(),
								}
								proj_mod.add_project(cfg.data_file, state.projects, new_proj)
								state.all_tags = proj_mod.all_tags(state.projects)
								reset_tag_colors()
								vim.notify(
									string.format("PhysNav: created %s/%s from '%s'", category, name, tmpl.label),
									vim.log.levels.INFO
								)

								-- Two refresh calls: first to recompute filtered, second
								-- after we move the selection to the new project.
								refresh()
								for i, p in ipairs(state.filtered) do
									if p.name == name then
										state.selected = i
										break
									end
								end
								refresh()

								-- Close dashboard, open the main file, drop NeoTree.
								M.close()
								vim.cmd(cfg.open_cmd .. " " .. vim.fn.fnameescape(dest .. "/" .. main_file))
								pcall(vim.cmd, "cd " .. vim.fn.fnameescape(dest))
								vim.schedule(function()
									open_neotree(dest)
								end)
							end)
						end,
					})
				end)
			end,
		})
	end

	------------------------------------------------------------------
	-- step 3 : project name + tags
	------------------------------------------------------------------
	local function step3_name_and_tags()
		vim.ui.input({ prompt = "Project name: " }, function(input)
			if not input or vim.trim(input) == "" then
				refocus()
				return
			end
			name = vim.trim(input):gsub("%s+", "_")
			vim.ui.input({ prompt = "Tags (comma-separated, blank ok): " }, function(tag_input)
				new_tags = {}
				if tag_input and vim.trim(tag_input) ~= "" then
					for tag in tag_input:gmatch("[^,]+") do
						local t = vim.trim(tag)
						if t ~= "" then
							table.insert(new_tags, t)
						end
					end
				end
				vim.schedule(step4_clone)
			end)
		end)
	end

	------------------------------------------------------------------
	-- step 2 : pick a category
	------------------------------------------------------------------
	local function step2_category()
		vim.ui.select(cfg.categories, { prompt = "Category:" }, function(sel)
			if not sel then
				refocus()
				return
			end
			category = sel
			vim.schedule(step3_name_and_tags)
		end)
	end

	------------------------------------------------------------------
	-- step 1 : pick a template
	------------------------------------------------------------------
	-- If there's only one template, skip the picker entirely.
	if #templates == 1 then
		tmpl = templates[1]
		vim.schedule(step2_category)
		return
	end

	vim.ui.select(templates, {
		prompt = "Template:",
		format_item = function(t)
			return string.format("%s   [%s]", t.label, t.type or "typst")
		end,
	}, function(sel)
		if not sel then
			refocus()
			return
		end
		tmpl = sel
		vim.schedule(step2_category)
	end)
end

-- -----------------------------------------------------------------
--  Delete project
-- -----------------------------------------------------------------
local function detect_trash_cmd()
	for _, cmd in ipairs({ "trash", "trash-put", "gio trash" }) do
		local bin = cmd:match("^(%S+)")
		if vim.fn.executable(bin) == 1 then
			return cmd
		end
	end
	return nil
end

local function do_delete_project()
	local p = state.filtered[state.selected]
	if not p then
		return
	end
	local trash_cmd = state.cfg.trash_cmd or detect_trash_cmd()
	local method = trash_cmd and "trash" or "PERMANENTLY DELETE"
	vim.ui.input({
		prompt = string.format('[%s] Confirm name to delete "%s": ', method, p.name),
	}, function(input)
		if input == nil or vim.trim(input) ~= p.name then
			vim.notify("PhysNav: delete cancelled", vim.log.levels.INFO)
			if is_open() then
				pcall(api.nvim_set_current_win, state.wins.list)
			end
			return
		end
		local path = p.path
		local name = p.name
		local function after(ok)
			vim.schedule(function()
				if ok then
					proj_mod.remove_project(state.cfg.data_file, state.projects, name)
					state.all_tags = proj_mod.all_tags(state.projects)
					reset_tag_colors()
					state.selected = math.max(1, state.selected - 1)
					vim.notify("PhysNav: deleted " .. name, vim.log.levels.INFO)
					if is_open() then
						pcall(api.nvim_set_current_win, state.wins.list)
						refresh()
					end
				else
					vim.notify("PhysNav: delete failed: " .. name, vim.log.levels.ERROR)
					if is_open() then
						pcall(api.nvim_set_current_win, state.wins.list)
					end
				end
			end)
		end
		if trash_cmd then
			local parts = vim.split(trash_cmd, " ")
			table.insert(parts, path)
			vim.fn.jobstart(parts, {
				on_exit = function(_, c)
					after(c == 0)
				end,
			})
		else
			vim.fn.jobstart({ "rm", "-rf", path }, {
				on_exit = function(_, c)
					after(c == 0)
				end,
			})
		end
	end)
end

-- -----------------------------------------------------------------
--  Help
-- -----------------------------------------------------------------
local function show_help()
	vim.notify(
		table.concat({
			"PhysNav  keybindings",
			string.rep("-", 48),
			"  Navigation",
			"    j / k / Down / Up   move within current pane",
			"    h / l / ← / →       move BETWEEN panes",
			"                          tags  ← list → preview",
			"    gg / G              jump to first / last item",
			"    Enter               open project (from list) / pick tag",
			"",
			"  Project actions (from the list pane)",
			"    p                   open compiled PDF",
			"    g                   git push   (PhysNav stays open)",
			"    L                   git log    (PhysNav stays open)",
			"    e                   edit tags for current project",
			"    n                   new note from typst template",
			"    d                   delete project (trash / rm -rf)",
			"    r                   force rescan from disk",
			"",
			"  Search",
			"    /                   focus the top search bar",
			"      (in search) type to filter live",
			"      (in search) <C-j>/<C-k> or <C-n>/<C-p> move list selection",
			"      (in search) <CR>  open the selected project",
			"      (in search) <Esc> leave search, keep query",
			"      (in search) <C-u> clear query",
			"",
			"  Tag panel",
			"    t                   open/close the tag panel",
			"    j/k                 move tag cursor (including 'All')",
			"    Enter / click       pick this tag (single-select)",
			"    Space               toggle this tag",
			"    m                   toggle multi-select mode",
			"    a                   toggle AND / OR  (multi-select only)",
			"    l / Esc             back to the list",
			"",
			"  Misc",
			"    <C-c>               clear search + tag filters",
			"    q                   quit",
			"    Esc                 quit (or clear filters first)",
			"    ?                   this help",
		}, "\n"),
		vim.log.levels.INFO,
		{ title = "PhysNav" }
	)
end

-- -----------------------------------------------------------------
--  Keymaps
--
--  Layout overview:
--    list pane    — j/k move item, Enter open, h → tags, l → preview
--    tags pane    — j/k move tag,  Enter pick, l → list, m toggle multi
--    preview pane — read-only,     h → list
--    search pane  — insert-mode entry + live filter (its own maps below)
--
--  These normal-mode maps are attached to every non-search pane buffer so
--  global actions (/, n, d, ?, q…) work no matter which block has focus.
-- -----------------------------------------------------------------
local function attach_keymaps(buf, pane)
	local opts = { buffer = buf, noremap = true, silent = true, nowait = true }
	local function nmap(key, fn)
		vim.keymap.set("n", key, fn, opts)
	end

	-- ── vertical movement ───────────────────────────────────────────
	nmap("j", function()
		if state.mode == "tags" then
			-- tag_cursor is 0 for "All", 1..#all_tags for real tags.
			state.tag_cursor = math.min(state.tag_cursor + 1, #state.all_tags)
		else
			state.selected = math.min(state.selected + 1, math.max(1, #state.filtered))
		end
		refresh()
	end)
	nmap("k", function()
		if state.mode == "tags" then
			state.tag_cursor = math.max(state.tag_cursor - 1, 0)
		else
			state.selected = math.max(state.selected - 1, 1)
		end
		refresh()
	end)
	nmap("<Down>", function()
		if state.mode == "tags" then
			state.tag_cursor = math.min(state.tag_cursor + 1, #state.all_tags)
		else
			state.selected = math.min(state.selected + 1, math.max(1, #state.filtered))
		end
		refresh()
	end)
	nmap("<Up>", function()
		if state.mode == "tags" then
			state.tag_cursor = math.max(state.tag_cursor - 1, 0)
		else
			state.selected = math.max(state.selected - 1, 1)
		end
		refresh()
	end)
	nmap("gg", function()
		if state.mode == "tags" then
			state.tag_cursor = 0
		else
			state.selected = 1
		end
		refresh()
	end)
	nmap("G", function()
		if state.mode == "tags" then
			state.tag_cursor = #state.all_tags
		else
			state.selected = math.max(1, #state.filtered)
		end
		refresh()
	end)

	-- ── horizontal pane navigation: h / l ───────────────────────────
	--
	-- From any pane, h moves focus "left" and l "right" along the row:
	--   tags  ← list ← preview
	--         (h)        (h, from preview)
	--   tags  → list → preview
	--         (l)        (l)
	-- Moving into the tags pane also puts us in tags-browse mode so that
	-- j/k operate on tags instead of the (invisible) list selection.
	--
	-- Moving from a pane → list also leaves tags-mode, which keeps the
	-- visual CursorLine on the right block.
	local function focus_list()
		state.mode = "normal"
		if state.wins.list and api.nvim_win_is_valid(state.wins.list) then
			api.nvim_set_current_win(state.wins.list)
		end
		refresh()
	end
	local function focus_tags()
		state.mode = "tags"
		-- Preserve tag_cursor on re-entry, but make sure it's in range.
		if state.tag_cursor > #state.all_tags then
			state.tag_cursor = math.max(0, #state.all_tags)
		end
		if state.wins.tags and api.nvim_win_is_valid(state.wins.tags) then
			api.nvim_set_current_win(state.wins.tags)
		end
		refresh()
	end
	local function focus_preview()
		state.mode = "normal"
		if state.wins.preview and api.nvim_win_is_valid(state.wins.preview) then
			api.nvim_set_current_win(state.wins.preview)
		end
		refresh()
	end

	nmap("h", function()
		if pane == "list" then
			focus_tags()
		elseif pane == "preview" then
			focus_list()
		elseif pane == "tags" then
			return -- already leftmost
		elseif pane == "hints" then
			focus_list()
		end
	end)
	nmap("l", function()
		if pane == "tags" then
			focus_list()
		elseif pane == "list" then
			focus_preview()
		elseif pane == "preview" then
			return -- already rightmost
		elseif pane == "hints" then
			focus_list()
		end
	end)
	-- Arrow variants, for folks who prefer them.
	nmap("<Left>", function()
		if pane == "list" then
			focus_tags()
		elseif pane == "preview" then
			focus_list()
		end
	end)
	nmap("<Right>", function()
		if pane == "tags" then
			focus_list()
		elseif pane == "list" then
			focus_preview()
		end
	end)

	-- ── Enter: context-dependent ────────────────────────────────────
	nmap("<CR>", function()
		if state.mode == "tags" then
			if state.tag_cursor == 0 then
				select_all_tags()
				state.mode = "normal"
				focus_list()
			else
				local tag = state.all_tags[state.tag_cursor]
				if tag then
					toggle_tag_filter(tag)
					-- In single-select mode, jump back to the list after picking.
					-- In multi-select mode, stay in the tags pane so the user can
					-- keep toggling.
					if not state.tag_multi then
						state.mode = "normal"
						focus_list()
					else
						refresh()
					end
				end
			end
		else
			open_project()
		end
	end)
	nmap("<2-LeftMouse>", function()
		if state.mode == "tags" then
			if state.tag_cursor == 0 then
				select_all_tags()
				state.mode = "normal"
				focus_list()
			else
				local tag = state.all_tags[state.tag_cursor]
				if tag then
					toggle_tag_filter(tag)
					if not state.tag_multi then
						state.mode = "normal"
						focus_list()
					else
						refresh()
					end
				end
			end
		else
			open_project()
		end
	end)

	-- ── tag-browser toggle & multi-select toggle ────────────────────
	-- `t` now enters / exits tag-browser mode (previously this was `T`).
	-- Both are kept so that muscle memory from v7 still works.
	local function toggle_tag_mode()
		if state.mode == "tags" then
			focus_list()
		else
			focus_tags()
		end
	end
	nmap("t", toggle_tag_mode)
	nmap("T", toggle_tag_mode)

	-- `m` toggles multi-select on the tags pane. When turning multi OFF
	-- and there are >1 active tags, collapse to just the one under cursor
	-- to keep the filter self-consistent.
	nmap("m", function()
		state.tag_multi = not state.tag_multi
		if not state.tag_multi and #state.active_tags > 1 then
			local keep = state.all_tags[state.tag_cursor]
			state.active_tags = keep and { keep } or {}
		end
		state.selected = 1
		refresh()
	end)

	-- `<Space>` still toggles a tag in tags-mode (mainly useful when
	-- multi-select is on). In single-select mode it works just like <CR>
	-- but without jumping back to the list — handy for quickly flipping
	-- through tags while staying in the tags pane.
	nmap("<Space>", function()
		if state.mode == "tags" then
			if state.tag_cursor == 0 then
				select_all_tags()
				refresh()
			else
				local tag = state.all_tags[state.tag_cursor]
				if tag then
					toggle_tag_filter(tag)
					refresh()
				end
			end
		end
	end)

	-- `a` toggles AND/OR logic — only meaningful with multi-select.
	nmap("a", function()
		if state.tag_multi and #state.active_tags > 1 then
			state.tag_and = not state.tag_and
			state.selected = 1
			refresh()
		else
			vim.notify("AND/OR only applies with multi-select (press m)", vim.log.levels.INFO)
		end
	end)

	-- ── Esc / <C-c> : exit mode / clear filters / quit ──────────────
	nmap("<Esc>", function()
		if state.mode == "tags" then
			focus_list()
		elseif state.query ~= "" or #state.active_tags > 0 then
			state.query = ""
			state.active_tags = {}
			state.tag_and = false
			state.selected = 1
			refresh()
		else
			M.close()
		end
	end)
	nmap("<C-c>", function()
		state.query = ""
		state.active_tags = {}
		state.mode = "normal"
		state.tag_and = false
		state.selected = 1
		refresh()
	end)

	-- ── Actions ─────────────────────────────────────────────────────
	-- `/`  focus the search bar (was: vim.ui.input at the bottom of the screen)
	-- `p`  open PDF
	-- `g`  git push   (note: `gg` is still "jump to top" — Vim will wait
	--                  for timeoutlen before triggering push)
	-- `L`  git log    (was `l`; moved to free up `l` for pane nav)
	-- `e`  edit current project's tags (was `t`)
	-- `n`  new note
	-- `d`  delete project
	-- `r`  rescan
	-- `?`  help,  `q` quit
	nmap("/", focus_search)
	nmap("p", open_pdf)
	nmap("g", function()
		vim.schedule(do_git_push)
	end)
	nmap("L", function()
		vim.schedule(do_git_log)
	end)
	nmap("e", function()
		vim.schedule(do_tag_edit)
	end)
	nmap("n", function()
		vim.schedule(do_new_note)
	end)
	nmap("d", function()
		vim.schedule(do_delete_project)
	end)
	nmap("r", function()
		state.projects = proj_mod.scan_and_save()
		state.all_tags = proj_mod.all_tags(state.projects)
		state.git_status = {}
		reset_tag_colors()
		refresh()
		load_git_statuses()
		vim.notify("PhysNav: rescanned", vim.log.levels.INFO)
	end)
	nmap("?", show_help)
	nmap("q", function()
		M.close()
	end)
end

-- -----------------------------------------------------------------
--  Pane window creation
-- -----------------------------------------------------------------
local function make_pane(pane, geom, title)
	-- Window dimensions account for the rounded border (2 chars of padding
	-- total in each direction).
	local buf = api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "physnav_" .. pane
	-- All panes start read-only except the search pane, which is where the
	-- user types to filter. Its keymap/autocmd flips modifiable back on and
	-- off as needed.
	vim.bo[buf].modifiable = (pane == "search")
	pcall(api.nvim_buf_set_var, buf, "physnav_main", true)

	local opts = {
		relative = "editor",
		row = geom.row,
		col = geom.col,
		width = math.max(6, geom.width - 2),
		height = math.max(1, geom.height - 2),
		style = "minimal",
		border = "rounded",
	}
	if title then
		opts.title = title
		opts.title_pos = "center"
	end

	-- Only the list pane is initially focused.
	local focus = (pane == "list")
	local win = api.nvim_open_win(buf, focus, opts)

	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = (pane == "list" or pane == "tags")
	vim.wo[win].winhighlight = "NormalFloat:NormalFloat,FloatBorder:PhysNavBorder,CursorLine:PhysNavCursorLine"

	state.bufs[pane] = buf
	state.wins[pane] = win
	state.ns[pane] = api.nvim_create_namespace("physnav_" .. pane)

	attach_keymaps(buf, pane)
	return win, buf
end

-- -----------------------------------------------------------------
--  Open / Close
-- -----------------------------------------------------------------
function M.open(cfg)
	if is_open() then
		M.close()
		return
	end

	hl_mod.setup()

	state.cfg = cfg
	state.projects = {}
	state.filtered = {}
	state.selected = 1
	state.query = ""
	state.active_tags = {}
	state.mode = "normal"
	state.tag_and = false
	state.tag_multi = false
	state.tag_cursor = 0 -- 0 = "All", 1..n = real tag index
	state.git_status = {}
	state.wins = {}
	state.bufs = {}
	state.ns = {}
	reset_tag_colors()

	state.projects = proj_mod.load(cfg.data_file, cfg.root, cfg.categories, false)
	state.all_tags = proj_mod.all_tags(state.projects)
	state.filtered = proj_mod.filter(state.projects, "", {}, cfg.sort_by, false)

	state.geom = compute_geometry(cfg)
	local g = state.geom

	make_pane("search", g.search, " PhysNav ")
	make_pane("tags", g.tags, " Tags ")
	make_pane("list", g.list, " Projects ")
	make_pane("preview", g.preview, " Preview ")
	make_pane("hints", g.hints, nil)

	-- ── Search pane: buffer-local autocmd + overrides ─────────────────
	-- The shared attach_keymaps set is already on this buffer (for h/l/q/T/
	-- etc. in normal mode). Here we add the search-specific bits: live
	-- filtering as the user types, and keys that make sense only inside the
	-- search bar (CR/Esc/j leave to the list; i/a/I/A re-enter insert).
	local sbuf = state.bufs.search
	local swin = state.wins.search
	local sgroup = api.nvim_create_augroup("PhysNavSearch", { clear = true })

	api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		group = sgroup,
		buffer = sbuf,
		callback = on_search_text_changed,
	})

	-- Prevent the user from navigating onto any other row (we only have one,
	-- but if they pressed 'o' or pasted a multi-line value we'd break).
	api.nvim_create_autocmd("InsertLeave", {
		group = sgroup,
		buffer = sbuf,
		callback = function()
			-- If the user somehow created extra lines, collapse back to one.
			local lc = api.nvim_buf_line_count(sbuf)
			if lc > 1 then
				local first = (api.nvim_buf_get_lines(sbuf, 0, 1, false) or { "" })[1]
				SEARCH_RENDER_GUARD = true
				api.nvim_buf_set_lines(sbuf, 0, -1, false, { first })
				SEARCH_RENDER_GUARD = false
			end
		end,
	})

	-- Search-pane keymaps (override the generic ones for these specific keys).
	local sopts = { buffer = sbuf, noremap = true, silent = true, nowait = true }
	local function smap(mode, key, fn)
		vim.keymap.set(mode, key, fn, sopts)
	end

	-- Leave insert with Esc — standard vim; then another Esc in normal mode
	-- drops back to the list pane without clearing the query.
	smap("i", "<Esc>", function()
		vim.cmd("stopinsert")
	end)
	smap("n", "<Esc>", leave_search_to_list)

	-- In the search pane's normal mode, j/k/<Down>/<Up> should move the
	-- selection in the *list* pane (not the cursor within the one-line
	-- search buffer). This means the user can refine results with arrows
	-- without leaving the search pane first — very fuzzy-finder-like.
	local function move_list_selection(delta)
		state.selected = state.selected + delta
		if state.selected < 1 then
			state.selected = 1
		end
		if state.selected > #state.filtered then
			state.selected = math.max(1, #state.filtered)
		end
		M._render_list()
		M._render_preview()
	end
	smap("n", "j", function()
		move_list_selection(1)
	end)
	smap("n", "k", function()
		move_list_selection(-1)
	end)
	smap("n", "<Down>", function()
		move_list_selection(1)
	end)
	smap("n", "<Up>", function()
		move_list_selection(-1)
	end)
	-- Same idea in insert mode via <C-j>/<C-k> — lets you filter and
	-- navigate without ever leaving insert.
	smap("i", "<C-j>", function()
		move_list_selection(1)
	end)
	smap("i", "<C-k>", function()
		move_list_selection(-1)
	end)
	smap("i", "<C-n>", function()
		move_list_selection(1)
	end)
	smap("i", "<C-p>", function()
		move_list_selection(-1)
	end)

	-- <CR> in insert mode = open the currently-selected project (fzf-style).
	smap("i", "<CR>", function()
		vim.cmd("stopinsert")
		local p = state.filtered[state.selected]
		if not p then
			leave_search_to_list()
			return
		end
		open_project()
	end)

	-- Leave search → list with Enter or l.
	smap("n", "<CR>", leave_search_to_list)
	smap("n", "l", leave_search_to_list)

	-- And from the search bar, h goes sideways into the tag panel directly.
	smap("n", "h", function()
		vim.cmd("stopinsert")
		state.mode = "tags"
		if state.tag_cursor > #state.all_tags then
			state.tag_cursor = math.max(0, #state.all_tags)
		end
		if state.wins.tags and api.nvim_win_is_valid(state.wins.tags) then
			api.nvim_set_current_win(state.wins.tags)
		end
		M._render()
	end)

	-- In insert mode, <C-u> / <C-w> should clear the query (not the prompt).
	smap("i", "<C-u>", function()
		SEARCH_RENDER_GUARD = true
		api.nvim_buf_set_lines(sbuf, 0, -1, false, { SEARCH_PROMPT })
		SEARCH_RENDER_GUARD = false
		api.nvim_win_set_cursor(swin, { 1, #SEARCH_PROMPT })
		state.query = ""
		state.selected = 1
		state.filtered = proj_mod.filter(state.projects, "", state.active_tags, state.cfg.sort_by, state.tag_and)
		M._render_tags()
		M._render_list()
		M._render_preview()
		M._render_hints()
		pcall(apply_titles)
		clear_hl("search")
		add_hl("search", "PhysNavSearchPrompt", 0, 0, #SEARCH_PROMPT)
		add_hl("search", "PhysNavSearchHint", 0, #SEARCH_PROMPT, -1)
	end)

	-- Protect the prompt: Home / ^ / 0 in insert mode should land *after*
	-- the prompt, not at column 0.
	smap("i", "<Home>", function()
		api.nvim_win_set_cursor(swin, { 1, #SEARCH_PROMPT })
	end)
	-- In normal mode, "i" / "a" / "A" should put us back in insert with the
	-- cursor in the right place. `a` at end of line is the common idiom.
	smap("n", "i", function()
		api.nvim_win_set_cursor(swin, { 1, #SEARCH_PROMPT })
		vim.cmd("startinsert")
	end)
	smap("n", "a", function()
		vim.cmd("startinsert!")
	end)
	smap("n", "A", function()
		vim.cmd("startinsert!")
	end)
	smap("n", "I", function()
		api.nvim_win_set_cursor(swin, { 1, #SEARCH_PROMPT })
		vim.cmd("startinsert")
	end)

	-- Auto-close safety: if focus leaves all panes (and isn't in a child
	-- prompt or git log float), close the whole dashboard.
	local group = api.nvim_create_augroup("PhysNavDashboard", { clear = true })
	for _, pane in ipairs(PANES) do
		api.nvim_create_autocmd("WinLeave", {
			group = group,
			buffer = state.bufs[pane],
			callback = function()
				vim.schedule(function()
					if not is_open() then
						return
					end
					local cur = api.nvim_get_current_win()
					-- Still inside any of our panes? OK.
					for _, pn in ipairs(PANES) do
						if state.wins[pn] == cur then
							return
						end
					end
					local cur_buf = api.nvim_win_get_buf(cur)
					local ok_bt, bt = pcall(api.nvim_buf_get_option, cur_buf, "buftype")
					if ok_bt and bt == "prompt" then
						return
					end
					local ok_ch, is_child = pcall(api.nvim_buf_get_var, cur_buf, "physnav_child")
					if ok_ch and is_child then
						return
					end
					M.close()
				end)
			end,
		})
	end

	-- Closing any one pane closes the whole dashboard.
	api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			if not is_open() then
				return
			end
			local closed = tonumber(args.match)
			for _, pane in ipairs(PANES) do
				if state.wins[pane] == closed then
					vim.schedule(M.close)
					return
				end
			end
		end,
	})

	-- Handle editor resize.
	api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			if not is_open() then
				return
			end
			state.geom = compute_geometry(state.cfg)
			local ng = state.geom
			local function resize(pane, geo)
				local w = state.wins[pane]
				if not (w and api.nvim_win_is_valid(w)) then
					return
				end
				pcall(api.nvim_win_set_config, w, {
					relative = "editor",
					row = geo.row,
					col = geo.col,
					width = math.max(6, geo.width - 2),
					height = math.max(1, geo.height - 2),
				})
			end
			resize("search", ng.search)
			resize("tags", ng.tags)
			resize("list", ng.list)
			resize("preview", ng.preview)
			resize("hints", ng.hints)
			M._render()
		end,
	})

	M._render()
	vim.schedule(load_git_statuses)
end

function M.close()
	last_title_state = {}
	local wins = state.wins
	local bufs = state.bufs
	state.wins = {}
	state.bufs = {}
	state.ns = {}
	for _, pane in ipairs(PANES) do
		local w = wins[pane]
		if w and api.nvim_win_is_valid(w) then
			pcall(api.nvim_win_close, w, true)
		end
	end
	for _, pane in ipairs(PANES) do
		local b = bufs[pane]
		if b and api.nvim_buf_is_valid(b) then
			pcall(api.nvim_buf_delete, b, { force = true })
		end
	end
end

return M
