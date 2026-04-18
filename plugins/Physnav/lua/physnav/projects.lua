-- physnav/projects.lua
-- Scanning, caching, filtering.
-- Key improvements over v1:
--   - categories read from config (not hardcoded)
--   - cache-first load: only re-scan when cache is stale or missing
--   - last_opened timestamp for "recent" sort
--   - single git-status call per root (batched in git.lua)
--   - smarter find_main: prefers files named main/master/<project>

local M  = {}
local uv = vim.loop or vim.uv

-- -----------------------------------------------------------------
--  Filesystem helpers
-- -----------------------------------------------------------------
local function detect_type(dir)
  local has_tex, has_typ = false, false
  local h = uv.fs_scandir(dir)
  if not h then return "unknown" end
  while true do
    local name, ftype = uv.fs_scandir_next(h)
    if not name then break end
    if ftype == "file" then
      if name:match("%.tex$") then has_tex = true end
      if name:match("%.typ$") then has_typ = true end
    end
  end
  if has_typ then return "typst" end
  if has_tex then return "latex" end
  return "unknown"
end

-- Smarter main-file finder: prefer main/master/<project-name> over random
local function find_main(dir, ptype, project_name)
  local ext = ptype == "typst" and "%.typ$" or "%.tex$"
  local candidates = {}
  local h = uv.fs_scandir(dir)
  if h then
    while true do
      local name = uv.fs_scandir_next(h)
      if not name then break end
      if name:match(ext) then
        table.insert(candidates, name)
      end
    end
  end
  if #candidates == 0 then return nil end

  -- Priority: exact "main.*", "master.*", "<project>.*", then first alpha
  local prio = { "^main%.", "^master%.", "^" .. vim.pesc(project_name:lower()) .. "%." }
  for _, pat in ipairs(prio) do
    for _, c in ipairs(candidates) do
      if c:lower():match(pat) then return c end
    end
  end
  table.sort(candidates)
  return candidates[1]
end

local function count_files(dir, ptype)
  local count   = 0
  local has_pdf = false
  local h = uv.fs_scandir(dir)
  if not h then return 0, false end
  while true do
    local name, ftype = uv.fs_scandir_next(h)
    if not name then break end
    if ftype == "file" then
      if ptype == "latex" and name:match("^lec%d+%.tex$") then count = count + 1 end
      if name == "main.pdf" then has_pdf = true end
    end
    if ftype == "directory" and name == "doc" then
      local dh = uv.fs_scandir(dir .. "/doc")
      if dh then
        while true do
          local dn = uv.fs_scandir_next(dh)
          if not dn then break end
          if dn:match("^lec%d+%.typ$") then count = count + 1 end
        end
      end
    end
  end
  return count, has_pdf
end

-- -----------------------------------------------------------------
--  Scan
-- -----------------------------------------------------------------
local function scan_category(root, category)
  local cat_dir = root .. "/" .. category
  local stat = uv.fs_stat(cat_dir)
  if not stat or stat.type ~= "directory" then return {} end

  local projects = {}
  local h = uv.fs_scandir(cat_dir)
  if not h then return projects end

  while true do
    local name, ftype = uv.fs_scandir_next(h)
    if not name then break end
    if ftype == "directory" and not name:match("^%.") and name ~= "README.md" then
      local dir   = cat_dir .. "/" .. name
      local ptype = detect_type(dir)
      if ptype ~= "unknown" then
        local main            = find_main(dir, ptype, name)
        local lec_count, pdf  = count_files(dir, ptype)
        table.insert(projects, {
          name        = name,
          category    = category,
          path        = dir,
          type        = ptype,
          main        = main,
          lec_count   = lec_count,
          has_pdf     = pdf,
          tags        = {},
          last_opened = 0,   -- unix timestamp; 0 = never
        })
      end
    end
  end
  table.sort(projects, function(a, b) return a.name < b.name end)
  return projects
end

function M.scan(root, categories)
  local all = {}
  for _, cat in ipairs(categories or { "EPFL_lecture", "Notes" }) do
    for _, p in ipairs(scan_category(root, cat)) do
      table.insert(all, p)
    end
  end
  return all
end

-- -----------------------------------------------------------------
--  Merge helper: copy user-managed fields from cached list
-- -----------------------------------------------------------------
local function merge_from_cache(projects, cached)
  if not cached then return end
  -- Build lookup by name (names assumed unique per install)
  local by_name = {}
  for _, cp in ipairs(cached) do by_name[cp.name] = cp end
  for _, p in ipairs(projects) do
    local cp = by_name[p.name]
    if cp then
      p.tags        = cp.tags        or {}
      p.last_opened = cp.last_opened or 0
    end
  end
end

-- -----------------------------------------------------------------
--  Persistence
-- -----------------------------------------------------------------
function M.save(data_file, projects)
  local f = io.open(data_file, "w")
  if f then
    f:write(vim.fn.json_encode(projects))
    f:close()
  end
end

local function load_cache(data_file)
  local f = io.open(data_file, "r")
  if not f then return nil end
  local content = f:read("*a"); f:close()
  local ok, data = pcall(vim.fn.json_decode, content)
  return (ok and type(data) == "table") and data or nil
