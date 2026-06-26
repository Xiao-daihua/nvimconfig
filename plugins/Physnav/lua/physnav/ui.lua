-- physnav/ui.lua  —  v9  "status board + panes"
--
-- Layout (four floating windows):
--
--   ╭─ search ─────────────────────────────────────────────╮
--   │  / type to filter…                                   │   top (1 line)
--   ╰──────────────────────────────────────────────────────╯
--   ╭─ tags ──╮ ╭─ notes 9/24 ─────────────────────────────╮
--   │ ● All   │ │   ▾ WIP   (3)                            │
--   │ ○ qft   │ │       QFT_renorm                         │   tags (left)
--   │ ○ cft   │ │   ▸ IDEA  (5)                            │   list (main)
--   │ …       │ │   ▸ SHELF (16)                           │
--   ╰─────────╯ ╰──────────────────────────────────────────╯
--   ╭─ keys ───────────────────────────────────────────────╮
--   │  j/k move · l open · h fold · w/i/x status · / search │   hints (1 line)
--   ╰──────────────────────────────────────────────────────╯
--
-- The LIST window is the only one you navigate with hjkl. The selection
-- model is driven entirely by the list cursor's buffer line + row_map
-- (single source of truth — no separate index to drift).
--
-- Navigation (in the list pane):
--   j / k   move between landing spots (headers + visible notes)
--   l       header → unfold ; note → open
--   h       header → fold   ; note → fold its bucket (and go to its header)
--   Enter   header → toggle fold ; note → open
--   gg / G  first / last landing spot
--   /       focus the search box (type to filter live)
--   t / Tab jump to the tags pane (j/k move, Enter/Space toggle, q/Tag back)
--
-- Status:  w → WIP   i → IDEA   x → SHELF      Detail: K
-- Actions: p pdf · c compile · g push · L log · e tags · n new · d delete
--          r rescan · ? help · Esc clears filter else closes · q close

local M = {}
local api = vim.api
local proj_mod = require("physnav.projects")
local hl_mod = require("physnav.highlights")
local git_mod = require("physnav.git")

local SEARCH_PROMPT = "  / "

-- ------------------------------------------------------------------
--  State
-- ------------------------------------------------------------------
local PANES = { "search", "tags", "list", "hints" }

local state = {
	cfg = nil,
	wins = {}, -- pane -> winid
	bufs = {}, -- pane -> bufnr
	ns = {}, -- pane -> namespace

	projects = {},
	filtered = {},
	query = "",
	active_tags = {},
	tag_and = false,

	folded = { wip = false, idea = true, shelf = true },
	cursor_line = 1, -- list cursor (1-based buffer line)
	row_map = {}, -- list buffer line -> { kind="header"|"note", ... }
	focus_project = nil,

	mode = "list", -- "list" | "tags" | "search"
	tag_cursor = 1, -- 1 = All, 2..#all+1 = tag rows
	all_tags = {},

	git_status = {},
	geom = nil,
}

local BUCKETS = { "wip", "idea", "shelf" }
local BUCKET_LABEL = { wip = "WIP", idea = "IDEA", shelf = "SHELF" }

-- Tag colour cache.
local TAG_HLS = { "PhysNavTagC1", "PhysNavTagC2", "PhysNavTagC3", "PhysNavTagC4", "PhysNavTagC5", "PhysNavTagC6" }
local tag_color_cache, tag_color_idx = {}, 0
local function reset_tag_colors()
	tag_color_cache, tag_color_idx = {}, 0
