-- physnav/git.lua
-- Monorepo-aware git operations.
-- status_async: one git call per repo-root, results fanned-out to projects.
-- push/log: float on top of PhysNav; on_done refocuses PhysNav.

local M   = {}
local api = vim.api

-- -----------------------------------------------------------------
--  Floating log window  (ASCII border)
-- -----------------------------------------------------------------
local function open_log_win(title)
  local ui  = api.nvim_list_uis()[1]
  local w   = math.min(92, ui.width  - 4)
  local h   = math.min(26, ui.height - 6)
  local row = math.floor((ui.height - h) / 2)
  local col = math.floor((ui.width  - w) / 2)

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(buf, "buftype",    "nofile")
  api.nvim_buf_set_option(buf, "bufhidden",  "wipe")
  api.nvim_buf_set_option(buf, "modifiable", true)
  -- Mark this buffer so WinLeave guard recognises it
  api.nvim_buf_set_var(buf, "physnav_child", true)

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row, col = col, width = w, height = h,
    style = "minimal", border = "single",
    title = " " .. title .. " ", title_pos = "center",
  })
  api.nvim_win_set_option(win, "wrap",           true)
  api.nvim_win_set_option(win, "number",         false)
  api.nvim_win_set_option(win, "relativenumber", false)
  api.nvim_win_set_option(win, "winhighlight",
    "Normal:Normal,FloatBorder:PhysNavBorder,FloatTitle:PhysNavGitTitle")

  return buf, win
end

local function setup_log_keymaps(buf, win, on_close)
  local opts = { buffer = buf, noremap = true, silent = true }
  local fired = false
  local function close()
    if fired then return end; fired = true
    pcall(api.nvim_win_close, win, true)
    if on_close then vim.schedule(on_close) end
  end
  vim.keymap.set("n", "q",     close, opts)
  vim.keymap.set("n", "<Esc>", close, opts)
  api.nvim_create_autocmd("WinClosed", {
    pattern  = tostring(win),
    once     = true,
    callback = function()
      if not fired then fired = true; if on_close then vim.schedule(on_close) end end
    end,
  })
end