end

-- -----------------------------------------------------------------
--  Load: cache-first.
--  Only re-scans disk when the cache is absent or when `force=true`.
--  Structural fields (type, main, lec_count, has_pdf) are refreshed
--  from cache values but user fields (tags, last_opened) are kept.
-- -----------------------------------------------------------------
function M.load(data_file, root, categories, force)
  local cached = load_cache(data_file)

  local projects
  if cached and not force then
    -- Use cached data as the project list, but verify dirs still exist
    projects = {}
    for _, cp in ipairs(cached) do
      if uv.fs_stat(cp.path) then
        table.insert(projects, cp)
      end
    end
  else
    -- Full disk scan
    projects = M.scan(root, categories)
    merge_from_cache(projects, cached)
    M.save(data_file, projects)
  end

  return projects
end

-- Called by :PhysNavScan command and the 'r' key
function M.scan_and_save()
  local cfg      = require("physnav").config
  local projects = M.scan(cfg.root, cfg.categories)
  local cached   = load_cache(cfg.data_file)
  merge_from_cache(projects, cached)
  M.save(cfg.data_file, projects)
  return projects
end

-- -----------------------------------------------------------------
--  Record that a project was opened right now
-- -----------------------------------------------------------------
function M.touch(data_file, projects, project_name)
  for _, p in ipairs(projects) do
    if p.name == project_name then
      p.last_opened = os.time()
      break
    end
  end
  M.save(data_file, projects)
end

-- -----------------------------------------------------------------
--  Tag update
-- -----------------------------------------------------------------
function M.update_tags(data_file, projects, project_name, new_tags)
  for _, p in ipairs(projects) do
    if p.name == project_name then
      p.tags = new_tags
      break
    end
  end
  M.save(data_file, projects)
end

-- -----------------------------------------------------------------
--  Fuzzy score
-- -----------------------------------------------------------------
function M.fuzzy_score(str, query)
  if query == "" then return 1 end
  str   = str:lower()
  query = query:lower()
  if str:find(query, 1, true) then return 100 - #str end
  local si, qi, score, last = 1, 1, 0, 0
  while si <= #str and qi <= #query do
    if str:sub(si, si) == query:sub(qi, qi) then
      score = score + (si - last <= 2 and 10 or 1)
      last  = si; qi = qi + 1
    end
    si = si + 1
  end
  return qi > #query and score or 0
end

-- -----------------------------------------------------------------
--  Filter + sort
-- -----------------------------------------------------------------
function M.filter(projects, query, active_tags, sort_by, tag_and)
  local results = {}
  for _, p in ipairs(projects) do
    -- tag filter: OR (any match) or AND (all must match)
    local tag_ok = (#active_tags == 0)
    if not tag_ok then
      if tag_and then
        -- AND: every active tag must appear in project tags
        tag_ok = true
        for _, at in ipairs(active_tags) do
          local found = false
          for _, pt in ipairs(p.tags or {}) do if pt == at then found = true; break end end
          if not found then tag_ok = false; break end
        end
      else
        -- OR: at least one active tag in project tags
        for _, at in ipairs(active_tags) do
          for _, pt in ipairs(p.tags or {}) do
            if pt == at then tag_ok = true; break end
          end
          if tag_ok then break end
        end
      end
    end
    if tag_ok then
      local search_str = p.name .. " " .. p.category
      for _, t in ipairs(p.tags or {}) do search_str = search_str .. " " .. t end
      local score = M.fuzzy_score(search_str, query)
      if score > 0 then
        table.insert(results, { project = p, score = score })
      end
    end
  end

  if sort_by == "recent" and query == "" then
    -- When no search query, sort by last_opened desc (never-opened go last, alpha)
    table.sort(results, function(a, b)
      local ta = a.project.last_opened or 0
      local tb = b.project.last_opened or 0
      if ta ~= tb then return ta > tb end
      return a.project.name < b.project.name
    end)
  else
    table.sort(results, function(a, b)
      if a.score ~= b.score then return a.score > b.score end
      return a.project.name < b.project.name
    end)
  end

  local out = {}
  for _, r in ipairs(results) do table.insert(out, r.project) end
  return out
end

-- -----------------------------------------------------------------
--  All unique tags
-- -----------------------------------------------------------------
function M.all_tags(projects)
  local seen, tags = {}, {}
  for _, p in ipairs(projects) do
    for _, t in ipairs(p.tags or {}) do
      if not seen[t] then seen[t] = true; table.insert(tags, t) end
    end
  end
  table.sort(tags)
  return tags
end

-- -----------------------------------------------------------------
--  Add a newly created project into the in-memory list + save
-- -----------------------------------------------------------------
function M.add_project(data_file, projects, proj)
  table.insert(projects, proj)
  M.save(data_file, projects)
end

-- -----------------------------------------------------------------
--  Remove a project from the in-memory list + save
-- -----------------------------------------------------------------
function M.remove_project(data_file, projects, project_name)
  for i, p in ipairs(projects) do
    if p.name == project_name then
      table.remove(projects, i)
      break
    end
  end
  M.save(data_file, projects)
end

return M
