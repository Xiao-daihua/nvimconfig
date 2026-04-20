-- biblio.nvim :: topic
-- The "new topic" flow:
--   1. Prompt for title
--   2. Multi-select from existing tags; allow adding new ones
--   3. Write a starter _database/NNNN<slug>.md with frontmatter + stub
--   4. Open it for editing

local util    = require("biblio.util")
local cfg     = require("biblio.config")
local ui      = require("biblio.ui")
local scanner = require("biblio.scanner")

local M = {}

--- Build the topic markdown content.
local function build_content(title, tags)
  local lines = { "---", "layout: topic" }
  table.insert(lines, string.format('title: %s', title))
  if tags and #tags > 0 then
    local quoted = {}
    for _, t in ipairs(tags) do
      -- Jekyll accepts unquoted tags unless they contain a comma or bracket.
      if t:find("[,%[%]]") then
        table.insert(quoted, string.format('"%s"', t))
      else
        table.insert(quoted, t)
      end
    end
    table.insert(lines, "tags: [" .. table.concat(quoted, ", ") .. "]")
  else
    table.insert(lines, "tags: []")
  end
  table.insert(lines, "---")
  table.insert(lines, "")
  table.insert(lines, "<!-- Describe the topic here. Link to papers with [Title](/papers/slug/). -->")
  table.insert(lines, "")
  return table.concat(lines, "\n")
end

--- Entry point: prompt for title, then tags, then write.
---@param on_done fun(absolute_path:string, slug:string)|nil
function M.prompt_new_topic(on_done)
  ui.line_input({
    title  = " New Topic ",
    prompt = "Topic title (e.g. Boundary CFT):",
  }, function(title)
    if title == "" then
      util.notify("Empty title; aborting.", vim.log.levels.WARN)
      return
    end

    local existing_tags = scanner.all_tags()

    ui.multi_select({
      title       = string.format(" Tags for: %s ", title),
      items       = existing_tags,
      allow_new   = true,
      new_prompt  = "New tag:",
    }, function(tags)
      local slug = util.slugify(title)
      if slug == "" then slug = "untitled" end

      local _, abs_path = util.unique_topic_filename(cfg.database_path(), slug)
      local content = build_content(title, tags)

      local ok, err = util.write_file(abs_path, content)
      if not ok then
        util.notify("Write failed: " .. (err or "unknown"), vim.log.levels.ERROR)
        return
      end
      util.notify(string.format("Created %s", vim.fn.fnamemodify(abs_path, ":t")))

      if on_done then on_done(abs_path, util.slug_of(abs_path)) end
    end)
  end)
end

M._build_content = build_content

return M
