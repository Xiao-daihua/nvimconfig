-- biblio.nvim :: reference
--
-- When editing a topic .md file in _database/, this module provides a picker
-- that fuzzy-searches your existing papers and inserts a link in the form
--
--     [Title](/papers/slug/)
--
-- at the current cursor position. The picker is a floating search bar plus
-- a scrollable result list; typing filters live.

local cfg     = require("biblio.config")
local scanner = require("biblio.scanner")
local util    = require("biblio.util")
local ui      = require("biblio.ui")

local M = {}

---@class RefPickerState
---@field papers BiblioPaper[]     Full list
---@field filtered BiblioPaper[]   Current filtered view
---@field target_buf integer       The topic .md buffer we'll insert into
---@field target_win integer       The window containing target_buf
---@field insert_row integer       1-indexed row in target_buf
---@field insert_col integer       0-indexed col in target_buf
---@field was_insert_mode boolean  Whether the target was in insert mode
---@field search_buf integer
---@field search_win integer
---@field list_buf integer
---@field list_win integer

---@param p BiblioPaper
---@return string
local function format_row(p)
  local year = tostring(p.year or "")
  if year == "" then year = "----" end
  local authors
  if p.authors and #p.authors > 0 then
    authors = p.authors[1]
    if #p.authors > 1 then authors = authors .. " et al." end
  else
    authors = "(unknown)"
  end
  return string.format("  %-4s  %-22s  %s", year, authors, p.title or p.slug)
end

---@param p BiblioPaper
---@param query string
---@return boolean
local function matches(p, query)
  if query == "" then return true end
  local q = query:lower()
  local hay = (p.title or "") .. "\n" .. table.concat(p.authors or {}, " ") .. "\n" ..
              tostring(p.year or "") .. "\n" .. (p.slug or "") .. "\n" ..
              (p.journal or "") .. "\n" .. (p.arxiv or "") .. "\n" .. (p.doi or "")
  return hay:lower():find(q, 1, true) ~= nil
end

local SEARCH_PROMPT = "  › "

local function strip_prompt(line)
  line = line or ""
  local stripped = line:gsub("^%s*›%s*", "")
  return (stripped:gsub("^%s+", ""))
end

