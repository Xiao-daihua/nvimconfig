-- biblio.nvim :: util
-- Small helpers: slugify, filename collision resolution, YAML escaping.

local M = {}

--- ASCII-ish slug suitable for filenames.
---@param s string
---@return string
function M.slugify(s)
  if not s then return "" end
  s = s:lower()
  s = s:gsub("[^%w]+", "")
  return s
end

--- Escape a string for a YAML double-quoted scalar.
---@param s string
---@return string
function M.yaml_escape(s)
  if not s then return "" end
  s = s:gsub("\\", "\\\\")
  s = s:gsub('"', '\\"')
  s = s:gsub("\r?\n", " ")
  s = s:gsub("%s+", " ")
  return s
end

--- Read a file fully; returns nil on failure.
---@param path string
---@return string|nil
function M.read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

--- Write content to a file atomically-ish (write + rename).
---@param path string
---@param content string
---@return boolean ok, string|nil err
function M.write_file(path, content)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "w")
  if not f then return false, err end
  f:write(content)
  f:close()
  local ok, rerr = os.rename(tmp, path)
  if not ok then
    os.remove(tmp)
    return false, rerr
  end
  return true
end

--- Check if a file exists.
---@param path string
---@return boolean
function M.file_exists(path)
  return vim.fn.filereadable(path) == 1
end

--- List .md files in a directory (no recursion).
---@param dir string
---@return string[]  absolute paths
function M.list_md(dir)
  local out = {}
  if vim.fn.isdirectory(dir) == 0 then return out end
  local entries = vim.fn.readdir(dir)
  for _, name in ipairs(entries) do
    if name:match("%.md$") then
      table.insert(out, dir .. "/" .. name)
    end
  end
  table.sort(out)
  return out
end

--- Generate a unique paper filename given a base (without suffix).
--- Sticks to your existing scheme: "1989-moore", "1989-moore2", "1989-moore3", ...
---@param dir string                absolute dir
---@param base string               e.g. "1989-moore"
---@return string filename          e.g. "1989-moore2.md"
---@return string absolute_path
function M.unique_paper_filename(dir, base)
  local candidate = base .. ".md"
  if not M.file_exists(dir .. "/" .. candidate) then
    return candidate, dir .. "/" .. candidate
  end
  local n = 2
  while true do
    candidate = base .. tostring(n) .. ".md"
    if not M.file_exists(dir .. "/" .. candidate) then
      return candidate, dir .. "/" .. candidate
    end
    n = n + 1
    if n > 999 then error("Could not find a free filename under " .. base) end
  end
end

--- Next numeric prefix for a topic file.
--- Your topics are named "0001...", "0002...", ..., "0010majoranacft.md".
--- The prefix is always exactly 4 digits — note that "00013dgravity.md" is
--- 0001 + "3dgravity", not 00013 + "dgravity".
---@param dir string
---@return string  4-digit padded string
function M.next_topic_prefix(dir)
  local max = 0
  if vim.fn.isdirectory(dir) == 1 then
    for _, name in ipairs(vim.fn.readdir(dir)) do
      local num = name:match("^(%d%d%d%d)")
      if num then
        local n = tonumber(num)
        if n and n > max then max = n end
      end
    end
  end
  return string.format("%04d", max + 1)
end

--- Unique topic filename. Base is "NNNN" + slug.
---@param dir string
---@param slug string
---@return string filename, string absolute_path
function M.unique_topic_filename(dir, slug)
  local prefix = M.next_topic_prefix(dir)
  local base = prefix .. slug
  local candidate = base .. ".md"
  -- Collision is very unlikely given the prefix, but handle it anyway.
  local n = 2
  while M.file_exists(dir .. "/" .. candidate) do
    candidate = base .. tostring(n) .. ".md"
    n = n + 1
  end
  return candidate, dir .. "/" .. candidate
end

--- Strip ".md" and any leading path from a file path.
---@param path string
---@return string
function M.slug_of(path)
  local name = vim.fn.fnamemodify(path, ":t:r")
  return name
end

--- Trim whitespace.
---@param s string
---@return string
function M.trim(s)
  if not s then return "" end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Split a string on a Lua pattern.
---@param s string
---@param sep string  Lua pattern
---@return string[]
function M.split(s, sep)
  local out = {}
  for part in (s .. sep):gmatch("(.-)" .. sep) do
    table.insert(out, part)
  end
  return out
end

--- Deduplicate a list while preserving order.
---@generic T
---@param list T[]
---@return T[]
function M.uniq(list)
  local seen, out = {}, {}
  for _, v in ipairs(list) do
    if not seen[v] then
      seen[v] = true
      table.insert(out, v)
    end
  end
  return out
end

