-- biblio.nvim :: init
-- Public entry point. Keep this thin: setup() wires config, everything else
-- is dispatched to sub-modules.

local cfg = require("biblio.config")

local M = {}

--- Set up buffer-local keymaps on topic .md files so that the user can
--- insert paper references without thinking about which command to invoke.
local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("BiblioEditor", { clear = true })
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    group = group,
    pattern = { "*.md", "*.markdown" },
    callback = function(ev)
      local path = vim.api.nvim_buf_get_name(ev.buf)
      if path == "" then return end
      local db = cfg.database_path()
      -- Only wire up for files inside the _database/ directory (topics).
      if path:sub(1, #db + 1) ~= (db .. "/") then return end

      local opts = { buffer = ev.buf, silent = true, nowait = true,
                     desc = "biblio: insert paper reference" }
      vim.keymap.set({ "n", "i" }, "<C-p>",
        function() require("biblio.reference").pick_and_insert() end, opts)
    end,
  })
end

---@param user BiblioConfig|nil
function M.setup(user)
  cfg.setup(user)
  setup_autocmds()
end

function M.open_dashboard()
  require("biblio.dashboard").open()
end

function M.close_dashboard()
  require("biblio.dashboard").close()
end

function M.new_paper()
  require("biblio.paper").prompt_new_paper()
end

function M.new_topic()
  require("biblio.topic").prompt_new_topic()
end

function M.insert_paper_ref()
  require("biblio.reference").pick_and_insert()
end

function M.refresh()
  require("biblio.dashboard").refresh()
end

-- ─── serve ──────────────────────────────────────────────────────────────────

function M.serve(opts)        require("biblio.serve").start(opts) end
function M.serve_stop()       require("biblio.serve").stop() end
function M.serve_status()     require("biblio.serve").status() end
function M.preview(port)      require("biblio.serve").open_browser(port) end

-- ─── git ────────────────────────────────────────────────────────────────────

function M.commit(opts)       require("biblio.git").prompt_commit(opts) end
function M.push()             require("biblio.git").push() end

function M.blog_root()
  return cfg.options.blog_root
end

return M
