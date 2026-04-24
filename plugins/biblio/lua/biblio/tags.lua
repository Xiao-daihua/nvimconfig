-- biblio.nvim :: tags
--
-- Bulk tag operations. The tricky bit is that tags live in the `tags:`
-- frontmatter field of every topic .md file, and we need to rewrite them
-- IN-PLACE without touching the rest of the file (especially without
-- touching anything below the `---` terminator).
--
-- Our topics use the flow-sequence form:  tags: [A, B, "C with spaces"]
-- Writing this form keeps round-trips stable with the scanner.

local cfg     = require("biblio.config")
local scanner = require("biblio.scanner")
local util    = require("biblio.util")
local ui      = require("biblio.ui")

local M = {}

--- Format a Lua list of tag strings back into a flow-sequence YAML value.
---   {"A", "B C"}   -->   "[A, \"B C\"]"
---@param list string[]
---@return string
local function format_flow_tags(list)
  local parts = {}
  for _, t in ipairs(list) do
    if t:find("[,%[%]:\"']") or t:find("^%s") or t:find("%s$") then
      -- Anything YAML-meaningful or leading/trailing whitespace → quote it.
      table.insert(parts, string.format('"%s"', t:gsub('"', '\\"')))
    else
      table.insert(parts, t)
    end
  end
  return "[" .. table.concat(parts, ", ") .. "]"
end

--- Read, edit, and write back a topic file. Rewrites ONLY the tags: line in
--- the frontmatter, preserving everything else byte-for-byte.
---@param path string
---@param transform fun(tags: string[]): string[]
---@return boolean ok, string|nil err
local function rewrite_tags(path, transform)
  local content = util.read_file(path)
  if not content then return false, "could not read " .. path end

  -- Find frontmatter boundaries
  if not content:match("^%-%-%-%s*\n") then
    return false, "no frontmatter in " .. path
  end
  local fm_start, _ = content:find("^%-%-%-%s*\n")
  local _, fm_end = content:find("\n%-%-%-%s*\n", 4)
  if not fm_end then
    return false, "no closing --- in " .. path
  end

  local before  = content:sub(1, fm_start + 3)      -- "---\n"
  local fm_body = content:sub(fm_start + 4, fm_end - 4)  -- everything between "---\n" and "\n---\n"
  local after   = content:sub(fm_end - 3)           -- "---\n" + body

  -- Find the tags line. Handle three forms: flow [A, B], empty, or block seq.
  -- We only touch lines that start with "tags:" at column 0.
  local lines = {}
  for line in (fm_body .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end

  local tags_line_idx, tags_block_end_idx
  for i, line in ipairs(lines) do
    if line:match("^tags%s*:") then
      tags_line_idx = i
      -- Is this a block sequence (tags: followed by "  - item" lines)?
      if line:match("^tags%s*:%s*$") then
        tags_block_end_idx = i
        for j = i + 1, #lines do
          if lines[j]:match("^%s+%-") then
            tags_block_end_idx = j
          else
            break
          end
        end
      else
        tags_block_end_idx = i
      end
      break
    end
  end

  -- Read the existing tags via the scanner-style logic: easier to just call
  -- scanner to get the frontmatter, and trust it.
  local _, body_unused = nil, nil
  _ = body_unused
  -- Reuse scanner's parser by stitching a pseudo-frontmatter
  local parser_path = path  -- scanner.scan_topics reads all topics; grab this one's tags
  local existing_tags = {}
  for _, t in ipairs(scanner.scan_topics()) do
    if t.path == path then
      existing_tags = t.tags or {}
      break
    end
  end

  local new_tags = transform(existing_tags)
  local new_line = "tags: " .. format_flow_tags(new_tags)

  local new_lines = {}
  if tags_line_idx then
    for i, line in ipairs(lines) do
      if i == tags_line_idx then
        table.insert(new_lines, new_line)
      elseif tags_block_end_idx and i > tags_line_idx and i <= tags_block_end_idx then
        -- Skip block-sequence continuation lines; we've replaced with a flow list.
      else
        table.insert(new_lines, line)
      end
    end
  else
    -- No existing tags line: append one just before the closing ---.
    for _, line in ipairs(lines) do table.insert(new_lines, line) end
    table.insert(new_lines, new_line)
  end

  local new_fm_body = table.concat(new_lines, "\n")
  local new_content = before .. new_fm_body .. after

  return util.write_file(path, new_content)
end

---@param topics BiblioTopic[]
---@param old_tag string
---@param new_tag string|nil   nil = delete
---@return integer touched      how many files changed
local function bulk_rename(topics, old_tag, new_tag)
  local touched = 0
  for _, t in ipairs(topics) do
    if vim.tbl_contains(t.tags, old_tag) then
      local ok, err = rewrite_tags(t.path, function(existing)
        local result = {}
        local added_replacement = false
        for _, tag in ipairs(existing) do
          if tag == old_tag then
            if new_tag then
              if not vim.tbl_contains(result, new_tag) then
                table.insert(result, new_tag)
                added_replacement = true
              end
              -- If new_tag was already in existing, skip (dedupe).
            end
            -- else: drop
          elseif tag == new_tag and added_replacement then
            -- Dedupe: new_tag already inserted as replacement.
          else
            table.insert(result, tag)
          end
        end
        return result
      end)
      if ok then
        touched = touched + 1
      else
        util.notify("Failed to update " .. t.path .. ": " .. (err or "?"),
          vim.log.levels.ERROR)
      end
    end
  end
  return touched
end

--- Public: rename `old_tag` to `new_tag` across all topics.
---@param old_tag string
---@param new_tag string
---@return integer touched
function M.rename(old_tag, new_tag)
  if old_tag == "" or new_tag == "" then return 0 end
  if old_tag == new_tag then return 0 end
  local topics = scanner.scan_topics()
  return bulk_rename(topics, old_tag, new_tag)
end

--- Public: remove `tag` from every topic that has it.
---@param tag string
---@return integer touched
function M.delete(tag)
  if tag == "" then return 0 end
  local topics = scanner.scan_topics()
  return bulk_rename(topics, tag, nil)
end

--- Public: add `tag` to each of the given topic paths. No-op if the topic
--- already has that tag.
---@param topic_paths string[]
---@param tag string
---@return integer touched
function M.apply_to_topics(topic_paths, tag)
  if tag == "" or #topic_paths == 0 then return 0 end
  local touched = 0
  for _, path in ipairs(topic_paths) do
    local ok, err = rewrite_tags(path, function(existing)
      if vim.tbl_contains(existing, tag) then return existing end
      local result = {}
      for _, t in ipairs(existing) do table.insert(result, t) end
      table.insert(result, tag)
      return result
    end)
    if ok then
      touched = touched + 1
    else
      util.notify("Failed to update " .. path .. ": " .. (err or "?"),
        vim.log.levels.ERROR)
    end
  end
  return touched
end

-- Exposed for testing
M._format_flow_tags = format_flow_tags
M._rewrite_tags     = rewrite_tags

return M
