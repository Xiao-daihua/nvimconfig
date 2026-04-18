if vim.g.loaded_physnav then
  return
end
vim.g.loaded_physnav = true

vim.api.nvim_create_user_command("PhysNav", function()
  require("physnav").open()
end, { desc = "Open PhysNav project browser" })

vim.api.nvim_create_user_command("PhysNavScan", function()
  require("physnav.projects").scan_and_save()
  vim.notify("PhysNav: project scan complete", vim.log.levels.INFO)
end, { desc = "Rescan and index all projects" })