end
local function tag_hl(tag)
	if not tag_color_cache[tag] then
		tag_color_idx = (tag_color_idx % #TAG_HLS) + 1
		tag_color_cache[tag] = TAG_HLS[tag_color_idx]
	end
	return tag_color_cache[tag]
end

-- Guard so programmatic writes to the search buffer don't re-fire its autocmd.
local SEARCH_GUARD = false

-- ------------------------------------------------------------------
--  Helpers
-- ------------------------------------------------------------------
local function is_open()
	if vim.tbl_isempty(state.wins) then return false end
	for _, p in ipairs(PANES) do
		local w = state.wins[p]
		if not w or not api.nvim_win_is_valid(w) then return false end
	end
	return true
end

local function dw(s) return vim.fn.strdisplaywidth(s) end

local function trunc(s, max_w)
	if max_w < 1 then return "" end
	if dw(s) <= max_w then return s end
	local r = s
	while dw(r) > max_w - 1 and #r > 0 do r = r:sub(1, -2) end
	return r .. "…"
end

local function set_lines(pane, lines)
	local buf = state.bufs[pane]
	if not (buf and api.nvim_buf_is_valid(buf)) then return end
	vim.bo[buf].modifiable = true
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	if pane ~= "search" then vim.bo[buf].modifiable = false end
end

local function clear_hl(pane)
	local buf, ns = state.bufs[pane], state.ns[pane]
	if buf and ns then api.nvim_buf_clear_namespace(buf, ns, 0, -1) end
end

local function add_hl(pane, group, line0, col_s, col_e)
	local buf, ns = state.bufs[pane], state.ns[pane]
	if buf and ns then pcall(api.nvim_buf_add_highlight, buf, ns, group, line0, col_s, col_e) end
end

-- ------------------------------------------------------------------
--  Geometry: search (top) / tags (left) + list (right) / hints (bottom)
-- ------------------------------------------------------------------
local function compute_geometry(cfg)
	local total_cols = vim.o.columns
	local total_lines = vim.o.lines - vim.o.cmdheight - 2

	local outer_w = math.max(70, math.floor(total_cols * (cfg.width or 0.86)))
	outer_w = math.min(outer_w, total_cols - 2)
	local outer_h = math.max(18, math.floor(total_lines * (cfg.height or 0.86)))
	outer_h = math.min(outer_h, total_lines)
	local outer_row = math.floor((total_lines - outer_h) / 2)
	local outer_col = math.floor((total_cols - outer_w) / 2)

	local search_h, hints_h, gap = 3, 3, 1
	local body_h = outer_h - search_h - hints_h - gap * 2
	if body_h < 8 then body_h = 8 end

	local tags_w = math.max(14, cfg.sidebar_width or 20)
	local list_w = outer_w - tags_w - gap
	if list_w < 30 then
		tags_w = math.max(12, outer_w - 30 - gap)
		list_w = outer_w - tags_w - gap
	end

	return {
		search = { row = outer_row, col = outer_col, width = outer_w, height = search_h },
		tags = { row = outer_row + search_h + gap, col = outer_col, width = tags_w, height = body_h },
		list = { row = outer_row + search_h + gap, col = outer_col + tags_w + gap, width = list_w, height = body_h },
		hints = { row = outer_row + search_h + gap + body_h + gap, col = outer_col, width = outer_w, height = hints_h },
	}
end

-- ------------------------------------------------------------------
--  Filtering / buckets
-- ------------------------------------------------------------------
local function recompute_filter()
	state.filtered = proj_mod.filter(state.projects, state.query, state.active_tags, state.cfg.sort_by, state.tag_and)
end

local function partition_buckets()
	local b = { wip = {}, idea = {}, shelf = {} }
	for _, p in ipairs(state.filtered) do
		local s = p.status or "idea"
		if s ~= "wip" and s ~= "idea" then s = "shelf" end
		table.insert(b[s], p)
	end
	return b
end

-- ------------------------------------------------------------------
--  Selection model (list pane)
-- ------------------------------------------------------------------
local function landing_lines()
	local ls = {}
	for ln, e in pairs(state.row_map) do
		if e.kind == "header" or e.kind == "note" then table.insert(ls, ln) end
	end
	table.sort(ls)
	return ls
end

local function sync_cursor_from_win()
	local w = state.wins.list
	if w and api.nvim_win_is_valid(w) then
		local ok, pos = pcall(api.nvim_win_get_cursor, w)
		if ok and pos then state.cursor_line = pos[1] end
	end
end

local function snap_cursor()
	local ls = landing_lines()
	if #ls == 0 then state.cursor_line = 1 return end
	for _, ln in ipairs(ls) do if ln == state.cursor_line then return end end
	for _, ln in ipairs(ls) do if ln >= state.cursor_line then state.cursor_line = ln return end end
	state.cursor_line = ls[#ls]
end

local function entry_under_cursor() return state.row_map[state.cursor_line] end
local function current_note()
	local e = entry_under_cursor()
	return (e and e.kind == "note") and e.project or nil
end
local function current_header()
	local e = entry_under_cursor()
	return (e and e.kind == "header") and e.bucket or nil
end

-- ------------------------------------------------------------------
--  Render: search pane
-- ------------------------------------------------------------------
local function render_search()
	local buf = state.bufs.search
	if not buf then return end
	SEARCH_GUARD = true
	local line = SEARCH_PROMPT .. (state.query or "")
	vim.bo[buf].modifiable = true
	api.nvim_buf_set_lines(buf, 0, -1, false, { line })
	if state.mode ~= "search" then vim.bo[buf].modifiable = false end
	SEARCH_GUARD = false
	clear_hl("search")
	add_hl("search", "PhysNavSearchPrompt", 0, 0, #SEARCH_PROMPT)
	if state.query == "" and state.mode ~= "search" then
		-- show a faint hint
		SEARCH_GUARD = true
		vim.bo[buf].modifiable = true
		api.nvim_buf_set_lines(buf, 0, -1, false, { SEARCH_PROMPT .. "type to filter…" })
		if state.mode ~= "search" then vim.bo[buf].modifiable = false end
		SEARCH_GUARD = false
		add_hl("search", "PhysNavSearchHint", 0, #SEARCH_PROMPT, -1)
	else
		add_hl("search", "PhysNavSearchText", 0, #SEARCH_PROMPT, -1)
	end
end

-- ------------------------------------------------------------------
--  Render: tags pane
-- ------------------------------------------------------------------
local function tag_active(tag)
	for _, t in ipairs(state.active_tags) do if t == tag then return true end end
	return false
end

local function render_tags()
	local geom = state.geom.tags
	local inner_w = math.max(6, geom.width - 2)
	local lines = { "" }
	-- "All" row
	local all_on = (#state.active_tags == 0)
	table.insert(lines, string.format(" %s All", all_on and "●" or "○"))
	for _, t in ipairs(state.all_tags) do
		local mark = tag_active(t) and "●" or "○"
		table.insert(lines, string.format(" %s %s", mark, trunc(t, inner_w - 3)))
	end

	set_lines("tags", lines)
	clear_hl("tags")

	-- highlight: marker + tag name; active tags get accent.
	-- Row layout: lines[1] padding; lines[2] = All; lines[3..] = tags.
	local all_hl = all_on and "PhysNavTagActive" or "PhysNavTagInactive"
	add_hl("tags", all_hl, 1, 0, -1)
	for i, t in ipairs(state.all_tags) do
		local ln = i + 1 -- 0-based: padding=0, All=1, tag1=2…
		add_hl("tags", "PhysNavTagMarker", ln, 1, 2)
		add_hl("tags", tag_active(t) and "PhysNavTagActive" or tag_hl(t), ln, 3, -1)
	end

	-- Cursor highlight in tags mode: draw a CursorLine-like marker by moving
	-- the real cursor (the window has cursorline on).
	if state.mode == "tags" and state.wins.tags and api.nvim_win_is_valid(state.wins.tags) then
		local target = state.tag_cursor + 1 -- +1 for padding line
		pcall(api.nvim_win_set_cursor, state.wins.tags, { target, 0 })
	end
end

-- ------------------------------------------------------------------
--  Render: list pane
-- ------------------------------------------------------------------
local function render_list()
	local geom = state.geom.list
	local inner_w = math.max(10, geom.width - 2)
	local lines = { "" }
	state.row_map = {}

	local buckets = partition_buckets()
	if #state.filtered == 0 then
		table.insert(lines, "   (no notes match)")
	else
		for _, key in ipairs(BUCKETS) do
			local items = buckets[key]
			local folded = state.folded[key]
			table.insert(lines, string.format("  %s %-6s (%d)", folded and "▸" or "▾", BUCKET_LABEL[key], #items))
			state.row_map[#lines] = { kind = "header", bucket = key }
			if not folded then
				for _, p in ipairs(items) do
					table.insert(lines, "      " .. trunc(p.name, inner_w - 6))
					state.row_map[#lines] = { kind = "note", project = p, bucket = key }
				end
			end
			table.insert(lines, "")
		end
	end

	set_lines("list", lines)
	clear_hl("list")
	for ln, e in pairs(state.row_map) do
		local z = ln - 1
		if e.kind == "header" then
			local hlg = (e.bucket == "wip") and "PhysNavAccentGreen"
				or (e.bucket == "idea") and "PhysNavAccentWarm"
				or "PhysNavMuted"
			add_hl("list", hlg, z, 0, -1)
		elseif e.kind == "note" and e.bucket == "shelf" then
			add_hl("list", "PhysNavMuted", z, 0, -1)
		end
	end

	if state.focus_project then
		for ln, e in pairs(state.row_map) do
			if e.kind == "note" and e.project == state.focus_project then
				state.cursor_line = ln
				break
			end
		end
		state.focus_project = nil
	end
	snap_cursor()
	if state.wins.list and api.nvim_win_is_valid(state.wins.list) then
		pcall(api.nvim_win_set_cursor, state.wins.list, { state.cursor_line, 0 })
	end
end

-- ------------------------------------------------------------------
--  Render: hints pane
-- ------------------------------------------------------------------
local function render_hints()
	local items
	if state.mode == "tags" then
		items = {
			{ "TAGS", "" }, { "j/k", "move" }, { "Enter/Space", "toggle" },
			{ "a", state.tag_and and "AND" or "OR" }, { "t/q", "back to list" },
		}
	elseif state.mode == "search" then
		items = {
			{ "SEARCH", "" }, { "type", "filter live" }, { "Enter/Esc", "back to list" },
		}
	else
		items = {
			{ "j/k", "move" }, { "l", "open/expand" }, { "h", "fold" },
			{ "w/i/x", "wip/idea/shelf" }, { "K", "detail" }, { "/", "search" },
			{ "t", "tags" }, { "n", "new" }, { "p", "pdf" }, { "?", "help" }, { "q", "quit" },
		}
	end

	local parts, ranges, col = {}, {}, 0
	local function add(text, kind)
		table.insert(parts, text)
		table.insert(ranges, { kind, col, col + #text })
		col = col + #text
	end
	add(" ", "sp")
	for i, it in ipairs(items) do
		if i > 1 then add("  ", "sp") end
		add(it[1], "key")
		if it[2] ~= "" then add(" ", "sp"); add(it[2], "desc") end
	end

	set_lines("hints", { table.concat(parts, "") })
	clear_hl("hints")
	for _, r in ipairs(ranges) do
		if r[1] == "key" then
			add_hl("hints", "PhysNavHintKey", 0, r[2], r[3])
		elseif r[1] == "desc" then
			add_hl("hints", "PhysNavHintDesc", 0, r[2], r[3])
		end
	end
end

-- ------------------------------------------------------------------
--  Titles + active-border
-- ------------------------------------------------------------------
local function apply_titles()
	local function set_title(pane, title, active)
		local w = state.wins[pane]
		if not (w and api.nvim_win_is_valid(w)) then return end
		pcall(api.nvim_win_set_config, w, { title = title, title_pos = "center" })
		local wh = active
			and "NormalFloat:NormalFloat,FloatBorder:PhysNavBorderActive,CursorLine:PhysNavCursorLine"
			or "NormalFloat:NormalFloat,FloatBorder:PhysNavBorder,CursorLine:PhysNavCursorLine"
		pcall(function() vim.wo[w].winhighlight = wh end)
	end
	set_title("search", " search ", state.mode == "search")
	local tag_title = " tags "
	if #state.active_tags > 0 then
		tag_title = string.format(" tags [%d] ", #state.active_tags)
	end
	set_title("tags", tag_title, state.mode == "tags")
	set_title("list", string.format(" notes %d/%d ", #state.filtered, #state.projects), state.mode == "list")
	set_title("hints", nil, false)
end

-- ------------------------------------------------------------------
--  Full render + refresh
-- ------------------------------------------------------------------
local function render()
	if not is_open() then return end
	render_search()
	render_tags()
	render_list()
	render_hints()
	apply_titles()
end

local function refresh()
	if not is_open() then return end
	recompute_filter()
	render()
end

-- ------------------------------------------------------------------
--  Focus helpers
-- ------------------------------------------------------------------
local function focus_pane(pane)
	local w = state.wins[pane]
	if w and api.nvim_win_is_valid(w) then pcall(api.nvim_set_current_win, w) end
end

local function focus_list()
	state.mode = "list"
	focus_pane("list")
	render()
end

local function focus_tags()
	state.mode = "tags"
	if state.tag_cursor > #state.all_tags + 1 then state.tag_cursor = 1 end
	focus_pane("tags")
	render()
end

local function refocus_self()
	if is_open() then focus_list() end
end

-- ------------------------------------------------------------------
--  Movement (list)
-- ------------------------------------------------------------------
local function move(delta)
	sync_cursor_from_win()
	local ls = landing_lines()
	if #ls == 0 then return end
	local idx = #ls
	for i, ln in ipairs(ls) do
		if ln >= state.cursor_line then idx = i break end
	end
	local on_landing = (state.row_map[state.cursor_line] ~= nil)
	if not on_landing and delta > 0 then delta = delta - 1 end
	local nxt = math.min(math.max(idx + delta, 1), #ls)
	state.cursor_line = ls[nxt]
	pcall(api.nvim_win_set_cursor, state.wins.list, { state.cursor_line, 0 })
end

local function goto_first()
	local ls = landing_lines()
	if #ls > 0 then state.cursor_line = ls[1]; pcall(api.nvim_win_set_cursor, state.wins.list, { state.cursor_line, 0 }) end
end
local function goto_last()
	local ls = landing_lines()
	if #ls > 0 then state.cursor_line = ls[#ls]; pcall(api.nvim_win_set_cursor, state.wins.list, { state.cursor_line, 0 }) end
end

-- ------------------------------------------------------------------
--  Fold
-- ------------------------------------------------------------------
local function set_fold(b, f) if b and state.folded[b] ~= nil then state.folded[b] = f end end
local function toggle_fold(b) if b and state.folded[b] ~= nil then state.folded[b] = not state.folded[b] end end

-- ------------------------------------------------------------------
--  Open helpers
-- ------------------------------------------------------------------
local function open_neotree(path)
	local ok = pcall(vim.cmd, "Neotree dir=" .. vim.fn.fnameescape(path) .. " reveal")
	if not ok then pcall(vim.cmd, "Explore " .. vim.fn.fnameescape(path)) end
end

-- ------------------------------------------------------------------
--  Actions
-- ------------------------------------------------------------------
local function open_note()
	local p = current_note()
	if not p then return end
	local target = p.path .. "/" .. (p.main or "main.tex")
	local path = p.path
	proj_mod.touch(state.cfg.data_file, state.projects, p.name)
	M.close()
	vim.cmd(state.cfg.open_cmd .. " " .. vim.fn.fnameescape(target))
	pcall(vim.cmd, "cd " .. vim.fn.fnameescape(path))
	vim.schedule(function() open_neotree(path) end)
end

local function open_pdf()
	local p = current_note()
	if not p then return end
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

local function do_compile()
	local p = current_note()
	if not p then return end
	local cmd
	if p.type == "typst" then
		cmd = string.format("cd %s && typst compile %s", vim.fn.fnameescape(p.path), p.main or "main.typ")
	else
		cmd = string.format("cd %s && latexmk -pdf %s", vim.fn.fnameescape(p.path), p.main or "main.tex")
	end
	M.close()
	vim.cmd("botright 12split | terminal " .. cmd)
	vim.cmd("startinsert")
end

local function do_git_push()
	local p = current_note()
	if not p then return end
	git_mod.push_project(p, nil, refocus_self)
end

local function do_git_log()
	local p = current_note()
	if not p then return end
	git_mod.show_log(p, refocus_self)
end

local function do_tag_edit()
	local p = current_note()
	if not p then return end
	vim.ui.input({
		prompt = 'Tags for "' .. p.name .. '" (comma-separated): ',
		default = table.concat(p.tags or {}, ", "),
	}, function(input)
		if input ~= nil then
			local new_tags = {}
			for tag in input:gmatch("[^,]+") do
				local t = vim.trim(tag)
				if t ~= "" then table.insert(new_tags, t) end
			end
			proj_mod.update_tags(state.cfg.data_file, state.projects, p.name, new_tags)
			state.all_tags = proj_mod.all_tags(state.projects)
			reset_tag_colors()
		end
		refocus_self()
		refresh()
	end)
end

local function set_note_status(new_status)
	local p = current_note()
	if not p then
		vim.notify("PhysNav: move the cursor onto a note first", vim.log.levels.INFO)
		return
	end
	proj_mod.set_status(state.cfg.data_file, state.projects, p.name, new_status)
	p.status = new_status
	set_fold(new_status, false)
	state.focus_project = p
	vim.notify(string.format("PhysNav: %s → %s", p.name, BUCKET_LABEL[new_status]), vim.log.levels.INFO)
	refresh()
end

-- hjkl semantics
local function key_l()
	sync_cursor_from_win()
	local hb = current_header()
	if hb then set_fold(hb, false); render(); return end
	if current_note() then open_note() end
end
local function key_h()
	sync_cursor_from_win()
	local hb = current_header()
	if hb then set_fold(hb, true); render(); return end
	local e = entry_under_cursor()
	if e and e.kind == "note" then
		local bucket = e.bucket
		for ln, ee in pairs(state.row_map) do
			if ee.kind == "header" and ee.bucket == bucket then state.cursor_line = ln break end
		end
		set_fold(bucket, true)
		render()
	end
end
local function key_enter_list()
	sync_cursor_from_win()
	local hb = current_header()
	if hb then toggle_fold(hb); render(); return end
	if current_note() then open_note() end
end

-- ------------------------------------------------------------------
--  Detail popup
-- ------------------------------------------------------------------
local function show_detail_popup()
	local p = current_note()
	if not p then return end
	local gs = state.git_status[p.name]
	local lines = {
		"  " .. p.name, "",
		"  status   " .. (p.status or "idea"),
		"  type     " .. (p.type or "-"),
		"  category " .. (p.category or "-"),
		"  main     " .. (p.main or "-"),
		"  pdf      " .. (p.has_pdf and "yes" or "no"),
		"  git      " .. ((gs and gs ~= "") and gs or "clean"),
		"  tags     " .. ((p.tags and #p.tags > 0) and table.concat(p.tags, ", ") or "-"),
		"  path     " .. (p.path or "-"), "",
		"  (q / Esc to close)",
	}
	local width = 2
	for _, l in ipairs(lines) do width = math.max(width, #l + 2) end
	local height = #lines
	local buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	local win = api.nvim_open_win(buf, true, {
		relative = "editor",
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		width = width, height = height,
		style = "minimal", border = "rounded", title = " detail ",
	})
	pcall(function() vim.wo[win].winhighlight = "NormalFloat:NormalFloat,FloatBorder:PhysNavBorder" end)
	local function close()
		if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
		refocus_self()
	end
	for _, k in ipairs({ "q", "<Esc>", "<CR>" }) do
		vim.keymap.set("n", k, close, { buffer = buf, nowait = true, silent = true })
	end
end

-- ------------------------------------------------------------------
--  Tags pane interaction
-- ------------------------------------------------------------------
local function tag_toggle_current()
	if state.tag_cursor == 1 then
		state.active_tags = {}
	else
		local tag = state.all_tags[state.tag_cursor - 1]
		if tag then
			if tag_active(tag) then
				local nt = {}
				for _, t in ipairs(state.active_tags) do if t ~= tag then table.insert(nt, t) end end
				state.active_tags = nt
			else
				table.insert(state.active_tags, tag)
			end
		end
	end
	refresh()
end

-- ------------------------------------------------------------------
--  New note wizard (preserved; status defaults to IDEA)
-- ------------------------------------------------------------------
local function do_new_note()
	local cfg = state.cfg
	local function refocus() refocus_self() end

	local templates = cfg.templates or {}
	if #templates == 0 then
		vim.notify("PhysNav: no templates configured. Set `templates = {...}` in physnav.setup().", vim.log.levels.ERROR)
		refocus()
		return
	end

	local tmpl, category, name, new_tags

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
						vim.notify("PhysNav: clone failed (code " .. code .. ") from " .. tmpl.url, vim.log.levels.ERROR)
						refocus()
						return
					end
					vim.fn.jobstart({ "rm", "-rf", dest .. "/.git" }, {
						on_exit = function(_, _)
							vim.schedule(function()
								local new_proj = {
									name = name, category = category, path = dest,
									type = proj_type, main = main_file, lec_count = 0,
									has_pdf = false, tags = new_tags, last_opened = os.time(),
									status = "idea",
								}
								proj_mod.add_project(cfg.data_file, state.projects, new_proj)
								state.all_tags = proj_mod.all_tags(state.projects)
								reset_tag_colors()
								vim.notify(string.format("PhysNav: created %s/%s from '%s'", category, name, tmpl.label), vim.log.levels.INFO)
								set_fold("idea", false)
								state.focus_project = new_proj
								refresh()
								M.close()
								vim.cmd(cfg.open_cmd .. " " .. vim.fn.fnameescape(dest .. "/" .. main_file))
								pcall(vim.cmd, "cd " .. vim.fn.fnameescape(dest))
								vim.schedule(function() open_neotree(dest) end)
							end)
						end,
					})
				end)
			end,
		})
	end

	local function step3_name_and_tags()
		vim.ui.input({ prompt = "Project name: " }, function(input)
			if not input or vim.trim(input) == "" then refocus() return end
			name = vim.trim(input):gsub("%s+", "_")
			vim.ui.input({ prompt = "Tags (comma-separated, blank ok): " }, function(tag_input)
				new_tags = {}
				if tag_input and vim.trim(tag_input) ~= "" then
					for tag in tag_input:gmatch("[^,]+") do
						local t = vim.trim(tag)
						if t ~= "" then table.insert(new_tags, t) end
					end
				end
				vim.schedule(step4_clone)
			end)
		end)
	end

	local function step2_category()
		vim.ui.select(cfg.categories, { prompt = "Category:" }, function(sel)
			if not sel then refocus() return end
			category = sel
			vim.schedule(step3_name_and_tags)
		end)
	end

	if #templates == 1 then
		tmpl = templates[1]
		vim.schedule(step2_category)
		return
	end
	vim.ui.select(templates, {
		prompt = "Template:",
		format_item = function(t) return string.format("%s   [%s]", t.label, t.type or "typst") end,
	}, function(sel)
		if not sel then refocus() return end
		tmpl = sel
		vim.schedule(step2_category)
	end)
end

-- ------------------------------------------------------------------
--  Delete (preserved)
-- ------------------------------------------------------------------
local function detect_trash_cmd()
	for _, cmd in ipairs({ "trash", "trash-put", "gio trash" }) do
		local bin = cmd:match("^(%S+)")
		if vim.fn.executable(bin) == 1 then return cmd end
	end
	return nil
end

local function do_delete_project()
	local p = current_note()
	if not p then return end
	local trash_cmd = state.cfg.trash_cmd or detect_trash_cmd()
	local method = trash_cmd and "trash" or "PERMANENTLY DELETE"
	vim.ui.input({ prompt = string.format('[%s] Confirm name to delete "%s": ', method, p.name) }, function(input)
		if input == nil or vim.trim(input) ~= p.name then
			vim.notify("PhysNav: delete cancelled", vim.log.levels.INFO)
			refocus_self()
			return
		end
		local path, name = p.path, p.name
		local function after(ok)
			vim.schedule(function()
				if ok then
					proj_mod.remove_project(state.cfg.data_file, state.projects, name)
					state.all_tags = proj_mod.all_tags(state.projects)
					reset_tag_colors()
					vim.notify("PhysNav: deleted " .. name, vim.log.levels.INFO)
				else
					vim.notify("PhysNav: delete failed: " .. name, vim.log.levels.ERROR)
				end
				refocus_self()
				refresh()
			end)
		end
		if trash_cmd then
			local parts = vim.split(trash_cmd, " ")
			table.insert(parts, path)
			vim.fn.jobstart(parts, { on_exit = function(_, c) after(c == 0) end })
		else
			vim.fn.jobstart({ "rm", "-rf", path }, { on_exit = function(_, c) after(c == 0) end })
		end
	end)
end

-- ------------------------------------------------------------------
--  Git status (async)
-- ------------------------------------------------------------------
local function load_git_statuses()
	local cb_map = {}
	for _, p in ipairs(state.projects) do
		cb_map[p.name] = function(s) state.git_status[p.name] = s or "" end
	end
	git_mod.status_async_batch(state.projects, cb_map)
end

-- ------------------------------------------------------------------
--  Help
-- ------------------------------------------------------------------
local function show_help()
	vim.notify(table.concat({
		"PhysNav — status board",
		string.rep("-", 46),
		"  Buckets:  WIP (writing) · IDEA (new notes) · SHELF (rest)",
		"",
		"  List nav (hjkl):",
		"    j/k move · l open/expand · h fold · Enter toggle/open",
		"    gg/G first/last",
		"  Status:  w → WIP   i → IDEA   x → SHELF",
		"  Note:    K detail · p pdf · c compile · g push · L log",
		"           e tags · n new · d delete",
		"  Search:  / focuses the top box; type to filter live; Esc back",
		"  Tags:    t (or Tab) enters the left pane; j/k move,",
		"           Enter/Space toggle, a AND/OR, t/q back",
		"  Misc:    r rescan · Esc clears filter else closes · q close",
	}, "\n"), vim.log.levels.INFO, { title = "PhysNav" })
end

-- ------------------------------------------------------------------
--  Keymaps
-- ------------------------------------------------------------------
local function attach_list_keymaps()
	local buf = state.bufs.list
	local opts = { buffer = buf, noremap = true, silent = true, nowait = true }
	local function map(k, fn) vim.keymap.set("n", k, fn, opts) end

	map("j", function() move(1) end)
	map("k", function() move(-1) end)
	map("<Down>", function() move(1) end)
	map("<Up>", function() move(-1) end)
	map("gg", goto_first)
	map("G", goto_last)

	map("l", key_l)
	map("<Right>", key_l)
	map("h", key_h)
	map("<Left>", key_h)
	map("<CR>", key_enter_list)
	map("<2-LeftMouse>", key_enter_list)

	map("w", function() set_note_status("wip") end)
	map("i", function() set_note_status("idea") end)
	map("x", function() set_note_status("shelf") end)

	map("K", show_detail_popup)
	map("p", open_pdf)
	map("c", function() vim.schedule(do_compile) end)
	map("g", function() vim.schedule(do_git_push) end)
	map("L", function() vim.schedule(do_git_log) end)
	map("e", function() vim.schedule(do_tag_edit) end)
	map("n", function() vim.schedule(do_new_note) end)
	map("d", function() vim.schedule(do_delete_project) end)

	map("/", function()
		state.mode = "search"
		focus_pane("search")
		render_search()
		apply_titles()
		vim.bo[state.bufs.search].modifiable = true
		local b = state.bufs.search
		local line = (api.nvim_buf_get_lines(b, 0, 1, false) or { "" })[1] or SEARCH_PROMPT
		-- if showing the hint, clear to just the prompt
		if line:find("type to filter", 1, true) then
			SEARCH_GUARD = true
			api.nvim_buf_set_lines(b, 0, -1, false, { SEARCH_PROMPT .. (state.query or "") })
			SEARCH_GUARD = false
		end
		pcall(api.nvim_win_set_cursor, state.wins.search, { 1, #(SEARCH_PROMPT .. (state.query or "")) })
		vim.cmd("startinsert!")
	end)
	map("t", focus_tags)
	map("T", focus_tags)
	map("<Tab>", focus_tags)
	map("r", function()
		state.projects = proj_mod.scan_and_save()
		state.all_tags = proj_mod.all_tags(state.projects)
		state.git_status = {}
		reset_tag_colors()
		refresh()
		load_git_statuses()
		vim.notify("PhysNav: rescanned", vim.log.levels.INFO)
	end)
	map("?", show_help)
	map("<Esc>", function()
		if state.query ~= "" or #state.active_tags > 0 then
			state.query = ""
			state.active_tags = {}
			state.tag_and = false
			refresh()
		else
			M.close()
		end
	end)
	map("q", function() M.close() end)
end

local function attach_tags_keymaps()
	local buf = state.bufs.tags
	local opts = { buffer = buf, noremap = true, silent = true, nowait = true }
	local function map(k, fn) vim.keymap.set("n", k, fn, opts) end

	local function tmove(delta)
		state.tag_cursor = math.min(math.max(state.tag_cursor + delta, 1), #state.all_tags + 1)
		render_tags()
	end
	map("j", function() tmove(1) end)
	map("k", function() tmove(-1) end)
	map("<Down>", function() tmove(1) end)
	map("<Up>", function() tmove(-1) end)
	map("gg", function() state.tag_cursor = 1; render_tags() end)
	map("G", function() state.tag_cursor = #state.all_tags + 1; render_tags() end)
	map("<CR>", function() tag_toggle_current() end)
	map("<Space>", function() tag_toggle_current() end)
	map("a", function()
		state.tag_and = not state.tag_and
		vim.notify("tag logic: " .. (state.tag_and and "AND" or "OR"))
		refresh()
	end)
	-- leave tags pane back to list
	map("t", focus_list)
	map("T", focus_list)
	map("<Tab>", focus_list)
	map("l", focus_list)
	map("<Right>", focus_list)
	map("q", focus_list)
	map("<Esc>", focus_list)
	map("?", show_help)
end

local function attach_search_keymaps()
	local buf = state.bufs.search
	local opts = { buffer = buf, noremap = true, silent = true, nowait = true }

	-- Live filter as the user types.
	local grp = api.nvim_create_augroup("PhysNavSearch", { clear = true })
	api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		group = grp, buffer = buf,
		callback = function()
			if SEARCH_GUARD then return end
			if not is_open() then return end
			local raw = (api.nvim_buf_get_lines(buf, 0, 1, false) or { "" })[1] or ""
			local q
			if raw:sub(1, #SEARCH_PROMPT) == SEARCH_PROMPT then
				q = raw:sub(#SEARCH_PROMPT + 1)
			else
				q = raw
				SEARCH_GUARD = true
				api.nvim_buf_set_lines(buf, 0, -1, false, { SEARCH_PROMPT .. q })
				SEARCH_GUARD = false
				pcall(api.nvim_win_set_cursor, state.wins.search, { 1, #SEARCH_PROMPT + #q })
			end
			if q == state.query then return end
			state.query = q
			if q ~= "" then state.folded = { wip = false, idea = false, shelf = false } end
			recompute_filter()
			render_list()
			render_tags()
			render_hints()
			apply_titles()
			-- keep search-text highlight
			clear_hl("search")
			add_hl("search", "PhysNavSearchPrompt", 0, 0, #SEARCH_PROMPT)
			add_hl("search", "PhysNavSearchText", 0, #SEARCH_PROMPT, -1)
		end,
	})

	local function leave_to_list()
		vim.cmd("stopinsert")
		focus_list()
	end
	vim.keymap.set("i", "<Esc>", function() vim.cmd("stopinsert") end, opts)
	vim.keymap.set("i", "<CR>", leave_to_list, opts)
	vim.keymap.set("n", "<Esc>", leave_to_list, opts)
	vim.keymap.set("n", "<CR>", leave_to_list, opts)
	vim.keymap.set("n", "q", leave_to_list, opts)
end

-- ------------------------------------------------------------------
--  Pane creation
-- ------------------------------------------------------------------
local function make_pane(pane, geom, title, enter)
	local buf = api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = (pane == "search")
	local opts = {
		relative = "editor",
		row = geom.row, col = geom.col,
		width = math.max(6, geom.width - 2),
		height = math.max(1, geom.height - 2),
		style = "minimal", border = "rounded",
	}
	if title then opts.title = title; opts.title_pos = "center" end
	local win = api.nvim_open_win(buf, enter or false, opts)
	vim.wo[win].wrap = false
	if pane == "list" or pane == "tags" then vim.wo[win].cursorline = true end
	pcall(function()
		vim.wo[win].winhighlight = "NormalFloat:NormalFloat,FloatBorder:PhysNavBorder,CursorLine:PhysNavCursorLine"
	end)
	state.wins[pane] = win
	state.bufs[pane] = buf
	state.ns[pane] = api.nvim_create_namespace("PhysNav_" .. pane)
end

-- ------------------------------------------------------------------
--  Open / Close
-- ------------------------------------------------------------------
function M.open(cfg)
	if is_open() then M.close() return end

	hl_mod.setup()
	state.cfg = cfg
	state.query = ""
	state.active_tags = {}
	state.tag_and = false
	state.folded = { wip = false, idea = true, shelf = true }
	state.cursor_line = 1
	state.row_map = {}
	state.focus_project = nil
	state.mode = "list"
	state.tag_cursor = 1
	state.git_status = {}
	state.wins = {}
	state.bufs = {}
	state.ns = {}
	reset_tag_colors()

	state.projects = proj_mod.load(cfg.data_file, cfg.root, cfg.categories, false)
	state.all_tags = proj_mod.all_tags(state.projects)
	recompute_filter()

	state.geom = compute_geometry(cfg)
	local g = state.geom
	make_pane("search", g.search, " search ", false)
	make_pane("tags", g.tags, " tags ", false)
	make_pane("list", g.list, " notes ", true) -- focus the list
	make_pane("hints", g.hints, nil, false)

	attach_list_keymaps()
	attach_tags_keymaps()
	attach_search_keymaps()

	-- Close-tracking: when the list window closes, tear everything down.
	local grp = api.nvim_create_augroup("PhysNavClose", { clear = true })
	api.nvim_create_autocmd("WinClosed", {
		group = grp, pattern = tostring(state.wins.list), once = true,
		callback = function() vim.schedule(M.close) end,
	})

	render()
	focus_list()
	load_git_statuses()
end

function M.close()
	pcall(function() api.nvim_del_augroup_by_name("PhysNavClose") end)
	pcall(function() api.nvim_del_augroup_by_name("PhysNavSearch") end)
	for _, pane in ipairs(PANES) do
		local w = state.wins[pane]
		if w and api.nvim_win_is_valid(w) then pcall(api.nvim_win_close, w, true) end
	end
	state.wins = {}
	state.bufs = {}
	state.ns = {}
end

M._state = state

return M