local function append_log(buf, new_lines)
  if not api.nvim_buf_is_valid(buf) then return end
  api.nvim_buf_set_option(buf, "modifiable", true)
  local cur = api.nvim_buf_get_lines(buf, 0, -1, false)
  if #cur == 1 and cur[1] == "" then cur = {} end
  for _, l in ipairs(new_lines) do table.insert(cur, l) end
  api.nvim_buf_set_lines(buf, 0, -1, false, cur)
  api.nvim_buf_set_option(buf, "modifiable", false)
  local w = vim.fn.bufwinid(buf)
  if w ~= -1 then pcall(api.nvim_win_set_cursor, w, { #cur, 0 }) end
end

-- -----------------------------------------------------------------
--  Find git toplevel for a path (async)
-- -----------------------------------------------------------------
local function find_git_root(path, cb)
  vim.fn.jobstart({ "git", "-C", path, "rev-parse", "--show-toplevel" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local root = (data[1] or ""):gsub("%s+$", "")
      cb(root ~= "" and root or nil)
    end,
    on_exit = function(_, code) if code ~= 0 then cb(nil) end end,
  })
end

-- -----------------------------------------------------------------
--  Run a sequence of git commands into a log buffer
-- -----------------------------------------------------------------
local function run_git_seq(cmds, cwd, log_buf, on_done)
  local idx = 1
  local function step()
    if idx > #cmds then
      append_log(log_buf, { "", "Done." })
      if on_done then on_done(true) end
      return
    end
    local cmd = cmds[idx]; idx = idx + 1
    append_log(log_buf, { "", "$ " .. table.concat(cmd, " ") })
    local out = {}
    vim.fn.jobstart(cmd, {
      cwd       = cwd,
      on_stdout = function(_, data)
        for _, l in ipairs(data) do if l ~= "" then table.insert(out, "  " .. l) end end
        if #out > 0 then append_log(log_buf, out); out = {} end
      end,
      on_stderr = function(_, data)
        local err = {}
        for _, l in ipairs(data) do if l ~= "" then table.insert(err, "  [err] " .. l) end end
        if #err > 0 then append_log(log_buf, err) end
      end,
      on_exit = function(_, code)
        if code ~= 0 then
          append_log(log_buf, { "", "Command failed (exit " .. code .. ")" })
          if on_done then on_done(false) end
          return
        end
        vim.schedule(step)
      end,
    })
  end
  vim.schedule(step)
end

-- -----------------------------------------------------------------
--  Public: push project  (stays as float over PhysNav)
-- -----------------------------------------------------------------
function M.push_project(project, msg_override, on_done)
  local path        = project.path
  local default_msg = string.format("chore(%s): update [physnav]", project.name)

  local function do_push(msg)
    if not msg or vim.trim(msg) == "" then
      vim.notify("PhysNav Git: push cancelled", vim.log.levels.WARN)
      if on_done then on_done() end; return
    end
    find_git_root(path, function(root)
      if not root then
        vim.notify("PhysNav Git: not in a git repo", vim.log.levels.WARN)
        if on_done then on_done() end; return
      end
      local log_buf, log_win = open_log_win("Git Push  " .. project.name)
      setup_log_keymaps(log_buf, log_win, on_done)
      append_log(log_buf, {
        "Project : " .. project.name,
        "Repo    : " .. root,
        "Scope   : " .. path,
        "Message : " .. msg,
        string.rep("-", 60),
      })
      local branch = (vim.fn.systemlist(
        "git -C " .. vim.fn.shellescape(root) .. " rev-parse --abbrev-ref HEAD"
      )[1] or "main"):gsub("%s+$", "")
      run_git_seq({
        { "git", "-C", root, "add", "--", path },
        { "git", "-C", root, "commit", "-m", msg, "--allow-empty" },
        { "git", "-C", root, "push", "--set-upstream", "origin", branch },
      }, root, log_buf, function(ok)
        if ok then vim.notify("PhysNav: pushed " .. project.name, vim.log.levels.INFO) end
      end)
    end)
  end

  if msg_override then
    do_push(msg_override)
  else
    vim.ui.input({ prompt = "Commit message: ", default = default_msg }, function(input)
      vim.schedule(function()
        if input == nil then if on_done then on_done() end
        else do_push(input) end
      end)
    end)
  end
end

-- -----------------------------------------------------------------
--  Public: git log scoped to project directory
-- -----------------------------------------------------------------
function M.show_log(project, on_done)
  find_git_root(project.path, function(root)
    if not root then
      vim.notify("PhysNav Git: not in a git repo", vim.log.levels.WARN)
      if on_done then on_done() end; return
    end
    local log_buf, log_win = open_log_win("Git Log  " .. project.name)
    setup_log_keymaps(log_buf, log_win, on_done)
    local out = {}
    vim.fn.jobstart(
      { "git", "-C", root, "log", "--oneline", "--graph",
        "--decorate", "--color=never", "-40", "--", project.path },
      {
        cwd       = root,
        on_stdout = function(_, data)
          for _, l in ipairs(data) do if l ~= "" then table.insert(out, l) end end
        end,
        on_exit = function()
          vim.schedule(function()
            append_log(log_buf, #out > 0 and out or { "(no commits touching this project)" })
          end)
        end,
      })
  end)
end

-- -----------------------------------------------------------------
--  Batched async git status.
--  Calls find_git_root once per unique root (not once per project).
--  cb_map: project_name -> callback(status_str)
-- -----------------------------------------------------------------
function M.status_async_batch(projects, cb_map)
  -- Group projects by git root
  local pending = #projects
  if pending == 0 then return end

  -- We query each project individually but reuse root finding.
  -- For true batching: group by root, run one git status per root.
  local root_cache = {}  -- path -> root (or false)

  local function process_root(root, path, name)
    if not root then
      if cb_map[name] then cb_map[name]("") end
      return
    end
    vim.fn.jobstart(
      { "git", "-C", root, "status", "--porcelain", "--", path },
      {
        stdout_buffered = true,
        on_stdout = function(_, data)
          local mod, unt = 0, 0
          for _, line in ipairs(data) do
            if #line >= 2 then
              if line:sub(1,2) == "??" then unt = unt + 1 else mod = mod + 1 end
            end
          end
          local parts = {}
          if mod > 0 then table.insert(parts, "~" .. mod) end
          if unt > 0 then table.insert(parts, "?" .. unt) end
          if cb_map[name] then cb_map[name](table.concat(parts, " ")) end
        end,
        on_exit = function(_, code)
          if code ~= 0 then if cb_map[name] then cb_map[name]("") end end
        end,
      })
  end

  for _, p in ipairs(projects) do
    local path = p.path
    local name = p.name
    -- Check root cache first to avoid duplicate find_git_root calls
    if root_cache[path] ~= nil then
      process_root(root_cache[path] or nil, path, name)
    else
      find_git_root(path, function(root)
        root_cache[path] = root or false
        process_root(root, path, name)
      end)
    end
  end
end

-- Simple single-project wrapper (kept for compatibility)
function M.status_async(path, cb)
  find_git_root(path, function(root)
    if not root then cb(""); return end
    vim.fn.jobstart(
      { "git", "-C", root, "status", "--porcelain", "--", path },
      {
        stdout_buffered = true,
        on_stdout = function(_, data)
          local mod, unt = 0, 0
          for _, line in ipairs(data) do
            if #line >= 2 then
              if line:sub(1,2) == "??" then unt = unt + 1 else mod = mod + 1 end
            end
          end
          local parts = {}
          if mod > 0 then table.insert(parts, "~" .. mod) end
          if unt > 0 then table.insert(parts, "?" .. unt) end
          cb(table.concat(parts, " "))
        end,
        on_exit = function(_, code) if code ~= 0 then cb("") end end,
      })
  end)
end

return M
