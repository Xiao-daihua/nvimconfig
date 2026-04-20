-- biblio.nvim :: scanner
-- Scans _database/ and _papers/ and parses their YAML frontmatter.
-- We only parse the subset of YAML that your posts use:
--   - scalar fields: key: value    or    key: "value"
--   - list fields written as:
--       tags: [a, b]
--     or as block sequence:
--       authors:
--         - Foo, B.
--         - Bar, Q.

local util  = require("biblio.util")
local cfg   = require("biblio.config")

local M = {}

--- Extract the frontmatter block from markdown content.
---@param content string
---@return string|nil frontmatter, string body
local function split_frontmatter(content)
  if not content or content == "" then return nil, "" end
  -- Must start with "---\n"
  if not content:match("^%-%-%-%s*\n") then return nil, content end
  local s, e = content:find("\n%-%-%-%s*\n", 4)
  if not s then
    -- No closing, try bare "---" at start of a line at end of file
    s, e = content:find("\n%-%-%-%s*$", 4)
  end
  if not s then return nil, content end
  local fm = content:sub(5, s - 1)   -- skip leading "---\n"
  local body = content:sub((e or s) + 1)
  return fm, body
end

--- Strip surrounding quotes from a YAML scalar.
local function unquote(v)
  if not v then return "" end
  v = util.trim(v)
  if v:sub(1, 1) == '"' and v:sub(-1) == '"' then
    return v:sub(2, -2):gsub('\\"', '"')
  end
  if v:sub(1, 1) == "'" and v:sub(-1) == "'" then
    return v:sub(2, -2)
  end
  return v
end

--- Parse a flow list "[a, b, c]".
local function parse_flow_list(s)
  s = util.trim(s)
  if s:sub(1, 1) ~= "[" or s:sub(-1) ~= "]" then return nil end
  local inner = s:sub(2, -2)
  if util.trim(inner) == "" then return {} end
  local out = {}
  for item in (inner .. ","):gmatch("([^,]*),") do
    table.insert(out, unquote(util.trim(item)))
  end
  return out
end

--- Parse simple frontmatter YAML into a table.
---@param fm string
---@return table
local function parse_frontmatter(fm)
  local out = {}
  local lines = {}
  for line in (fm .. "\n"):gmatch("([^\n]*)\n") do table.insert(lines, line) end

  local i = 1
  while i <= #lines do
    local line = lines[i]
    if line:match("^%s*$") or line:match("^%s*#") then
      i = i + 1
    else
      local key, value = line:match("^(%S[%w_%-]*):%s*(.*)$")
      if not key then
        i = i + 1
      else
        value = util.trim(value or "")
        if value == "" then
          -- The value is on following lines. Three possibilities:
          --   (a) block sequence:    - item
          --   (b) block scalar:      indented continuation lines (free text)
          --   (c) nothing:           the key has no value
          --
          -- Block sequence detection: first non-empty following line starts
          -- with the pattern "^%s+%-%s+".
          local j = i + 1
          local list = {}
          while j <= #lines do
            local l = lines[j]
            local item = l:match("^%s+%-%s+(.*)$")
            if item then
              table.insert(list, unquote(util.trim(item)))
              j = j + 1
            else
              break
            end
          end

          if #list > 0 then
            out[key] = list
            i = j
          else
            -- Try block scalar: collect consecutive indented (non-empty) lines.
            -- YAML semantics: the indent level of the first continuation line
            -- defines the block; lines with less indent end it.
            local scalar_parts = {}
            local k = i + 1
            local base_indent = nil
            while k <= #lines do
              local l = lines[k]
              if l:match("^%s*$") then
                -- blank line — preserve as paragraph break, keep going
                if #scalar_parts > 0 then table.insert(scalar_parts, "") end
                k = k + 1
              else
                local indent = l:match("^(%s+)")
                if not indent then break end
                if not base_indent then base_indent = #indent end
                if #indent < base_indent then break end
                table.insert(scalar_parts, util.trim(l))
                k = k + 1
              end
            end

            if #scalar_parts > 0 then
              -- Join with spaces (folded-style). Good enough for our use.
              out[key] = util.trim(table.concat(scalar_parts, " "))
              i = k
            else
              out[key] = ""
              i = i + 1
            end
          end
        else
          local flow = parse_flow_list(value)
          if flow then
            out[key] = flow
          else
            out[key] = unquote(value)
          end
          i = i + 1
        end
      end
    end
  end
  return out
end

---@class BiblioTopic
---@field path string          Absolute file path
---@field slug string          Filename without ".md"
---@field title string
---@field tags string[]
---@field body string          Markdown body (for fuzzy content search)

---@class BiblioPaper
---@field path string
---@field slug string          Filename without ".md" (this is what shows up in URLs)
---@field title string
---@field authors string[]
---@field year string|number|nil
---@field journal string|nil
---@field arxiv string|nil
---@field doi string|nil
---@field abstract string|nil
---@field url string           "/papers/<slug>/"

---@return BiblioTopic[]
function M.scan_topics()
  local out = {}
  local dir = cfg.database_path()
  for _, path in ipairs(util.list_md(dir)) do
    local content = util.read_file(path) or ""
    local fm_raw, body = split_frontmatter(content)
    local fm = fm_raw and parse_frontmatter(fm_raw) or {}
    local tags = fm.tags
    if type(tags) ~= "table" then tags = {} end
    table.insert(out, {
      path  = path,
      slug  = util.slug_of(path),
      title = fm.title or util.slug_of(path),
      tags  = tags,
      body  = body or "",
    })
  end
  return out
end

---@return BiblioPaper[]
function M.scan_papers()
  local out = {}
  local dir = cfg.papers_path()
  for _, path in ipairs(util.list_md(dir)) do
    local content = util.read_file(path) or ""
    local fm_raw = split_frontmatter(content)
    local fm = fm_raw and parse_frontmatter(fm_raw) or {}
    local authors = fm.authors
    if type(authors) ~= "table" then authors = {} end
    local slug = util.slug_of(path)
    table.insert(out, {
      path     = path,
      slug     = slug,
      title    = fm.title or slug,
      authors  = authors,
      year     = fm.year,
      journal  = fm.journal,
      arxiv    = fm.arxiv,
      doi      = fm.doi,
      abstract = fm.abstract,
      url      = cfg.options.paper_url_prefix .. slug .. "/",
    })
  end
  return out
end

--- Unique, sorted list of all tags present in the database.
---@return string[]
function M.all_tags()
  local seen, out = {}, {}
  for _, t in ipairs(M.scan_topics()) do
    for _, tag in ipairs(t.tags) do
      local trimmed = util.trim(tag)
      if trimmed ~= "" and not seen[trimmed] then
        seen[trimmed] = true
        table.insert(out, trimmed)
      end
    end
  end
  table.sort(out)
  return out
end

--- Scan everything at once (cheap, but avoids double I/O for the dashboard).
---@return { topics: BiblioTopic[], papers: BiblioPaper[], tags: string[] }
function M.scan_all()
  local topics = M.scan_topics()
  local papers = M.scan_papers()
  local seen, tags = {}, {}
  for _, t in ipairs(topics) do
    for _, tag in ipairs(t.tags) do
      local trimmed = util.trim(tag)
      if trimmed ~= "" and not seen[trimmed] then
        seen[trimmed] = true
        table.insert(tags, trimmed)
      end
    end
  end
  table.sort(tags)
  return { topics = topics, papers = papers, tags = tags }
end

-- Expose for tests
M._split_frontmatter = split_frontmatter
M._parse_frontmatter = parse_frontmatter

return M