local function render_list(S)
  local lines = {}
  if #S.filtered == 0 then
    table.insert(lines, "  (no matches)")
  else
    for _, p in ipairs(S.filtered) do table.insert(lines, format_row(p)) end
  end
  vim.bo[S.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(S.list_buf, 0, -1, false, lines)
  vim.bo[S.list_buf].modifiable = false
end

local function recompute(S, query)
  S.filtered = {}
  for _, p in ipairs(S.papers) do
    if matches(p, query) then table.insert(S.filtered, p) end
  end
  table.sort(S.filtered, function(a, b)
    -- Heuristic: newer first, otherwise title.
    local ay = tonumber(a.year) or 0
    local by = tonumber(b.year) or 0
    if ay ~= by then return ay > by end
    return (a.title or "") < (b.title or "")
  end)
  render_list(S)
  -- Reset cursor on the list to the first row when filter changes.
  if #S.filtered > 0 then
    pcall(vim.api.nvim_win_set_cursor, S.list_win, { 1, 0 })
  end
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
    -- Put cursor back where it was, and resume insert if needed.
    pcall(vim.api.nvim_win_set_cursor, S.target_win, { S.insert_row, S.insert_col })
    if S.was_insert_mode then
      vim.schedule(function()
        -- Re-entering insert at the cursor. "a" keeps us at current column.
        vim.cmd("startinsert")
        -- If the column was at end-of-line we'd need startinsert!, but we
        -- restore explicitly so regular startinsert is fine.
      end)
    end
  end
end

--- Insert the markdown link for `p` at the saved cursor position.
---@param S RefPickerState
---@param p BiblioPaper
local function do_insert(S, p)
  local text = string.format("[%s](%s%s/)",
    p.title or p.slug,
    cfg.options.paper_url_prefix,
    p.slug)

  local row, col = S.insert_row, S.insert_col   -- 1-indexed row, 0-indexed col
  local lines = vim.api.nvim_buf_get_lines(S.target_buf, row - 1, row, false)
  local line  = lines[1] or ""
  -- Clamp col in case the line is shorter (shouldn't happen, but safe).
  if col > #line then col = #line end
  local new_line = line:sub(1, col) .. text .. line:sub(col + 1)
  vim.api.nvim_buf_set_lines(S.target_buf, row - 1, row, false, { new_line })

  -- Move cursor to end of inserted text.
  S.insert_col = col + #text
  close_picker(S)
end

--- Pick the currently highlighted paper in the list.
local function pick_current(S)
  if #S.filtered == 0 then return end
  local row = vim.api.nvim_win_get_cursor(S.list_win)[1]
  local p = S.filtered[row]
  if not p then return end
  do_insert(S, p)
end

--- Entry point. Call this while the cursor is in a topic .md file.
function M.pick_and_insert()
  local target_buf = vim.api.nvim_get_current_buf()
  local target_win = vim.api.nvim_get_current_win()
  local cursor     = vim.api.nvim_win_get_cursor(target_win)
  local mode       = vim.api.nvim_get_mode().mode

  -- Scan papers. Always fresh — the user might have added papers in this same
  -- session and we want them available.
  local papers = scanner.scan_papers()
  if #papers == 0 then
    util.notify("No papers found under " .. cfg.papers_path(), vim.log.levels.WARN)
    return
  end

  -- Leave insert mode before opening floats, so they can take focus cleanly.
  if mode:match("^i") then vim.cmd("stopinsert") end

  local total_cols  = vim.o.columns
  local total_lines = vim.o.lines - vim.o.cmdheight - 2
  local w = math.min(96, math.max(60, math.floor(total_cols  * 0.7)))
  local max_list_h = math.max(8, math.floor(total_lines * 0.6))
  local search_h = 1

  local row = math.floor((total_lines - (search_h + max_list_h + 4)) / 2)
  local col = math.floor((total_cols  - w) / 2)

  local search_buf = ui.scratch_buf({ filetype = "biblio_ref_search" })
  local search_win = vim.api.nvim_open_win(search_buf, true, {
    relative = "editor",
    row = row, col = col,
    width = w - 2, height = search_h,
    style = "minimal", border = "rounded",
    title = " Insert paper reference ",
    title_pos = "center",
  })

  local list_buf = ui.scratch_buf({ filetype = "biblio_ref_list" })
  local list_win = vim.api.nvim_open_win(list_buf, false, {
    relative = "editor",
    row = row + search_h + 2,     -- below search float incl. its borders
    col = col,
    width = w - 2, height = max_list_h,
    style = "minimal", border = "rounded",
  })

  for _, win in ipairs({ search_win, list_win }) do
    vim.wo[win].number         = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn     = "no"
    vim.wo[win].wrap           = false
    vim.wo[win].winhighlight   = "Normal:NormalFloat,CursorLine:Visual"
  end
  vim.wo[list_win].cursorline = true

  local S = {
    papers = papers, filtered = {},
    target_buf = target_buf, target_win = target_win,
    insert_row = cursor[1], insert_col = cursor[2],
    was_insert_mode = mode:match("^i") ~= nil,
    search_buf = search_buf, search_win = search_win,
    list_buf = list_buf, list_win = list_win,
  }

  -- Seed
  vim.api.nvim_buf_set_lines(search_buf, 0, -1, false, { SEARCH_PROMPT })
  vim.api.nvim_win_set_cursor(search_win, { 1, #SEARCH_PROMPT })
  recompute(S, "")

  -- Live filter on typing
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = search_buf,
    callback = function()
      local line = vim.api.nvim_buf_get_lines(search_buf, 0, 1, false)[1] or ""
      recompute(S, strip_prompt(line))
    end,
  })

  local map = function(buf, lhs, rhs, mode_)
    vim.keymap.set(mode_ or "n", lhs, rhs,
      { buffer = buf, silent = true, nowait = true })
  end

  -- Search buffer: arrow / Ctrl-n/p navigate list without leaving input.
  local function move_list(delta)
    if #S.filtered == 0 then return end
    local cur = vim.api.nvim_win_get_cursor(S.list_win)[1]
    local new = cur + delta
    if new < 1 then new = 1 end
    if new > #S.filtered then new = #S.filtered end
    pcall(vim.api.nvim_win_set_cursor, S.list_win, { new, 0 })
  end

  map(search_buf, "<Down>", function() move_list(1) end,  "i")
  map(search_buf, "<Up>",   function() move_list(-1) end, "i")
  map(search_buf, "<C-n>",  function() move_list(1) end,  "i")
  map(search_buf, "<C-p>",  function() move_list(-1) end, "i")
  map(search_buf, "<CR>",   function() vim.cmd("stopinsert"); pick_current(S) end, "i")
  map(search_buf, "<Tab>",  function() vim.api.nvim_set_current_win(list_win) end, "i")
  map(search_buf, "<Esc>",  function() vim.cmd("stopinsert"); close_picker(S) end, "i")
  map(search_buf, "<C-c>",  function() vim.cmd("stopinsert"); close_picker(S) end, "i")
  map(search_buf, "<C-u>",  function()
    vim.api.nvim_buf_set_lines(search_buf, 0, -1, false, { SEARCH_PROMPT })
    vim.api.nvim_win_set_cursor(search_win, { 1, #SEARCH_PROMPT })
    recompute(S, "")
  end, "i")
  -- Normal mode fallbacks
  map(search_buf, "<Esc>", function() close_picker(S) end, "n")
  map(search_buf, "q",     function() close_picker(S) end, "n")

  -- List buffer: j/k navigate, Enter picks, Esc closes.
  map(list_buf, "<CR>", function() pick_current(S) end)
  map(list_buf, "<Esc>", function() close_picker(S) end)
  map(list_buf, "q",    function() close_picker(S) end)
  map(list_buf, "i",    function()
    vim.api.nvim_set_current_win(search_win)
    vim.cmd("startinsert!")
  end)
  map(list_buf, "/",    function()
    vim.api.nvim_set_current_win(search_win)
    vim.cmd("startinsert!")
  end)

  -- Start in insert mode on the search bar so the user can just start typing.
  vim.cmd("startinsert!")
end

return M
