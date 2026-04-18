local M = {}

M.config = {
  root          = vim.fn.expand("~/Phys"),
  data_file     = vim.fn.stdpath("data") .. "/physnav_projects.json",
  open_cmd      = "edit",
  width         = 0.92,
  height        = 0.88,
  preview_width = 32,
  sidebar_width = 22,
  -- List of subdirectories under root to scan for projects.
  -- Add new category folders here without touching plugin code.
  categories    = { "EPFL_lecture", "Notes" },
  -- "name" | "recent"  (recent = last-opened first)
  sort_by       = "recent",
  -- Typst template repo to clone when creating a new note
  typst_template = "https://github.com/Xiao-daihua/typst_template",
  -- Trash command: "trash" (trash-cli), "gio trash", or nil (permanent rm!)
  trash_cmd     = nil,  -- auto-detected at runtime
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

function M.open()
  require("physnav.ui").open(M.config)
end

return M
