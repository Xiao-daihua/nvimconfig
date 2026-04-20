-- biblio.nvim :: git
--
-- Minimal git workflow: stage everything under blog_root, commit with a
-- user-supplied message, optionally push.
--
-- The commit UI shows `git status --short` in a preview float, and has an
-- editable message area above the status. Keys:
--   <CR> in normal      commit (with optional push prompt)
--   p                   commit and push (skip the prompt)
--   q / <Esc> normal    cancel
--
-- We never force-push, never touch other branches, never amend. Only the
-- simplest path.

local cfg  = require("biblio.config")
local util = require("biblio.util")
local ui   = require("biblio.ui")

local M = {}

--- Run a git command synchronously in blog_root, returning (stdout, code).
---@param args string[]
---@return string stdout, integer code, string stderr
local function git(args)
  local cmd = { "git", "-C", cfg.options.blog_root }
  for _, a in ipairs(args) do table.insert(cmd, a) end
  if vim.system then
    local res = vim.system(cmd, { text = true }):wait(15000)
    return res.stdout or "", res.code or -1, res.stderr or ""
  else
    -- Fallback for Neovim < 0.10
    local shelled = {}
    for _, a in ipairs(cmd) do table.insert(shelled, vim.fn.shellescape(a)) end
    local stdout = vim.fn.system(table.concat(shelled, " "))
    return stdout, vim.v.shell_error, ""
  end
end

--- Is blog_root a git repo?
local function is_repo()
  local _, code = git({ "rev-parse", "--is-inside-work-tree" })
  return code == 0
end