--- URL encode (minimal, enough for DOI/arxiv ids).
---@param s string
---@return string
function M.url_encode(s)
  if not s then return "" end
  return (s:gsub("([^%w%-_%./~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

--- Notify helper that stays quiet if nvim-notify isn't around.
---@param msg string
---@param level integer|nil  vim.log.levels.*
function M.notify(msg, level)
  vim.notify("[biblio] " .. msg, level or vim.log.levels.INFO)
end

-- Window/buffer categorization constants. Filetypes fall into three groups
-- for the purpose of opening files from biblio:
--
--   SIDEBAR_FT   — never touch these (file trees, outlines, help, quickfix).
--                  We skip past them when picking a target window.
--   STARTUP_FT   — startup-screen plugins that live in nofile buffers but are
--                  absolutely meant to be replaced when the user opens a
--                  real file. Treat them as editable.
--   (everything else is evaluated on buftype.)

local SIDEBAR_FT = {
  ["neo-tree"]       = true,
  ["NvimTree"]       = true,
  ["nerdtree"]       = true,
  ["aerial"]         = true,
  ["Outline"]        = true,
  ["outline"]        = true,
  ["Trouble"]        = true,
  ["trouble"]        = true,
  ["qf"]             = true,
  ["help"]           = true,
  ["fugitive"]       = true,
  ["DiffviewFiles"]  = true,
  ["DiffviewFileHistory"] = true,
  ["neo-tree-popup"] = true,
  ["TelescopePrompt"] = true,
}

local STARTUP_FT = {
  ["dashboard"]      = true,    -- dashboard-nvim
  ["alpha"]          = true,    -- alpha-nvim
  ["starter"]        = true,    -- mini.starter
  ["snacks_dashboard"] = true,  -- snacks.nvim
  ["startify"]       = true,    -- vim-startify
  ["ministarter"]    = true,    -- mini.starter (alternate name)
}

--- Is this window a "normal" editor window suitable for :edit'ing into?
---@param win integer
---@return boolean
function M.is_editable_window(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  local cfg_ = vim.api.nvim_win_get_config(win)
  if cfg_.relative and cfg_.relative ~= "" then return false end  -- float

  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype

  if SIDEBAR_FT[ft] then return false end
  if STARTUP_FT[ft] then return true end   -- startups are meant to be replaced

  local bt = vim.bo[buf].buftype
  -- Empty buftype = regular editable buffer. Everything else (nofile, help,
  -- quickfix, terminal, prompt) we skip.
  return bt == ""
end

--- Find a window in the current tab safe to :edit into. Returns nil if none.
---
--- Preference order:
---   1. A startup screen (dashboard-nvim / alpha / etc) — these are *meant*
---      to be replaced when the user opens a file.
---   2. The current window if it's editable.
---   3. Any other normal editor window.
---@return integer|nil
function M.find_target_editor_window()
  local wins = vim.api.nvim_tabpage_list_wins(0)

  -- Pass 1: startup screens take highest priority.
  for _, win in ipairs(wins) do
    if M.is_editable_window(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if STARTUP_FT[vim.bo[buf].filetype] then return win end
    end
  end

  -- Pass 2: the current window, if it's editable.
  local cur = vim.api.nvim_get_current_win()
  if M.is_editable_window(cur) then return cur end

  -- Pass 3: any other normal editor window.
  for _, win in ipairs(wins) do
    if M.is_editable_window(win) then return win end
  end

  return nil
end

--- Close extra editor splits in the current tab, keeping only `keep_win`.
--- Sidebars (neo-tree etc.) are preserved. This is how we make picking a
--- paper feel like "replace what's open" rather than "add another split".
---@param keep_win integer
local function close_extra_editor_splits(keep_win)
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    if win ~= keep_win and M.is_editable_window(win) then
      pcall(vim.api.nvim_win_close, win, false)
    end
  end
end

--- Apply user's global window options to the current window (after opening
--- a file, to undo any float / sidebar inheritance).
function M.apply_user_winopts()
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].number         = vim.o.number
  vim.wo[win].relativenumber = vim.o.relativenumber
  vim.wo[win].signcolumn     = vim.o.signcolumn
  vim.wo[win].foldcolumn     = vim.o.foldcolumn
  vim.wo[win].wrap           = vim.o.wrap
  vim.wo[win].cursorline     = vim.o.cursorline
  vim.wo[win].winhighlight   = ""
end

--- Open `path` for editing, choosing a sensible target window. Honors
--- `open_cmd` from config (default: "edit").
---
--- When `open_cmd == "edit"`:
---   - Focus a suitable target window (startup screen > current > any editor).
---   - If the only windows are sidebars/floats, create a new split.
---   - Close any OTHER non-sidebar splits so the user ends up with a
---     single-file view (plus their sidebars), instead of accumulating
---     horizontal splits on every pick.
---
--- For non-edit open_cmds (tabedit, vsplit, split) we only focus a target
--- first so the new split/tab doesn't inherit sidebar settings; we do NOT
--- close other splits (that would defeat the user's explicit choice).
---@param path string
---@param open_cmd string   "edit" | "tabedit" | "vsplit" | "split"
function M.open_file_for_editing(path, open_cmd)
  local escaped = vim.fn.fnameescape(path)
  local target = M.find_target_editor_window()

  if target then
    vim.api.nvim_set_current_win(target)
  elseif open_cmd == "edit" then
    -- No normal/startup window exists. Make one so we don't :edit a sidebar.
    vim.cmd("botright new")
    target = vim.api.nvim_get_current_win()
  end

  vim.cmd(open_cmd .. " " .. escaped)

  if open_cmd == "edit" then
    -- After :edit, the current window holds the file. Close other editor
    -- splits (keeping sidebars/floats). This is what makes opening a paper
    -- feel like "replace the current view" rather than "pile up splits".
    local kept = vim.api.nvim_get_current_win()
    close_extra_editor_splits(kept)
  end

  M.apply_user_winopts()
end

return M
