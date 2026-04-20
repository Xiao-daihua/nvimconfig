-- biblio.nvim :: paper
-- The "new paper" flow:
--   1. Prompt for BibTeX input (multi-line float)
--   2. Parse it
--   3. Try to enrich with arXiv and/or Crossref data
--   4. Build the Jekyll YAML frontmatter
--   5. Write the file to _papers/ using your filename convention

local bibtex  = require("biblio.bibtex")
local fetcher = require("biblio.fetcher")
local util    = require("biblio.util")
local cfg     = require("biblio.config")
local ui      = require("biblio.ui")

local M = {}

--- Build the YAML frontmatter string from a merged record.
---@param rec table   Merged bibtex + fetched info, all strings
---@return string
local function build_yaml(rec)
  local lines = { "---", "layout: paper" }
  table.insert(lines, string.format('title: "%s"', util.yaml_escape(rec.title or "")))

  if rec.authors and #rec.authors > 0 then
    table.insert(lines, "authors:")
    for _, a in ipairs(rec.authors) do
      table.insert(lines, "  - " .. a)
    end
  end

  if rec.year and rec.year ~= "" then
    table.insert(lines, "year: " .. rec.year)
  else
    table.insert(lines, "year: ")
  end

  table.insert(lines, "status: published")

  local maybe = function(key, val)
    if val and val ~= "" then
      table.insert(lines, string.format('%s: "%s"', key, util.yaml_escape(val)))
    end
  end
  maybe("journal",  rec.journal)
  maybe("volume",   rec.volume)
  maybe("pages",    rec.pages)
  maybe("arxiv",    rec.arxiv)
  maybe("arxiv_cat", rec.arxiv_cat)
  maybe("doi",      rec.doi)

  if rec.abstract and rec.abstract ~= "" then
    table.insert(lines, string.format('abstract: "%s"', util.yaml_escape(rec.abstract)))
  end

  table.insert(lines, "---")
  table.insert(lines, "")
  return table.concat(lines, "\n")
end

--- Derive the file base (e.g. "1988-moore") from year + first-author name.
--- Year resolution order: explicit `override_year` (usually the merged record
--- year from arXiv/Crossref/bibtex), bibtex `year` field, year-shaped digits
--- inside the bibtex citation key (e.g. "Collier:2023fwi" → "2023"), else
--- "0000" as a last resort.
---@param bib table
---@param override_year string|number|nil
---@return string
local function derive_base(bib, override_year)
  local last = bibtex.first_author_lastname(bib.author)

  local year = ""
  local function try(candidate)
    if year ~= "" then return end
    if not candidate then return end
    local y = tostring(candidate):match("(%d%d%d%d)")
    if y and tonumber(y) and tonumber(y) >= 1800 and tonumber(y) <= 2100 then
      year = y
    end
  end
  try(override_year)
  try(bib.year)
  try(bib.key)          -- last resort: digits in the citation key

  if year == "" then return "0000-" .. last end
  return year .. "-" .. last
end

--- Merge bibtex + fetched sources into a single record. arXiv and Crossref
--- can disagree; we prefer explicit BibTeX values, then Crossref (typically
--- the most authoritative for journal/volume/pages), then arXiv.
local function merge(bib, arxiv_info, crossref_info)
  local function coalesce(...)
    local n = select("#", ...)
    for i = 1, n do
      local v = select(i, ...)
      if v and v ~= "" then return v end
    end
    return nil
  end

  return {
    title     = bibtex.clean_title(coalesce(bib.title, crossref_info and crossref_info.title, arxiv_info and arxiv_info.title) or ""),
    authors   = bibtex.format_authors(bib.author),
    year      = coalesce(bib.year, crossref_info and crossref_info.year, arxiv_info and arxiv_info.year),
    journal   = coalesce(bib.journal, crossref_info and crossref_info.journal),
    volume    = coalesce(bib.volume, crossref_info and crossref_info.volume),
    pages     = coalesce(bib.pages, crossref_info and crossref_info.page),
    doi       = bib.doi,
    arxiv     = bibtex.extract_arxiv(bib),
    arxiv_cat = arxiv_info and arxiv_info.primary_cat,
    abstract  = coalesce(
      bib.abstract,
      arxiv_info and arxiv_info.abstract,      -- arXiv usually has the longer one
      crossref_info and crossref_info.abstract
    ),
  }
end

--- Return a one-line summary of what was fetched, for the notification.
local function summary(arxiv_ok, crossref_ok)
  local parts = {}
  if arxiv_ok    then table.insert(parts, "arXiv ✓") end
  if crossref_ok then table.insert(parts, "Crossref ✓") end
  if #parts == 0 then return "no online enrichment" end
  return table.concat(parts, ", ")
