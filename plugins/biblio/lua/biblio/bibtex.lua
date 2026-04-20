-- biblio.nvim :: bibtex
-- Minimal BibTeX parser, ported from Xiao's bibtex-converter.html.
-- Handles @type{key, field = {value}, field = "value", ...}

local util = require("biblio.util")

local M = {}

--- Parse a single BibTeX entry.
---@param raw string
---@return table   fields keyed lowercase; includes `type` and `key`
function M.parse(raw)
  local r = {}
  if not raw or raw == "" then return r end

  -- @type{key,
  local t, k = raw:match("@(%w+)%s*{([^,]+),")
  if t then r.type = t:lower() end
  if k then r.key = util.trim(k) end

  -- Walk the body, extracting field = value pairs.
  -- Values can be: "quoted", 'quoted', {braced}, or bareword.
  -- We implement a small state machine instead of a regex so we handle
  -- nested braces correctly (e.g. {Hello {World}}).
  local i, n = 1, #raw
  -- Skip past the header "@type{key,"
  local _, header_end = raw:find("@%w+%s*{[^,]+,")
  if header_end then i = header_end + 1 end

  local function skip_ws()
    while i <= n do
      local c = raw:sub(i, i)
      if c == " " or c == "\t" or c == "\n" or c == "\r" then
        i = i + 1
      else
        return
      end
    end
  end

  while i <= n do
    skip_ws()
    if i > n then break end
    local c = raw:sub(i, i)
    if c == "}" then break end
    if c == "," then i = i + 1; goto continue end

    -- Field name
    local name_start = i
    while i <= n do
      local ch = raw:sub(i, i)
      if ch:match("[%w_%-]") then
        i = i + 1
      else
        break
      end
    end
    if i == name_start then
      -- No field name found; bail out to avoid infinite loop
      break
    end
    local field = raw:sub(name_start, i - 1):lower()

    skip_ws()
    if raw:sub(i, i) ~= "=" then
      -- Malformed, skip to next comma or closing brace
      while i <= n and raw:sub(i, i) ~= "," and raw:sub(i, i) ~= "}" do i = i + 1 end
      goto continue
    end
    i = i + 1
    skip_ws()

    -- Read value
    local value = ""
    local vc = raw:sub(i, i)
    if vc == "{" then
      local depth = 1
      i = i + 1
      local start = i
      while i <= n and depth > 0 do
        local ch = raw:sub(i, i)
        if ch == "{" then depth = depth + 1
        elseif ch == "}" then depth = depth - 1
        end
        if depth > 0 then i = i + 1 end
      end
      value = raw:sub(start, i - 1)
      i = i + 1   -- consume closing }
    elseif vc == '"' then
      i = i + 1
      local start = i
      while i <= n do
        local ch = raw:sub(i, i)
        if ch == '\\' then
          i = i + 2
        elseif ch == '"' then
          break
        else
          i = i + 1
        end
      end
      value = raw:sub(start, i - 1)
      i = i + 1
    else
      -- bareword until , or }
      local start = i
      while i <= n do
        local ch = raw:sub(i, i)
        if ch == "," or ch == "}" then break end
        i = i + 1
      end
      value = raw:sub(start, i - 1)
    end

    -- Strip nested braces inside the value (like the JS version)
    value = value:gsub("[{}]", "")
    r[field] = util.trim(value)

    ::continue::
  end

  return r
end

--- Format authors from a BibTeX "author" field ("Foo Bar and Baz Qux")
--- into the "Last, F." style used in your _papers/*.md files.
---@param s string|nil
---@return string[]
function M.format_authors(s)
  if not s or s == "" then return {} end
  local out = {}
  -- Split on whitespace+"and"+whitespace (case-insensitive).
  -- Lua pattern lacks case-insensitivity, so we normalize first.
  local normalized = s:gsub("%s+[Aa][Nn][Dd]%s+", "\0")
  for part in (normalized .. "\0"):gmatch("([^%z]+)\0") do
    local a = util.trim(part)
    if a ~= "" then
      if a:find(",") then
        local last, first = a:match("([^,]+),%s*(.*)")
        last = util.trim(last or a)
        first = util.trim(first or "")
        if first ~= "" then
          table.insert(out, last .. ", " .. first:sub(1, 1) .. ".")
        else
          table.insert(out, last)
        end
      else
        -- "Firstname Lastname" or "F. M. Lastname"
        local parts = {}
        for p in a:gmatch("%S+") do table.insert(parts, p) end
        if #parts >= 2 then
          local last = parts[#parts]
          local first_initial = parts[1]:sub(1, 1)
          table.insert(out, last .. ", " .. first_initial .. ".")
        else
          table.insert(out, a)
        end
      end
    end
  end
  return out
end

--- Extract the lowercase last name of the first author, stripped to a-z.
---@param s string|nil
---@return string
function M.first_author_lastname(s)
  if not s or s == "" then return "unknown" end
  local normalized = s:gsub("%s+[Aa][Nn][Dd]%s+", "\0")
  local first = normalized:match("([^%z]+)") or s
  first = util.trim(first)
  local last
  if first:find(",") then
    last = first:match("([^,]+),")
  else
    local parts = {}
    for p in first:gmatch("%S+") do table.insert(parts, p) end
    last = parts[#parts]
  end
  last = last or first
  last = last:lower():gsub("[^a-z]", "")
  if last == "" then return "unknown" end
  return last
end

--- Extract arXiv id from a parsed entry.
---@param bib table
---@return string|nil
function M.extract_arxiv(bib)
  local e = bib.eprint
  if e and (e:match("^%d%d%d%d%.%d%d%d%d%d?$") or e:match("^[%a%-]+/%d+$")) then
    return util.trim(e)
  end
  if bib.archiveprefix and bib.archiveprefix:lower() == "arxiv" and bib.eprint then
    return util.trim(bib.eprint)
  end
  if bib.arxivid then return util.trim(bib.arxivid) end
  if bib.arxiv then return util.trim(bib.arxiv) end
  return nil
end

--- Strip {...} wrapping from a title.
---@param t string|nil
---@return string
function M.clean_title(t)
  if not t then return "" end
  t = t:gsub("^{", ""):gsub("}$", "")
  t = t:gsub("[{}]", "")
  return util.trim(t)
end

return M
