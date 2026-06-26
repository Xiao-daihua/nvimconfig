-- biblio.nvim :: topic_ref
--
-- When editing a topic .md file in _database/, this module provides a picker
-- that fuzzy-searches your *other* topics and inserts a wikilink in the form
--
--     [[Topic Title]]
--
-- at the current cursor position. This mirrors reference.lua (which inserts
-- paper links) but targets topic-to-topic connections instead. The site's
-- Library graph resolves [[Topic Title]] automatically, so the title is all
-- we need to write.
--
-- The picker is a floating search bar plus a scrollable result list; typing
-- filters live. The whole search line IS the query (no in-buffer prompt
-- symbol to accidentally edit); a non-editable "› " prompt is drawn as
-- virtual text instead.

local cfg = require("biblio.config")
local scanner = require("biblio.scanner")
local util = require("biblio.util")
local ui = require("biblio.ui")

local M = {}

local NS = vim.api.nvim_create_namespace("biblio_topicref_prompt")

---@param t BiblioTopic
---@return string
local function format_row(t)
	local tags = ""
	if t.tags and #t.tags > 0 then
		tags = "[" .. table.concat(t.tags, ", ") .. "]"
	end
	return string.format("  %-40s  %s", t.title or t.slug, tags)
end

---@param t BiblioTopic
---@param query string
---@return boolean
local function matches(t, query)
	if query == "" then
		return true
	end
	local q = query:lower()
	local hay = (t.title or "")
		.. "\n"
		.. table.concat(t.tags or {}, " ")
		.. "\n"
		.. (t.slug or "")
		.. "\n"
		.. (t.body or "")
	return hay:lower():find(q, 1, true) ~= nil
end

local function render_list(S)
	local lines = {}
	if #S.filtered == 0 then
		table.insert(lines, "  (no matches)")
	else
		for _, t in ipairs(S.filtered) do
			table.insert(lines, format_row(t))
		end
	end
	vim.bo[S.list_buf].modifiable = true
	vim.api.nvim_buf_set_lines(S.list_buf, 0, -1, false, lines)
	vim.bo[S.list_buf].modifiable = false
end

local function recompute(S, query)
	S.filtered = {}
	for _, t in ipairs(S.topics) do
		if matches(t, query) then
			table.insert(S.filtered, t)
		end
	end
	table.sort(S.filtered, function(a, b)
		return (a.title or a.slug or "") < (b.title or b.slug or "")
	end)
	render_list(S)
	if #S.filtered > 0 then
		pcall(vim.api.nvim_win_set_cursor, S.list_win, { 1, 0 })
		if vim.api.nvim_win_is_valid(S.list_win) then
			vim.wo[S.list_win].cursorline = true
		end
	end
end