end

--- Show the generated YAML in a preview float. User decides:
---   y / <CR>  = save file, done
---   e         = save file and open it for editing
---   d / <Esc> = discard, don't save
---@param abs_path string   where it would be written
---@param yaml string       the generated content
---@param summary_line string   info line for the header
---@param on_done fun(path:string, slug:string)|nil
local function preview_and_commit(abs_path, yaml, summary_line, on_done)
  local fname = vim.fn.fnamemodify(abs_path, ":t")

  local header = {
    "  Review the generated paper entry:",
    "",
    "  File:    " .. abs_path,
    "  Source:  " .. summary_line,
    "",
    "  ────────────────────────────────────────────────────────────",
  }
  local footer = {
    "  ────────────────────────────────────────────────────────────",
    "",
    "  y / <CR>  Save and close          e  Save and open for editing",
    "  d / <Esc> Discard                 q  Close without saving",
  }

  local lines = {}
  for _, l in ipairs(header)       do table.insert(lines, l)           end
  for yline in (yaml .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, "  " .. yline)
  end
  for _, l in ipairs(footer)       do table.insert(lines, l)           end

  local buf = ui.scratch_buf({ filetype = "markdown" })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local total_cols  = vim.o.columns
  local total_lines = vim.o.lines - vim.o.cmdheight - 2
  local w = math.min(92, total_cols - 4)
  local h = math.min(#lines + 2, total_lines - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((total_lines - h) / 2),
    col = math.floor((total_cols  - w) / 2),
    width = w, height = h,
    style = "minimal", border = "rounded",
    title = string.format(" Preview: %s ", fname),
    title_pos = "center",
  })
  vim.wo[win].cursorline = false

  local committed = false
  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end

  local function save_file()
    local ok, err = util.write_file(abs_path, yaml)
    if not ok then
      util.notify("Write failed: " .. (err or "unknown"), vim.log.levels.ERROR)
      return false
    end
    committed = true
    util.notify(string.format("Saved %s (%s)", fname, summary_line))
    if on_done then on_done(abs_path, util.slug_of(abs_path)) end
    return true
  end

  local function accept()
    if save_file() then close() end
  end
  local function accept_and_edit()
    if save_file() then
      close()
      util.open_file_for_editing(abs_path, cfg.options.open_cmd)
    end
  end
  local function discard()
    close()
    util.notify("Discarded: nothing was written.")
  end

  local map = function(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  map("y",     accept)
  map("<CR>",  accept)
  map("e",     accept_and_edit)
  map("d",     discard)
  map("<Esc>", discard)
  map("q",     discard)
end

--- Entry point: open the BibTeX input float.
---@param on_done fun(absolute_path:string, slug:string)|nil
function M.prompt_new_paper(on_done)
  local initial = {
    "# Paste BibTeX below.",
    "# <Esc>           drop to normal mode",
    "# <CR> in normal  submit        <C-s>  submit from any mode",
    "# q  in normal    cancel",
    "# Lines starting with '#' are ignored.",
    "",
  }
  ui.multiline_input({
    title        = " New Paper: paste BibTeX ",
    filetype     = "bibtex",
    initial      = initial,
    width_frac   = 0.75,
    height_frac  = 0.5,
    start_insert = true,
  }, function(text)
    -- Strip comment lines starting with '#'
    local cleaned = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      if not line:match("^%s*#") then table.insert(cleaned, line) end
    end
    text = table.concat(cleaned, "\n")
    if not text:match("@%w+%s*{") then
      util.notify("No @entry found in the input; aborting.", vim.log.levels.WARN)
      return
    end

    local bib = bibtex.parse(text)
    if not bib.type then
      util.notify("Could not parse the BibTeX entry.", vim.log.levels.ERROR)
      return
    end

    util.notify("Fetching metadata…")
    local arxiv_id = bibtex.extract_arxiv(bib)
    local arxiv_info, crossref_info
    if arxiv_id then
      arxiv_info = fetcher.fetch_arxiv(arxiv_id)
    end
    if bib.doi and bib.doi ~= "" then
      crossref_info = fetcher.fetch_crossref(bib.doi)
    end

    local rec = merge(bib, arxiv_info, crossref_info)
    local yaml = build_yaml(rec)

    local base = derive_base(bib, rec.year)
    local _, abs_path = util.unique_paper_filename(cfg.papers_path(), base)

    -- Instead of writing immediately, show a preview and let the user decide.
    preview_and_commit(abs_path, yaml, summary(arxiv_info ~= nil, crossref_info ~= nil), on_done)
  end)
end

-- Exposed for testing
M._build_yaml   = build_yaml
M._derive_base  = derive_base
M._merge        = merge

return M
