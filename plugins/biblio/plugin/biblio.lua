-- biblio.nvim :: plugin registration
-- Runs once at startup to expose user commands.

if vim.g.loaded_biblio_nvim then return end
vim.g.loaded_biblio_nvim = true

local subcommands = {
  open         = function() require("biblio").open_dashboard() end,
  close        = function() require("biblio").close_dashboard() end,
  paper        = function() require("biblio").new_paper() end,
  topic        = function() require("biblio").new_topic() end,
  ref          = function() require("biblio").insert_paper_ref() end,
  refresh      = function() require("biblio").refresh() end,
  -- jekyll preview
  serve        = function() require("biblio").serve() end,
  serve_stop   = function() require("biblio").serve_stop() end,
  serve_status = function() require("biblio").serve_status() end,
  preview      = function() require("biblio").preview() end,
  -- git
  commit       = function() require("biblio").commit() end,
  push         = function() require("biblio").push() end,
  sync         = function() require("biblio").commit({ push = true }) end,
}

vim.api.nvim_create_user_command("Biblio", function(opts)
  local sub = opts.fargs[1]
  if not sub or sub == "" then
    subcommands.open()
    return
  end
  local fn = subcommands[sub]
  if not fn then
    vim.notify("[biblio] unknown subcommand: " .. sub, vim.log.levels.ERROR)
    return
  end
  fn()
end, {
  nargs = "?",
  complete = function(arg_lead)
    local keys = {}
    for k in pairs(subcommands) do
      if k:sub(1, #arg_lead) == arg_lead then table.insert(keys, k) end
    end
    table.sort(keys)
    return keys
  end,
  desc = "biblio.nvim dashboard and subcommands",
})
