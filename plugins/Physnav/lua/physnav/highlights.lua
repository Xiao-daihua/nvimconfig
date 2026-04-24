-- physnav/highlights.lua  v3
-- Redesign: panel-style UI (biblio-inspired).
-- Each dashboard pane is its own floating window with a rounded border.
-- Highlights are kept simple: per-pane title tints, a uniform selection colour,
-- a couple of accent colours for badges, and a muted tone for secondary text.

local M = {}

function M.setup()
  local function hi(name, opts) vim.api.nvim_set_hl(0, name, opts) end
  local dark = vim.o.background == "dark"

  if dark then
    -- Panel chrome
    hi("PhysNavBorder",        { fg = "#3b4261" })
    hi("PhysNavBorderActive",  { fg = "#7aa2f7", bold = true })
    hi("PhysNavTitle",         { fg = "#7aa2f7", bold = true })
    hi("PhysNavTitleTags",     { fg = "#e0af68", bold = true })
    hi("PhysNavTitleList",     { fg = "#7aa2f7", bold = true })
    hi("PhysNavTitlePreview",  { fg = "#bb9af7", bold = true })
    hi("PhysNavTitleSearch",   { fg = "#9ece6a", bold = true })
    hi("PhysNavTitleHints",    { fg = "#565f89", bold = true })

    -- Text
    hi("PhysNavNormal",        { fg = "#a9b1d6" })
    hi("PhysNavMuted",         { fg = "#565f89" })
    hi("PhysNavDim",           { fg = "#414868" })
    hi("PhysNavAccent",        { fg = "#7aa2f7", bold = true })
    hi("PhysNavAccentWarm",    { fg = "#e0af68", bold = true })
    hi("PhysNavAccentPink",    { fg = "#f7768e", bold = true })
    hi("PhysNavAccentPurple",  { fg = "#bb9af7", bold = true })
    hi("PhysNavAccentGreen",   { fg = "#9ece6a", bold = true })

    -- Selection (lines highlighted via CursorLine -> PhysNavCursorLine)
    hi("PhysNavCursorLine",    { bg = "#2a2e42" })

    -- Project type badges
    hi("PhysNavLatex",         { fg = "#7aa2f7", bold = true })
    hi("PhysNavTypst",         { fg = "#9ece6a", bold = true })

    -- PDF / lec / git
    hi("PhysNavPDF",           { fg = "#9ece6a" })
    hi("PhysNavNoPDF",         { fg = "#414868" })
    hi("PhysNavLecCount",      { fg = "#e0af68" })
    hi("PhysNavGitDirty",      { fg = "#e0af68" })
    hi("PhysNavGitClean",      { fg = "#414868" })

    -- Category badges
    hi("PhysNavCatEPFL",       { fg = "#f7768e", bold = true })
    hi("PhysNavCatNotes",      { fg = "#bb9af7", bold = true })

    -- Tag marker / state
    hi("PhysNavTagMarker",     { fg = "#7aa2f7", bold = true })
    hi("PhysNavTagActive",     { fg = "#e0af68", bold = true })
    hi("PhysNavTagInactive",   { fg = "#a9b1d6" })
    hi("PhysNavTagCount",      { fg = "#565f89" })

    -- Tag colour cycle (for per-tag tinting)
    hi("PhysNavTagC1",         { fg = "#7aa2f7" })
    hi("PhysNavTagC2",         { fg = "#9ece6a" })
    hi("PhysNavTagC3",         { fg = "#e0af68" })
    hi("PhysNavTagC4",         { fg = "#bb9af7" })
    hi("PhysNavTagC5",         { fg = "#f7768e" })
    hi("PhysNavTagC6",         { fg = "#7dcfff" })

    -- Search bar
    hi("PhysNavSearchPrompt",  { fg = "#9ece6a", bold = true })
    hi("PhysNavSearchText",    { fg = "#e0af68", bold = true })
    hi("PhysNavSearchHint",    { fg = "#414868", italic = true })

    -- Hints bar
    hi("PhysNavHintKey",       { fg = "#bb9af7", bold = true })
    hi("PhysNavHintDesc",      { fg = "#565f89" })
    hi("PhysNavHintSep",       { fg = "#3b4261" })

    -- Preview fields
    hi("PhysNavPreviewKey",    { fg = "#565f89" })
    hi("PhysNavPreviewVal",    { fg = "#a9b1d6" })
    hi("PhysNavPreviewHead",   { fg = "#bb9af7", bold = true })

    -- Mode badge (tags vs normal)
    hi("PhysNavModeNormal",    { fg = "#1a1b26", bg = "#7aa2f7", bold = true })
    hi("PhysNavModeTags",      { fg = "#1a1b26", bg = "#e0af68", bold = true })
  else
    -- Light theme
    hi("PhysNavBorder",        { fg = "#bcc0cc" })
    hi("PhysNavBorderActive",  { fg = "#1e66f5", bold = true })
    hi("PhysNavTitle",         { fg = "#1e66f5", bold = true })
    hi("PhysNavTitleTags",     { fg = "#df8e1d", bold = true })
    hi("PhysNavTitleList",     { fg = "#1e66f5", bold = true })
    hi("PhysNavTitlePreview",  { fg = "#8839ef", bold = true })
    hi("PhysNavTitleSearch",   { fg = "#40a02b", bold = true })
    hi("PhysNavTitleHints",    { fg = "#9ca0b0", bold = true })

    hi("PhysNavNormal",        { fg = "#4c4f69" })
    hi("PhysNavMuted",         { fg = "#9ca0b0" })
    hi("PhysNavDim",           { fg = "#bcc0cc" })
    hi("PhysNavAccent",        { fg = "#1e66f5", bold = true })
    hi("PhysNavAccentWarm",    { fg = "#df8e1d", bold = true })
    hi("PhysNavAccentPink",    { fg = "#d20f39", bold = true })
    hi("PhysNavAccentPurple",  { fg = "#8839ef", bold = true })
    hi("PhysNavAccentGreen",   { fg = "#40a02b", bold = true })

    hi("PhysNavCursorLine",    { bg = "#dce0e8" })

    hi("PhysNavLatex",         { fg = "#1e66f5", bold = true })
    hi("PhysNavTypst",         { fg = "#40a02b", bold = true })

    hi("PhysNavPDF",           { fg = "#40a02b" })
    hi("PhysNavNoPDF",         { fg = "#bcc0cc" })
    hi("PhysNavLecCount",      { fg = "#df8e1d" })
    hi("PhysNavGitDirty",      { fg = "#df8e1d" })
    hi("PhysNavGitClean",      { fg = "#bcc0cc" })

    hi("PhysNavCatEPFL",       { fg = "#d20f39", bold = true })
    hi("PhysNavCatNotes",      { fg = "#8839ef", bold = true })

    hi("PhysNavTagMarker",     { fg = "#1e66f5", bold = true })
    hi("PhysNavTagActive",     { fg = "#df8e1d", bold = true })
    hi("PhysNavTagInactive",   { fg = "#4c4f69" })
    hi("PhysNavTagCount",      { fg = "#9ca0b0" })

    hi("PhysNavTagC1",         { fg = "#1e66f5" })
    hi("PhysNavTagC2",         { fg = "#40a02b" })
    hi("PhysNavTagC3",         { fg = "#df8e1d" })
    hi("PhysNavTagC4",         { fg = "#8839ef" })
    hi("PhysNavTagC5",         { fg = "#d20f39" })
    hi("PhysNavTagC6",         { fg = "#04a5e5" })

    hi("PhysNavSearchPrompt",  { fg = "#40a02b", bold = true })
    hi("PhysNavSearchText",    { fg = "#df8e1d", bold = true })
    hi("PhysNavSearchHint",    { fg = "#bcc0cc", italic = true })

    hi("PhysNavHintKey",       { fg = "#8839ef", bold = true })
    hi("PhysNavHintDesc",      { fg = "#9ca0b0" })
    hi("PhysNavHintSep",       { fg = "#bcc0cc" })

    hi("PhysNavPreviewKey",    { fg = "#9ca0b0" })
    hi("PhysNavPreviewVal",    { fg = "#4c4f69" })
    hi("PhysNavPreviewHead",   { fg = "#8839ef", bold = true })

    hi("PhysNavModeNormal",    { fg = "#eff1f5", bg = "#1e66f5", bold = true })
    hi("PhysNavModeTags",      { fg = "#eff1f5", bg = "#df8e1d", bold = true })
  end
end

return M
