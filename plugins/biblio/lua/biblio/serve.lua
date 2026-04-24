-- biblio.nvim :: serve
--
-- Run `bundle exec jekyll serve` in the background against the user's blog
-- so they can preview edits at http://127.0.0.1:4000/ . We keep the handle
-- around so we can tell the user whether a server is already running and
-- stop it on demand.

local cfg  = require("biblio.config")
local util = require("biblio.util")

local M = {}

---@class ServeState
---@field job integer             jobstart id
---@field started_at integer      os.time()
---@field bufnr integer|nil       optional terminal buffer if we used termopen

---@type ServeState|nil
local S = nil

--- Is jekyll currently running under our control?
---@return boolean
function M.is_running()
  if not S then return false end
  -- `jobwait` with timeout 0 returns -1 if still running, nonneg exit code
  -- otherwise.
  local res = vim.fn.jobwait({ S.job }, 0)[1]
  return res == -1
end

--- Start `bundle exec jekyll serve`. If a server is already running, no-op
--- and notify.
---@param opts table|nil { port?: integer, host?: string, open_browser?: boolean }
function M.start(opts)
  opts = opts or {}
  if M.is_running() then
    util.notify("jekyll is already running (pid job=" .. tostring(S.job) .. ")",
      vim.log.levels.WARN)
    return
  end

  if vim.fn.executable("bundle") == 0 then
    util.notify("`bundle` not found on PATH. Install bundler (gem install bundler).",
      vim.log.levels.ERROR)
    return
  end

  local cmd = { "bundle", "exec", "jekyll", "serve" }
  if opts.port then table.insert(cmd, "--port");  table.insert(cmd, tostring(opts.port)) end
  if opts.host then table.insert(cmd, "--host");  table.insert(cmd, opts.host) end
  if opts.livereload then table.insert(cmd, "--livereload") end

  -- Capture stderr/stdout and show a short trailing snippet on failure.
  local output_lines = {}
  local function on_output(_, data, _)
    if not data then return end
    for _, line in ipairs(data) do
      if line and line ~= "" then
        table.insert(output_lines, line)
        if #output_lines > 200 then
          table.remove(output_lines, 1)
        end
      end
    end
  end

  local job = vim.fn.jobstart(cmd, {
    cwd = cfg.options.blog_root,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = on_output,
    on_stderr = on_output,
    on_exit = function(_, code, _)
      S = nil
      if code == 0 then
        util.notify("jekyll stopped cleanly.")
      else
        util.notify(string.format("jekyll exited with code %d", code),
          vim.log.levels.WARN)
        -- Surface a short summary of the last few output lines.
        local tail = {}
        local start = math.max(1, #output_lines - 5)
        for i = start, #output_lines do table.insert(tail, output_lines[i]) end
        if #tail > 0 then
          util.notify("jekyll output (tail):\n" .. table.concat(tail, "\n"),
            vim.log.levels.WARN)
        end
      end
    end,
  })

  if job <= 0 then
    util.notify("Failed to start jekyll (jobstart returned " .. tostring(job) .. ")",
      vim.log.levels.ERROR)
    return
  end

  S = { job = job, started_at = os.time() }

  local port = opts.port or 4000
  local host = opts.host or "127.0.0.1"
  util.notify(string.format("jekyll starting at http://%s:%d/ (job=%d; :Biblio serve_stop to stop)",
    host, port, job))
end

--- Stop a running server.
function M.stop()
  if not M.is_running() then
    util.notify("jekyll is not running.", vim.log.levels.WARN)
    return
  end
  -- Graceful: SIGTERM then SIGKILL after a beat.
  vim.fn.jobstop(S.job)
  util.notify("jekyll stop requested.")
end

--- Toggle: start if stopped, stop if running.
function M.toggle()
  if M.is_running() then
    M.stop()
  else
    M.start()
  end
end

--- Show status.
function M.status()
  if M.is_running() then
    local uptime = os.time() - S.started_at
    util.notify(string.format("jekyll is running (job=%d, up %ds).", S.job, uptime))
  else
    util.notify("jekyll is not running.")
  end
end

--- Try to open the preview URL in the OS default browser. Doesn't depend
--- on whether our server is running — if the user prefers a different
--- server, this still opens the URL.
---@param port integer|nil
function M.open_browser(port)
  port = port or 4000
  local url = string.format("http://127.0.0.1:%d/", port)
  local openers = {
    "xdg-open",   -- Linux
    "open",       -- macOS
    "wslview",    -- WSL
  }
  for _, o in ipairs(openers) do
    if vim.fn.executable(o) == 1 then
      vim.fn.jobstart({ o, url }, { detach = true })
      util.notify("Opening " .. url)
      return
    end
  end
  util.notify("Could not find an opener (xdg-open/open/wslview). URL: " .. url,
    vim.log.levels.WARN)
end

return M
