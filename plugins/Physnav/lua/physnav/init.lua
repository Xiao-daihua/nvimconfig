local M = {}

M.config = {
	root = vim.fn.expand("~/Phys"),
	data_file = vim.fn.stdpath("data") .. "/physnav_projects.json",
	open_cmd = "edit",
	width = 0.92,
	height = 0.88,
	preview_width = 32,
	sidebar_width = 22,
	-- List of subdirectories under root to scan for projects.
	categories = { "EPFL_lecture", "Notes" },
	-- "name" | "recent"
	sort_by = "recent",

	-- Templates offered when creating a new note (press `n`).
	-- Each entry:
	--   label : shown in the picker
	--   url   : git repo to shallow-clone (https or ssh)
	--   type  : "typst" or "latex"  → drives main filename + project type
	--   main  : optional, override the default main file ("main.typ"/"main.tex")
	templates = {
		{ label = "Typst notes", url = "https://github.com/Xiao-daihua/typst_template", type = "typst" },
		{ label = "LaTeX reading", url = "https://github.com/Xiao-daihua/Reading_Latextemplate", type = "latex" },
		{ label = "Pieces (mixed)", url = "https://github.com/Xiao-daihua/pieces_template", type = "typst" },
	},

	-- Deprecated: kept for backward compatibility. If `templates` is empty and
	-- this is set, it is converted to a single-entry `templates` list at setup.
	typst_template = nil,

	-- Trash command: "trash" (trash-cli), "gio trash", or nil (permanent rm!)
	trash_cmd = nil,
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Back-compat: old configs only set `typst_template`. Promote it.
	if
		(not M.config.templates or vim.tbl_isempty(M.config.templates))
		and type(M.config.typst_template) == "string"
	then
		M.config.templates = {
			{ label = "Typst", url = M.config.typst_template, type = "typst" },
		}
	end

	-- Validate: each template must have label + url; default type to typst.
	for _, t in ipairs(M.config.templates or {}) do
		if type(t.label) ~= "string" or type(t.url) ~= "string" then
			vim.notify("PhysNav: malformed template entry (need label + url)", vim.log.levels.WARN)
		end
		t.type = t.type or "typst"
	end
end

function M.open()
	require("physnav.ui").open(M.config)
end

return M