--- git status --short output.
---@return string[] lines
local function status_short()
  local out = git({ "status", "--short" })
  local lines = {}
  for line in (out .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then table.insert(lines, line) end
  end
  return lines
end

--- Current branch name (empty on error).
local function current_branch()
  local out, code = git({ "rev-parse", "--abbrev-ref", "HEAD" })
  if code ~= 0 then return "" end
  return (out:gsub("%s+$", ""))
end

--- Does the current branch have an upstream?
local function has_upstream()
  local _, code = git({ "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" })
  return code == 0
end

--- Actually perform the commit and optional push.
---@param message string
---@param do_push boolean
local function do_commit(message, do_push)
  if message == "" then
    util.notify("Commit aborted: empty message.", vim.log.levels.WARN)
    return
  end

  util.notify("Staging changes…")
  local _, add_code, add_err = git({ "add", "-A" })
  if add_code ~= 0 then
    util.notify("git add failed: " .. add_err, vim.log.levels.ERROR)
    return
  end

  -- Any staged changes?
  local _, diff_code = git({ "diff", "--cached", "--quiet" })
  if diff_code == 0 then
    util.notify("Nothing to commit (working tree clean).", vim.log.levels.WARN)
    return
  end

  util.notify("Committing…")
  local _, commit_code, commit_err = git({ "commit", "-m", message })
  if commit_code ~= 0 then
    util.notify("git commit failed: " .. commit_err, vim.log.levels.ERROR)
    return
  end

  if not do_push then
    util.notify("Committed. (Use :Biblio push to push.)")
    return
  end

  if not has_upstream() then
    local branch = current_branch()
    util.notify("No upstream set; use `git push -u origin " .. branch .. "` once manually.",
      vim.log.levels.WARN)
    return
  end

  util.notify("Pushing…")
  local push_out, push_code, push_err = git({ "push" })
  if push_code ~= 0 then
    util.notify("git push failed: " .. push_err .. "\n" .. push_out, vim.log.levels.ERROR)
    return
  end
  util.notify("Pushed to origin.")
end

--- Open the commit UI: float with status + message input.
---@param opts table|nil { push?: boolean }   push=true skips the ask-to-push
function M.prompt_commit(opts)
  opts = opts or {}

  if not is_repo() then
    util.notify(cfg.options.blog_root .. " is not a git repo.", vim.log.levels.ERROR)
    return
  end

  local status = status_short()
  if #status == 0 then
    util.notify("Working tree clean — nothing to commit.")
    return
  end

  local branch = current_branch()
  local upstream = has_upstream()

  -- Build the layout content
  local header = {
    string.format("  Branch: %s%s", branch, upstream and "" or "  (no upstream)"),
    string.format("  Repo:   %s", cfg.options.blog_root),
    "",
    "  Changes to commit:",
    "  ─────────────────────────────────────────",
  }
  for _, s in ipairs(status) do table.insert(header, "    " .. s) end
  table.insert(header, "  ─────────────────────────────────────────")
  table.insert(header, "")
  table.insert(header, "  Commit message (edit below the ▶ marker):")
  table.insert(header, "  ▶")

  local buf = ui.scratch_buf({ filetype = "gitcommit" })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, header)
  -- Remember where the message starts so we can extract just that part.
  local msg_start_row = #header   -- 1-indexed, the line AFTER "  ▶"
  -- Add one empty editable line
  vim.api.nvim_buf_set_lines(buf, msg_start_row, msg_start_row, false, { "" })
  vim.bo[buf].modifiable = true

  local total_cols  = vim.o.columns
  local total_lines = vim.o.lines - vim.o.cmdheight - 2
  local w = math.min(86, math.max(60, math.floor(total_cols  * 0.7)))
  local h = math.min(#status + 14, total_lines - 4)
  local row = math.floor((total_lines - h) / 2)
  local col = math.floor((total_cols  - w) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row, col = col,
    width = w, height = h,
    style = "minimal", border = "rounded",
    title = " Commit to git ", title_pos = "center",
  })
  vim.wo[win].number      = false
  vim.wo[win].signcolumn  = "no"
  vim.wo[win].wrap        = true
  vim.wo[win].cursorline  = false

  -- Put cursor on the message line in insert mode
  vim.api.nvim_win_set_cursor(win, { msg_start_row + 1, 0 })
  vim.cmd("startinsert!")

  local closed = false
  local function close()
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function extract_message()
    local lines = vim.api.nvim_buf_get_lines(buf, msg_start_row, -1, false)
    -- Join, strip leading/trailing whitespace
    return (table.concat(lines, "\n"):gsub("^%s+", ""):gsub("%s+$", ""))
  end

  local function submit(push)
    local msg = extract_message()
    close()
    if msg == "" then
      util.notify("Commit aborted: empty message.", vim.log.levels.WARN)
      return
    end
    if push == nil then
      -- Ask
      local answer = vim.fn.confirm("Commit done. Push now?", "&Yes\n&No", 2)
      push = (answer == 1)
    end
    do_commit(msg, push)
  end

  local function cancel()
    close()
    util.notify("Commit cancelled.")
  end

  local map = function(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = buf, silent = true, nowait = true })
  end
  -- Normal mode submit / push / cancel
  map("n", "<CR>", function() submit(opts.push) end)
  map("n", "<C-s>", function() submit(opts.push) end)
  map("n", "p",    function() submit(true) end)
  map("n", "q",    cancel)
  -- Insert mode: <C-s> commits without leaving insert first.
  map("i", "<C-s>", function() vim.cmd("stopinsert"); submit(opts.push) end)
  -- <Esc> in insert → drops to normal (Vim default). Not mapped.
end

--- Push without opening UI.
function M.push()
  if not is_repo() then
    util.notify(cfg.options.blog_root .. " is not a git repo.", vim.log.levels.ERROR); return
  end
  if not has_upstream() then
    util.notify("No upstream set for " .. current_branch() .. ".", vim.log.levels.WARN); return
  end
  util.notify("Pushing…")
  local out, code, err = git({ "push" })
  if code ~= 0 then
    util.notify("git push failed: " .. err .. "\n" .. out, vim.log.levels.ERROR)
  else
    util.notify("Pushed.")
  end
end

return M
