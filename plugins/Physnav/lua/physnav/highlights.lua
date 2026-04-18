-- physnav/highlights.lua  v2
-- Richer visual palette: header backgrounds, accent fills, bold states.

local M = {}

function M.setup()
  local function hi(name, opts)
    vim.api.nvim_set_hl(0, name, opts)
  end
  local dark = vim.o.background == "dark"

  if dark then
    -- Structure
    hi("PhysNavBorder",        { fg = "#3b4261" })
    hi("PhysNavSep",           { fg = "#1e2030" })
    hi("PhysNavSepBright",     { fg = "#3b4261" })
    -- Header row  (full-width filled bars)
    hi("PhysNavHeaderBar",     { fg = "#c0caf5", bg = "#1e2030", bold = true })
    hi("PhysNavHeaderBarDim",  { fg = "#545c7e", bg = "#1e2030" })
    hi("PhysNavHeaderTitle",   { fg = "#7aa2f7", bg = "#1e2030", bold = true })
    hi("PhysNavHeaderCount",   { fg = "#3b4261", bg = "#1e2030" })
    -- Hint bar
    hi("PhysNavHint",          { fg = "#414868" })
    hi("PhysNavHintActive",    { fg = "#7aa2f7" })
    hi("PhysNavSearch",        { fg = "#e0af68", bold = true })
    -- Selection in main list
    hi("PhysNavSelected",      { fg = "#c0caf5", bg = "#1d2030", bold = true })
    hi("PhysNavSelAccent",     { fg = "#7aa2f7", bg = "#1d2030", bold = true })
    hi("PhysNavNormal",        { fg = "#a9b1d6" })
    -- Project types
    hi("PhysNavLatex",         { fg = "#7aa2f7" })
    hi("PhysNavLatexSel",      { fg = "#89b4fa", bg = "#1d2030", bold = true })
    hi("PhysNavTypst",         { fg = "#9ece6a" })
    hi("PhysNavTypstSel",      { fg = "#a9dc7e", bg = "#1d2030", bold = true })
    -- PDF / lec
    hi("PhysNavPDF",           { fg = "#9ece6a" })
    hi("PhysNavNoPDF",         { fg = "#2a2f45" })
    hi("PhysNavLecCount",      { fg = "#414868" })
    -- Git
    hi("PhysNavGitDirty",      { fg = "#e0af68" })
    hi("PhysNavGitClean",      { fg = "#2a2f45" })
    hi("PhysNavGitTitle",      { fg = "#9ece6a", bold = true })
    -- Category badges
    hi("PhysNavCatEPFL",       { fg = "#f7768e", bold = true })
    hi("PhysNavCatNotes",      { fg = "#bb9af7" })
    -- Sidebar tags
    hi("PhysNavSidebarBar",    { fg = "#7aa2f7", bg = "#1e2030", bold = true })
    hi("PhysNavTagActive",     { fg = "#e0af68", bold = true })
    hi("PhysNavTagInactive",   { fg = "#3b4261" })
    hi("PhysNavTagCursor",     { fg = "#1a1b26", bg = "#7aa2f7", bold = true })
    hi("PhysNavTagAllActive",  { fg = "#7aa2f7", bold = true })
    -- Tag colours (cycling)
    hi("PhysNavTag",           { fg = "#e0af68" })
    hi("PhysNavKey",           { fg = "#bb9af7", bold = true })
    hi("PhysNavCourse",        { fg = "#9ece6a" })
    hi("PhysNavNotes",         { fg = "#bb9af7" })
    -- Preview panel
    hi("PhysNavPreviewBar",    { fg = "#c0caf5", bg = "#1a1e2e", bold = true })
    hi("PhysNavPreviewBarTyp", { fg = "#9ece6a", bg = "#1a1e2e", bold = true })
    hi("PhysNavPreviewBarTex", { fg = "#7aa2f7", bg = "#1a1e2e", bold = true })
    hi("PhysNavPreviewKey",    { fg = "#3b4261" })
    hi("PhysNavPreviewVal",    { fg = "#9aa5ce" })
    hi("PhysNavMuted",         { fg = "#414868" })
    -- Status bar
    hi("PhysNavStatusNormal",  { fg = "#1a1b26", bg = "#7aa2f7", bold = true })
    hi("PhysNavStatusTags",    { fg = "#1a1b26", bg = "#e0af68", bold = true })
    hi("PhysNavStatusSep",     { fg = "#7aa2f7", bg = "#1e2030" })
    hi("PhysNavStatusFill",    { fg = "#3b4261", bg = "#1e2030" })
    hi("PhysNavStatusInfo",    { fg = "#565f89", bg = "#1e2030" })
    hi("PhysNavStatusQuery",   { fg = "#e0af68", bg = "#1e2030" })
  else
    hi("PhysNavBorder",        { fg = "#ccd0da" })
    hi("PhysNavSep",           { fg = "#e6e9ef" })
    hi("PhysNavSepBright",     { fg = "#ccd0da" })
    hi("PhysNavHeaderBar",     { fg = "#4c4f69", bg = "#e6e9ef", bold = true })
    hi("PhysNavHeaderBarDim",  { fg = "#9ca0b0", bg = "#e6e9ef" })
    hi("PhysNavHeaderTitle",   { fg = "#1e66f5", bg = "#e6e9ef", bold = true })
    hi("PhysNavHeaderCount",   { fg = "#bcc0cc", bg = "#e6e9ef" })
    hi("PhysNavHint",          { fg = "#bcc0cc" })
    hi("PhysNavHintActive",    { fg = "#1e66f5" })
    hi("PhysNavSearch",        { fg = "#df8e1d", bold = true })
    hi("PhysNavSelected",      { fg = "#4c4f69", bg = "#dce0e8", bold = true })
    hi("PhysNavSelAccent",     { fg = "#1e66f5", bg = "#dce0e8", bold = true })
    hi("PhysNavNormal",        { fg = "#4c4f69" })
    hi("PhysNavLatex",         { fg = "#1e66f5" })
    hi("PhysNavLatexSel",      { fg = "#1e66f5", bg = "#dce0e8", bold = true })
    hi("PhysNavTypst",         { fg = "#40a02b" })
    hi("PhysNavTypstSel",      { fg = "#40a02b", bg = "#dce0e8", bold = true })
    hi("PhysNavPDF",           { fg = "#40a02b" })
    hi("PhysNavNoPDF",         { fg = "#dce0e8" })
    hi("PhysNavLecCount",      { fg = "#bcc0cc" })
    hi("PhysNavGitDirty",      { fg = "#df8e1d" })
    hi("PhysNavGitClean",      { fg = "#dce0e8" })
    hi("PhysNavGitTitle",      { fg = "#40a02b", bold = true })
    hi("PhysNavCatEPFL",       { fg = "#d20f39", bold = true })
    hi("PhysNavCatNotes",      { fg = "#8839ef" })
    hi("PhysNavSidebarBar",    { fg = "#1e66f5", bg = "#e6e9ef", bold = true })
    hi("PhysNavTagActive",     { fg = "#df8e1d", bold = true })
    hi("PhysNavTagInactive",   { fg = "#ccd0da" })
    hi("PhysNavTagCursor",     { fg = "#eff1f5", bg = "#1e66f5", bold = true })
    hi("PhysNavTagAllActive",  { fg = "#1e66f5", bold = true })
    hi("PhysNavTag",           { fg = "#df8e1d" })
    hi("PhysNavKey",           { fg = "#8839ef", bold = true })
    hi("PhysNavCourse",        { fg = "#40a02b" })
    hi("PhysNavNotes",         { fg = "#8839ef" })
    hi("PhysNavPreviewBar",    { fg = "#4c4f69", bg = "#eff1f5", bold = true })
    hi("PhysNavPreviewBarTyp", { fg = "#40a02b", bg = "#eff1f5", bold = true })
    hi("PhysNavPreviewBarTex", { fg = "#1e66f5", bg = "#eff1f5", bold = true })
    hi("PhysNavPreviewKey",    { fg = "#bcc0cc" })
    hi("PhysNavPreviewVal",    { fg = "#6c6f85" })
    hi("PhysNavMuted",         { fg = "#bcc0cc" })
    hi("PhysNavStatusNormal",  { fg = "#eff1f5", bg = "#1e66f5", bold = true })
    hi("PhysNavStatusTags",    { fg = "#eff1f5", bg = "#df8e1d", bold = true })
    hi("PhysNavStatusSep",     { fg = "#1e66f5", bg = "#e6e9ef" })
    hi("PhysNavStatusFill",    { fg = "#bcc0cc", bg = "#e6e9ef" })
    hi("PhysNavStatusInfo",    { fg = "#9ca0b0", bg = "#e6e9ef" })
    hi("PhysNavStatusQuery",   { fg = "#df8e1d", bg = "#e6e9ef" })
  end
end

return M
