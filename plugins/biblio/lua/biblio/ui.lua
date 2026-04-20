-- biblio.nvim :: ui
-- Thin wrappers over Neovim's windowing primitives. Kept dependency-free.
-- Everything renders in floating windows so the dashboard can own the screen
-- without disturbing the user's regular buffers.

local M = {}

--- Create a scratch buffer with nice defaults for a floating window.
---@param opts table|nil
---@return integer buf
function M.scratch_buf(opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile  = false
  if opts.filetype then vim.bo[buf].filetype = opts.filetype end
  if opts.name then
    pcall(vim.api.nvim_buf_set_name, buf, opts.name)
  end
  return buf
end

--- Centered floating window sized relative to the editor.
---@param buf integer
---@param width_frac number   e.g. 0.6
---@param height_frac number
---@param title string|nil
---@param border string|nil   "single"|"rounded"|... default "rounded"
---@return integer win
function M.center_float(buf, width_frac, height_frac, title, border)
  local cols  = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight - 2
  local w = math.max(40, math.floor(cols  * width_frac))
  local h = math.max(10, math.floor(lines * height_frac))
  local row = math.floor((lines - h) / 2)
  local col = math.floor((cols  - w) / 2)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row      = row,
    col      = col,
    width    = w,
    height   = h,
    style    = "minimal",
    border   = border or "rounded",
    title    = title,
    title_pos = title and "center" or nil,
  })
  return win
end

--- Open a multi-line input float.
---
--- Modes:
---   n: <CR>   submit
---   n: <C-s>  submit
---   n: q      close
---   i: <C-s> submit
---   i: <Esc> drops to normal mode (Vim default — no mapping)
---
--- Set `start_insert = true` when the float is primarily for typing (e.g.
--- pasting BibTeX). Otherwise the float opens in normal mode.
---@param opts { title?:string, filetype?:string, initial?:string[], width_frac?:number, height_frac?:number, start_insert?:boolean }
---@param on_submit fun(text:string)
---@param on_cancel fun()|nil
function M.multiline_input(opts, on_submit, on_cancel)
  opts = opts or {}
  local buf = M.scratch_buf({ filetype = opts.filetype })
  local win = M.center_float(buf,
    opts.width_frac  or 0.7,
    opts.height_frac or 0.5,
    opts.title or "biblio: input")
  if opts.initial and #opts.initial > 0 then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.initial)
  end
  vim.bo[buf].modifiable = true

  local closed = false
  local function close()
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    close()
    on_submit(table.concat(lines, "\n"))
  end
  local function cancel()
    close()
    if on_cancel then on_cancel() end
  end

  local map = function(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  -- Submit
  map("n", "<CR>",  submit)
  map("n", "<C-s>", submit)
  map("i", "<C-s>", function() vim.cmd("stopinsert"); submit() end)
  -- Close from normal mode only; <Esc> in insert is left unmapped so Vim's
  -- default mode-switch behavior applies.
  map("n", "q",     cancel)

  if opts.start_insert then vim.cmd("startinsert") end
end

--- Single-line input with a prompt line at the top of the float.
---@param opts { title?:string, prompt?:string, default?:string, width_frac?:number }
---@param on_submit fun(text:string)
---@param on_cancel fun()|nil
function M.line_input(opts, on_submit, on_cancel)
  opts = opts or {}
  local buf = M.scratch_buf({})
  local win = M.center_float(buf, opts.width_frac or 0.5, 0.12,
    opts.title or "biblio: input")
  local initial = opts.default or ""
  local lines = {}
  if opts.prompt then table.insert(lines, opts.prompt) end
  table.insert(lines, initial)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local input_row = #lines - 1
  vim.api.nvim_win_set_cursor(win, { input_row + 1, #initial })
  vim.cmd("startinsert!")

  local closed = false
  local function close()
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function submit()
    local all = vim.api.nvim_buf_get_lines(buf, input_row, input_row + 1, false)
    close()
    on_submit((all[1] or ""):gsub("^%s+", ""):gsub("%s+$", ""))
  end
  local function cancel()
    close()
    if on_cancel then on_cancel() end
  end

  local map = function(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  -- Submit: <CR> in either mode (insert also stops insert first)
  map("n", "<CR>", submit)
  map("i", "<CR>", function() vim.cmd("stopinsert"); submit() end)
  -- Close only from normal mode via q. <Esc> in insert drops to normal
  -- (Vim default, unmapped); <Esc> in normal is a no-op.
  map("n", "q", cancel)
end

--- Multi-select picker backed by a plain buffer. Each line is one item.
--- <Tab> toggles selection, <CR> submits, n adds a new item, <Esc> cancels.
---@param opts { title?:string, items:string[], allow_new?:boolean, new_prompt?:string }
---@param on_submit fun(selected:string[])
---@param on_cancel fun()|nil
function M.multi_select(opts, on_submit, on_cancel)
  opts = opts or {}
  local items = {}
  for _, v in ipairs(opts.items or {}) do table.insert(items, v) end
  local selected = {}       -- item -> true

  local buf = M.scratch_buf({})
  local win = M.center_float(buf, 0.5, 0.5, opts.title or "biblio: select")

  local function header()
    local help
    if opts.allow_new then
      help = "<Tab> toggle  <CR> submit  n new  <Esc> cancel"
    else
      help = "<Tab> toggle  <CR> submit  <Esc> cancel"
    end
    return { help, string.rep("─", 60), "" }
  end

  local function render()
    local lines = header()
    for _, item in ipairs(items) do
      local marker = selected[item] and "[x] " or "[ ] "
      table.insert(lines, marker .. item)
    end
    if #items == 0 then
      table.insert(lines, "(no existing items)")
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end

  render()
  -- Put cursor on first selectable line
  pcall(vim.api.nvim_win_set_cursor, win, { 4, 0 })

  local header_rows = #header()

  local function current_item()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local idx = row - header_rows
    if idx < 1 or idx > #items then return nil end
    return items[idx]
  end

  local closed = false
  local function close()
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function toggle()
    local item = current_item()
    if not item then return end
    selected[item] = not selected[item] or nil
    render()
  end

  local function add_new()
    if not opts.allow_new then return end
    M.line_input({ title = "New item", prompt = opts.new_prompt or "New:" },
      function(text)
        if text == "" then return end
        if not vim.tbl_contains(items, text) then
          table.insert(items, text)
        end
        selected[text] = true
        render()
      end)
  end

  local function submit()
    local out = {}
    for _, item in ipairs(items) do
      if selected[item] then table.insert(out, item) end
    end
    close()
    on_submit(out)
  end

  local function cancel()
    close()
    if on_cancel then on_cancel() end
  end

  local map = function(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  map("<Tab>",  toggle)
  map("<Space>", toggle)
  map("<CR>",   submit)
  map("n",      add_new)
  map("<Esc>",  cancel)
  map("q",      cancel)
end

--- Yes/no confirmation. Uses vim.fn.confirm since it's synchronous and
--- renders in the cmdline — perfect for brief checks like "delete this?".
---@param prompt string
---@return boolean
function M.confirm(prompt)
  local choice = vim.fn.confirm(prompt, "&Yes\n&No", 2)
  return choice == 1
end

return M
