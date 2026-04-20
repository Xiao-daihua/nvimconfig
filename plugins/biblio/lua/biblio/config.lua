-- biblio.nvim :: config
-- Centralizes defaults and user overrides.

local M = {}

---@class BiblioConfig
---@field blog_root string           Path to the Jekyll repo root (contains _database/ and _papers/)
---@field database_dir string        Relative to blog_root
---@field papers_dir string          Relative to blog_root
---@field paper_url_prefix string    URL prefix used in topic links, e.g. "/papers/"
---@field open_cmd string            How to open a file from dashboard: "edit" | "tabedit" | "vsplit" | "split"
---@field arxiv_api string
---@field crossref_api string
---@field request_timeout_ms integer
---@field keymaps table<string,string>  Dashboard buffer-local keymaps

M.defaults = {
  -- Resolved at setup time. If nil, we try cwd, then git root.
  blog_root          = nil,
  database_dir       = "_database",
  papers_dir         = "_papers",
  paper_url_prefix   = "/papers/",
  open_cmd           = "edit",
  arxiv_api          = "https://export.arxiv.org/api/query",
  crossref_api       = "https://api.crossref.org/works",
  request_timeout_ms = 10000,

  -- Whether to auto-open neo-tree at blog_root when the dashboard opens.
  -- Set to false if you prefer to manage your file tree manually.
  open_neotree       = true,

  keymaps = {
    new_paper     = "np",
    new_topic     = "nt",
    search        = "/",
    focus_tags    = "t",
    focus_topics  = "T",
    focus_papers  = "P",
    open_item     = "<CR>",
    delete_item   = "d",
    refresh       = "r",
    help          = "?",
    quit          = "q",
    -- jekyll preview & git ops
    serve         = "s",
    preview       = "S",   -- open browser at current preview
    commit        = "gc",
    push          = "gp",
    sync          = "gs",  -- commit + push in one go
  },
}

M.options = vim.deepcopy(M.defaults)

--- Merge user config on top of defaults.
---@param user table|nil
function M.setup(user)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user or {})
  M.options.blog_root = M.resolve_blog_root(M.options.blog_root)
end

--- Try user-provided path, else cwd if it looks like a Jekyll repo, else git root.
---@param provided string|nil
---@return string
function M.resolve_blog_root(provided)
  local function looks_like_repo(p)
    if not p or p == "" then return false end
    return vim.fn.isdirectory(p .. "/_database") == 1
       and vim.fn.isdirectory(p .. "/_papers") == 1
  end

  if provided then
    provided = vim.fn.expand(provided)
    if looks_like_repo(provided) then return provided end
  end

  local cwd = vim.fn.getcwd()
  if looks_like_repo(cwd) then return cwd end

  -- Walk up looking for _database + _papers
  local dir = cwd
  for _ = 1, 8 do
    if looks_like_repo(dir) then return dir end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then break end
    dir = parent
  end

  -- Fall back; commands will error with a clear message if paths are bogus.
  return provided and vim.fn.expand(provided) or cwd
end

function M.database_path()
  return M.options.blog_root .. "/" .. M.options.database_dir
end

function M.papers_path()
  return M.options.blog_root .. "/" .. M.options.papers_dir
end

return M
