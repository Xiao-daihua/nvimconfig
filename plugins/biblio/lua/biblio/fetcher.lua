-- biblio.nvim :: fetcher
-- Fetches metadata from arXiv and Crossref using curl via vim.system.
-- All functions are synchronous and return (result, err) — err is nil on
-- success and a string on failure. Failures are never fatal; callers are
-- expected to degrade gracefully.

local util = require("biblio.util")
local cfg  = require("biblio.config")

local M = {}

--- Run curl with a timeout. Returns stdout or nil + error.
---@param url string
---@param accept string|nil
---@return string|nil body, string|nil err
local function http_get(url, accept)
  if vim.fn.executable("curl") == 0 then
    return nil, "curl not found on PATH"
  end
  local args = {
    "curl", "-sSL",
    "--max-time", tostring(math.floor(cfg.options.request_timeout_ms / 1000)),
    "-A", "biblio.nvim/0.1 (https://github.com/)",
  }
  if accept then
    table.insert(args, "-H")
    table.insert(args, "Accept: " .. accept)
  end
  table.insert(args, url)

  -- vim.system exists in Neovim 0.10+. Fall back to vim.fn.system for older.
  if vim.system then
    local ok, res = pcall(function()
      return vim.system(args, { text = true }):wait(cfg.options.request_timeout_ms + 500)
    end)
    if not ok or not res then return nil, "request failed" end
    if res.code ~= 0 then
      return nil, "curl exit " .. tostring(res.code) .. ": " .. (res.stderr or "")
    end
    return res.stdout or "", nil
  else
    local cmd = table.concat(vim.tbl_map(vim.fn.shellescape, args), " ")
    local out = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      return nil, "curl exit " .. tostring(vim.v.shell_error)
    end
    return out, nil
  end
end

--- Decode XML entities (minimal; arXiv summaries mostly need these four).
local function xml_decode(s)
  if not s then return "" end
  s = s:gsub("&lt;",  "<")
  s = s:gsub("&gt;",  ">")
  s = s:gsub("&quot;", '"')
  s = s:gsub("&apos;", "'")
  s = s:gsub("&amp;",  "&")
  return s
end

--- Fetch metadata from arXiv by id.
---@param id string
---@return table|nil info, string|nil err
function M.fetch_arxiv(id)
  if not id or id == "" then return nil, "no arxiv id" end
  local url = cfg.options.arxiv_api .. "?id_list=" .. util.url_encode(id)
  local body, err = http_get(url, "application/atom+xml")
  if not body then return nil, err end

  -- Grab the first <entry> block; there should only be one.
  local entry = body:match("<entry>(.-)</entry>")
  if not entry then return nil, "no entry in arXiv response" end

  local function pick(tag)
    local v = entry:match("<" .. tag .. "[^>]*>(.-)</" .. tag .. ">")
    if not v then return "" end
    v = v:gsub("%s+", " ")
    return util.trim(xml_decode(v))
  end

  local title   = pick("title")
  local summary = pick("summary")
  local published = pick("published")
  local year = published:sub(1, 4)

  local primary_cat = entry:match('<arxiv:primary_category[^>]-term="([^"]+)"') or ""
  -- arXiv sometimes uses a plain "primary_category" without the prefix.
  if primary_cat == "" then
    primary_cat = entry:match('<primary_category[^>]-term="([^"]+)"') or ""
  end

  return {
    title        = title,
    abstract     = summary,
    year         = year ~= "" and year or nil,
    primary_cat  = primary_cat ~= "" and primary_cat or nil,
    source       = "arXiv",
  }, nil
end

--- Very small JSON value extractor. We only need a handful of top-level-ish
--- fields from Crossref, so a real parser is overkill.
---@param json string
---@param key string
---@return string|nil
local function json_string(json, key)
  local pat = '"' .. key .. '"%s*:%s*"([^"\\]*(?:\\.[^"\\]*)*)"'
  -- Lua pattern doesn't support the non-capturing group, so do it in two steps.
  local _, _, simple = json:find('"' .. key .. '"%s*:%s*"([^"]*)"')
  if simple then return simple end
  return nil
end

--- Fetch Crossref metadata for a DOI.
---@param doi string
---@return table|nil info, string|nil err
function M.fetch_crossref(doi)
  if not doi or doi == "" then return nil, "no doi" end
  local url = cfg.options.crossref_api .. "/" .. util.url_encode(doi)
  local body, err = http_get(url, "application/json")
  if not body then return nil, err end

  local msg = body:match('"message"%s*:%s*({.*)') or body
  local info = {}

  -- title is a JSON array; take the first element.
  local title_arr = msg:match('"title"%s*:%s*%[(.-)%]')
  if title_arr then
    local first = title_arr:match('"([^"]+)"')
    if first then info.title = xml_decode(first) end
  end

  -- container-title (journal) is also an array
  local ct = msg:match('"container%-title"%s*:%s*%[(.-)%]')
  if ct then
    local first = ct:match('"([^"]+)"')
    if first then info.journal = first end
  end

  info.volume = json_string(msg, "volume")
  info.page   = json_string(msg, "page")
  info.abstract = json_string(msg, "abstract")
  if info.abstract then
    -- Crossref abstracts come wrapped in JATS XML.
    info.abstract = info.abstract:gsub("<[^>]+>", " "):gsub("%s+", " ")
    info.abstract = util.trim(info.abstract)
  end

  -- year from issued/date-parts
  local year = msg:match('"issued"%s*:%s*{%s*"date%-parts"%s*:%s*%[%s*%[%s*(%d+)')
  if year then info.year = year end

  info.source = "Crossref"
  return info, nil
end

return M