--- The query is simply the (single) line of the search buffer, trimmed.
local function current_query(S)
	local line = vim.api.nvim_buf_get_lines(S.search_buf, 0, 1, false)[1] or ""
	return (line:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Draw the non-editable "› " prompt as virtual text at the start of line 1.
local function draw_prompt(S)
	vim.api.nvim_buf_clear_namespace(S.search_buf, NS, 0, -1)
	vim.api.nvim_buf_set_extmark(S.search_buf, NS, 0, 0, {
		virt_text = { { "› ", "Comment" } },
		virt_text_pos = "inline",
		right_gravity = false,
	})
end

--- Close both picker windows, restore focus/mode in the target editor.
local function close_picker(S)
	for _, w in ipairs({ S.search_win, S.list_win }) do
		if w and vim.api.nvim_win_is_valid(w) then
			pcall(vim.api.nvim_win_close, w, true)
		end
	end
	if S.target_win and vim.api.nvim_win_is_valid(S.target_win) then
		vim.api.nvim_set_current_win(S.target_win)
		pcall(vim.api.nvim_win_set_cursor, S.target_win, { S.insert_row, S.insert_col })
		if S.was_insert_mode then
			vim.schedule(function()
				vim.cmd("startinsert")
			end)
		end
	end
end

--- Insert the wikilink for `t` at the saved cursor position.
---@param S table
---@param t BiblioTopic
local function do_insert(S, t)
	local text = string.format("[[%s]]", t.title or t.slug)

	local row, col = S.insert_row, S.insert_col -- 1-indexed row, 0-indexed col
	local lines = vim.api.nvim_buf_get_lines(S.target_buf, row - 1, row, false)
	local line = lines[1] or ""
	if col > #line then
		col = #line
	end
	local new_line = line:sub(1, col) .. text .. line:sub(col + 1)
	vim.api.nvim_buf_set_lines(S.target_buf, row - 1, row, false, { new_line })

	S.insert_col = col + #text
	close_picker(S)
end

--- Pick the currently highlighted topic in the list.
local function pick_current(S)
	if #S.filtered == 0 then
		return
	end
	local row = vim.api.nvim_win_get_cursor(S.list_win)[1]
	local t = S.filtered[row]
	if not t then
		return
	end
	do_insert(S, t)
end

--- Entry point. Call this while the cursor is in a topic .md file.
function M.pick_and_insert()
	local target_buf = vim.api.nvim_get_current_buf()
	local target_win = vim.api.nvim_get_current_win()
	local cursor = vim.api.nvim_win_get_cursor(target_win)
	local mode = vim.api.nvim_get_mode().mode
	local cur_path = vim.api.nvim_buf_get_name(target_buf)

	local all = scanner.scan_topics()
	local topics = {}
	for _, t in ipairs(all) do
		if t.path ~= cur_path then
			table.insert(topics, t)
		end
	end
	if #topics == 0 then
		util.notify("No other topics found under " .. cfg.database_path(), vim.log.levels.WARN)
		return
	end

	if mode:match("^i") then
		vim.cmd("stopinsert")
	end

	local total_cols = vim.o.columns
	local total_lines = vim.o.lines - vim.o.cmdheight - 2
	local w = math.min(96, math.max(60, math.floor(total_cols * 0.7)))
	local max_list_h = math.max(8, math.floor(total_lines * 0.6))
	local search_h = 1

	local row = math.floor((total_lines - (search_h + max_list_h + 4)) / 2)
	local col = math.floor((total_cols - w) / 2)

	local search_buf = ui.scratch_buf({ filetype = "biblio_topicref_search" })
	local search_win = vim.api.nvim_open_win(search_buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = w - 2,
		height = search_h,
		style = "minimal",
		border = "rounded",
		title = " Link topic [[…]] ",
		title_pos = "center",
	})

	local list_buf = ui.scratch_buf({ filetype = "biblio_topicref_list" })
	local list_win = vim.api.nvim_open_win(list_buf, false, {
		relative = "editor",
		row = row + search_h + 2,
		col = col,
		width = w - 2,
		height = max_list_h,
		style = "minimal",
		border = "rounded",
	})

	for _, win in ipairs({ search_win, list_win }) do
		vim.wo[win].number = false
		vim.wo[win].relativenumber = false
		vim.wo[win].signcolumn = "no"
		vim.wo[win].wrap = false
		vim.wo[win].winhighlight = "Normal:NormalFloat,CursorLine:Visual"
	end
	vim.wo[list_win].cursorline = true

	local S = {
		topics = topics,
		filtered = {},
		target_buf = target_buf,
		target_win = target_win,
		insert_row = cursor[1],
		insert_col = cursor[2],
		was_insert_mode = mode:match("^i") ~= nil,
		search_buf = search_buf,
		search_win = search_win,
		list_buf = list_buf,
		list_win = list_win,
	}

	-- Start with a genuinely empty editable line; prompt is virtual text only.
	vim.api.nvim_buf_set_lines(search_buf, 0, -1, false, { "" })
	draw_prompt(S)
	vim.api.nvim_win_set_cursor(search_win, { 1, 0 })
	recompute(S, "")

	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		buffer = search_buf,
		callback = function()
			-- Keep the search buffer to a single line; collapse any stray newlines.
			local ls = vim.api.nvim_buf_get_lines(search_buf, 0, -1, false)
			if #ls > 1 then
				vim.api.nvim_buf_set_lines(search_buf, 0, -1, false, { table.concat(ls, " ") })
			end
			draw_prompt(S)
			recompute(S, current_query(S))
		end,
	})

	local map = function(buf, lhs, rhs, mode_)
		vim.keymap.set(mode_ or "n", lhs, rhs, { buffer = buf, silent = true, nowait = true })
	end

	local function move_list(delta)
		if #S.filtered == 0 then
			return
		end
		local cur = vim.api.nvim_win_get_cursor(S.list_win)[1]
		local new = cur + delta
		if new < 1 then
			new = 1
		end
		if new > #S.filtered then
			new = #S.filtered
		end
		pcall(vim.api.nvim_win_set_cursor, S.list_win, { new, 0 })
	end

	map(search_buf, "<Down>", function()
		move_list(1)
	end, "i")
	map(search_buf, "<Up>", function()
		move_list(-1)
	end, "i")
	map(search_buf, "<C-n>", function()
		move_list(1)
	end, "i")
	map(search_buf, "<C-p>", function()
		move_list(-1)
	end, "i")
	map(search_buf, "<CR>", function()
		vim.cmd("stopinsert")
		pick_current(S)
	end, "i")
	map(search_buf, "<Tab>", function()
		vim.api.nvim_set_current_win(list_win)
	end, "i")
	map(search_buf, "<Esc>", function()
		vim.cmd("stopinsert")
		close_picker(S)
	end, "i")
	map(search_buf, "<C-c>", function()
		vim.cmd("stopinsert")
		close_picker(S)
	end, "i")
	map(search_buf, "<C-u>", function()
		vim.api.nvim_buf_set_lines(search_buf, 0, -1, false, { "" })
		draw_prompt(S)
		vim.api.nvim_win_set_cursor(search_win, { 1, 0 })
		recompute(S, "")
	end, "i")
	map(search_buf, "<Esc>", function()
		close_picker(S)
	end, "n")
	map(search_buf, "q", function()
		close_picker(S)
	end, "n")

	map(list_buf, "<CR>", function()
		pick_current(S)
	end)
	map(list_buf, "<Esc>", function()
		close_picker(S)
	end)
	map(list_buf, "q", function()
		close_picker(S)
	end)
	map(list_buf, "j", function()
		move_list(1)
	end)
	map(list_buf, "k", function()
		move_list(-1)
	end)
	map(list_buf, "<Down>", function()
		move_list(1)
	end)
	map(list_buf, "<Up>", function()
		move_list(-1)
	end)
	map(list_buf, "i", function()
		vim.api.nvim_set_current_win(search_win)
		vim.cmd("startinsert!")
	end)
	map(list_buf, "/", function()
		vim.api.nvim_set_current_win(search_win)
		vim.cmd("startinsert!")
	end)

	vim.cmd("startinsert!")
end

return M
