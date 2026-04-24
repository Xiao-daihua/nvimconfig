-- biblio.nvim :: dashboard
--
-- A single composite floating UI (not a tab). Layout:
--
--   ┌─ biblio ──────────────────────────────────────────────┐
--   │ › search · type to filter · Esc → normal · q to close       │
--   ├────────┬──────────────────────┬───────────────────────┤
--   │  TAGS  │       TOPICS         │        PAPERS         │
--   │        │  (filtered by tag)   │  (linked by topic)    │
--   │        │                      │                       │
--   ├────────┴──────────────────────┴───────────────────────┤
--   │ np new paper  nt new topic  / search  ? help  q quit  │
--   └───────────────────────────────────────────────────────┘
--
-- Each panel is its own floating window positioned relative to the editor.

local cfg     = require("biblio.config")
local scanner = require("biblio.scanner")
local util    = require("biblio.util")
local paper   = require("biblio.paper")
local topic   = require("biblio.topic")
local ui      = require("biblio.ui")

local M = {}

---@class DashState
---@field data { topics: BiblioTopic[], papers: BiblioPaper[], tags: string[] }
---@field selected_tag string
---@field selected_topic BiblioTopic|nil
---@field topics_view BiblioTopic[]
---@field papers_view BiblioPaper[]
---@field search_query string
---@field wins table<string, integer>
---@field bufs table<string, integer>
local S = nil

local PANES = { "search", "tags", "topics", "papers", "hints" }

-- ─── layout ─────────────────────────────────────────────────────────────────

local function compute_geometry()
  local total_cols  = vim.o.columns
  local total_lines = vim.o.lines - vim.o.cmdheight - 2

  local outer_w = math.min(160, math.max(80, math.floor(total_cols  * 0.90)))
  local outer_h = math.min(48,  math.max(20, math.floor(total_lines * 0.85)))
  local outer_row = math.floor((total_lines - outer_h) / 2)
  local outer_col = math.floor((total_cols  - outer_w) / 2)

  local search_h = 3   -- 1 content row + border
  local hints_h  = 3
  local gap      = 1
  local body_h   = outer_h - search_h - hints_h - gap * 2
  if body_h < 8 then body_h = 8 end

  local tags_w   = math.max(16, math.floor(outer_w * 0.16))
  local topics_w = math.max(26, math.floor(outer_w * 0.32))
  local papers_w = outer_w - tags_w - topics_w - 2

  return {
    search = { row = outer_row, col = outer_col, width = outer_w, height = search_h },
    tags   = { row = outer_row + search_h + gap, col = outer_col,
               width = tags_w, height = body_h },
    topics = { row = outer_row + search_h + gap, col = outer_col + tags_w + 1,
               width = topics_w, height = body_h },
    papers = { row = outer_row + search_h + gap, col = outer_col + tags_w + topics_w + 2,
               width = papers_w, height = body_h },
    hints  = { row = outer_row + search_h + gap + body_h + gap, col = outer_col,
               width = outer_w, height = hints_h },
  }
end

-- ─── helpers ────────────────────────────────────────────────────────────────

local function is_open()
  if not S then return false end
  for _, pane in ipairs(PANES) do
    local w = S.wins[pane]
    if not w or not vim.api.nvim_win_is_valid(w) then return false end
  end
  return true
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function papers_linked_from(t, papers)
  local by_slug = {}
  for _, p in ipairs(papers) do by_slug[p.slug] = p end
  local found, seen = {}, {}
  local prefix_escaped = cfg.options.paper_url_prefix:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  for slug in (t.body or ""):gmatch(prefix_escaped .. "([%w%-_]+)/") do
    if by_slug[slug] and not seen[slug] then
      seen[slug] = true
      table.insert(found, by_slug[slug])
    end
  end
  return found
end

local function matches(hay, needle)
  if not needle or needle == "" then return true end
  return hay:lower():find(needle:lower(), 1, true) ~= nil
end

-- ─── rendering ──────────────────────────────────────────────────────────────

-- Search bar prompt. Plain ASCII — no emoji — for consistent column math and
-- terminal compatibility.
local SEARCH_PROMPT = "  › "
local SEARCH_PLACEHOLDER = "type to filter · Esc → normal mode · q to close"

local function render_search()
  local q = S.search_query or ""
  local line
  if q == "" then
    line = SEARCH_PROMPT .. SEARCH_PLACEHOLDER
  else
    line = SEARCH_PROMPT .. q
  end
  set_lines(S.bufs.search, { line })
end

local function render_hints()
  local serve_marker = require("biblio.serve").is_running() and "■" or "▶"
  local line1 = string.format(
    "  np new   nt topic   / search   %s s serve   gc commit   m mark  a tag   ? help   q quit",
    serve_marker)
  set_lines(S.bufs.hints, { line1 })
end

local function render_tags()
  local lines = {}
  local q = S.search_query or ""
  local all_marker = (S.selected_tag == "") and "▸ " or "  "
  table.insert(lines, all_marker .. "All")
  for _, t in ipairs(S.data.tags) do
    if matches(t, q) then
      local marker = (S.selected_tag == t) and "▸ " or "  "
      table.insert(lines, marker .. t)
    end
  end
  set_lines(S.bufs.tags, lines)
end

local function render_topics()
  local view = {}
  local q = S.search_query or ""
  for _, t in ipairs(S.data.topics) do
    local tag_ok = (S.selected_tag == "") or vim.tbl_contains(t.tags, S.selected_tag)
    if tag_ok then
      if q == "" then
        table.insert(view, t)
      else
        local hay = (t.title or "") .. "\n" .. table.concat(t.tags or {}, " ") .. "\n" .. (t.body or "")
        if matches(hay, q) then table.insert(view, t) end
      end
    end
  end
  table.sort(view, function(a, b) return (a.title or "") < (b.title or "") end)
  S.topics_view = view

  local lines = {}
  if #view == 0 then
    table.insert(lines, "  (none)")
  else
    for _, t in ipairs(view) do
      local marker = S.selected_topics[t.path] and "✓ " or "  "
      table.insert(lines, marker .. (t.title or t.slug))
    end
  end
  set_lines(S.bufs.topics, lines)
end

local function render_papers()
  local q = S.search_query or ""
  local view
  if S.selected_topic then
    view = papers_linked_from(S.selected_topic, S.data.papers)
  else
    view = {}
    for _, p in ipairs(S.data.papers) do table.insert(view, p) end
  end
  if q ~= "" then
    local filtered = {}
    for _, p in ipairs(view) do
      local hay = (p.title or "") .. "\n" .. table.concat(p.authors or {}, " ") .. "\n" ..
                  (p.abstract or "") .. "\n" .. tostring(p.year or "") .. "\n" ..
                  (p.journal or "") .. "\n" .. (p.arxiv or "") .. "\n" .. (p.doi or "")
      if matches(hay, q) then table.insert(filtered, p) end
    end
    view = filtered
  end
  table.sort(view, function(a, b)
    local ay = tostring(a.year or ""); local by = tostring(b.year or "")
    if ay == by then return (a.title or "") < (b.title or "") end
    return ay < by
  end)
  S.papers_view = view

  local lines = {}
  if #view == 0 then
    table.insert(lines, "  (no papers)")
  else
    for _, p in ipairs(view) do
      local year = tostring(p.year or ""); if year == "" then year = "----" end
      local authors
      if p.authors and #p.authors > 0 then
        authors = p.authors[1]
        if #p.authors > 1 then authors = authors .. " et al." end
      else authors = "(unknown)" end
      table.insert(lines, string.format("  %-4s  %-22s  %s", year, authors, p.title or ""))
    end
  end
  set_lines(S.bufs.papers, lines)
end

local function render_all()
  render_search(); render_hints()
  render_tags(); render_topics(); render_papers()
end

-- ─── interactions ───────────────────────────────────────────────────────────

local function item_under_cursor(pane)
  local win = S.wins[pane]
  if not win or not vim.api.nvim_win_is_valid(win) then return nil end
  local row = vim.api.nvim_win_get_cursor(win)[1]
  if pane == "tags" then
    if row == 1 then return "" end
    local q = S.search_query or ""
    local filtered = {}
    for _, t in ipairs(S.data.tags) do
      if matches(t, q) then table.insert(filtered, t) end
    end
    return filtered[row - 1]
  end
  if pane == "topics" then return S.topics_view[row] end
  if pane == "papers" then return S.papers_view[row] end
  return nil
end

local function on_tag_move()
  local tag = item_under_cursor("tags")
  if tag == nil then return end
  if tag ~= S.selected_tag then
    S.selected_tag = tag
    S.selected_topic = nil
    render_tags(); render_topics(); render_papers()
  end
end

local function on_topic_move()
  local t = item_under_cursor("topics")
  if type(t) == "table" and S.selected_topic ~= t then
    S.selected_topic = t
    render_papers()
  end
end

--- Open `path` for editing via util.open_file_for_editing. Centralized so
--- the new-topic and paper-preview flows can share the same logic.
local function open_file_for_editing(path)
  util.open_file_for_editing(path, cfg.options.open_cmd)
end

local function open_selected(pane)
  local item = item_under_cursor(pane)
  if not item then return end
  if pane == "tags" then
    vim.api.nvim_set_current_win(S.wins.topics); return
  end
  if type(item) ~= "table" or not item.path then return end
  local path = item.path
  M.close()
  open_file_for_editing(path)
end

local function do_delete(pane)
  local item = item_under_cursor(pane)
  if type(item) ~= "table" or not item.path then return end
  if not ui.confirm("Delete " .. vim.fn.fnamemodify(item.path, ":t") .. "?") then return end
  local ok, err = os.remove(item.path)
  if not ok then
    util.notify("Delete failed: " .. (err or "?"), vim.log.levels.ERROR); return
  end
  util.notify("Deleted " .. vim.fn.fnamemodify(item.path, ":t"))
  M.refresh()
end

local function focus_search()
  vim.api.nvim_set_current_win(S.wins.search)
  vim.bo[S.bufs.search].modifiable = true
  vim.api.nvim_buf_set_lines(S.bufs.search, 0, -1, false, { SEARCH_PROMPT })
  vim.api.nvim_win_set_cursor(S.wins.search, { 1, #SEARCH_PROMPT })
  vim.cmd("startinsert!")
end

local function strip_prompt(line)
  line = line or ""
  -- Remove the leading "  › " prompt (and any stray leading whitespace).
  local stripped = line:gsub("^%s*›%s*", "")
  return (stripped:gsub("^%s+", ""))
end

local function commit_search()
  local line = vim.api.nvim_buf_get_lines(S.bufs.search, 0, 1, false)[1] or ""
  S.search_query = strip_prompt(line)
  S.selected_topic = nil
  render_all()
  vim.cmd("stopinsert")
  if #S.topics_view > 0 then
    vim.api.nvim_set_current_win(S.wins.topics)
    pcall(vim.api.nvim_win_set_cursor, S.wins.topics, { 1, 0 })
  elseif #S.papers_view > 0 then
    vim.api.nvim_set_current_win(S.wins.papers)
    pcall(vim.api.nvim_win_set_cursor, S.wins.papers, { 1, 0 })
  else
    vim.api.nvim_set_current_win(S.wins.tags)
  end
end

local function clear_search_inplace(buf)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { SEARCH_PROMPT })
  vim.api.nvim_win_set_cursor(S.wins.search, { 1, #SEARCH_PROMPT })
  S.search_query = ""
  render_tags(); render_topics(); render_papers()
end

local function show_help()
  local km = cfg.options.keymaps
  local function row(k, d) return string.format("  %-18s  %s", k, d) end
  local lines = {
    "",
    "  biblio.nvim — keybindings",
    "",
    "  NAVIGATION",
    row(km.focus_tags,    "Focus Tags pane"),
    row(km.focus_topics,  "Focus Topics pane"),
    row(km.focus_papers,  "Focus Papers pane"),
    row("h / l",          "Move one pane left / right"),
    row("j / k",          "Down / up within a pane"),
    row("j in search",    "Jump from search bar into topics pane"),
    row(km.open_item,     "Open selected item for editing"),
    "",
    "  CREATE",
    row(km.new_paper,     "New paper (paste BibTeX; preview before saving)"),
    row(km.new_topic,     "New topic (title + tag picker)"),
    "",
    "  TAGS (on Tags pane)",
    row("R",              "Rename tag under cursor (updates all topics)"),
    row("D",              "Delete tag from all topics (confirmed)"),
    "",
    "  BATCH-TAG TOPICS (on Topics pane)",
    row("m",              "Mark / unmark topic for batch op (✓ shown)"),
    row("M",              "Unmark all"),
    row("a",              "Add tag(s) to marked topics (or cursor topic)"),
    "",
    "  IN EDITOR (when editing a topic .md file)",
    row("<C-p>",          "Pick a paper and insert [Title](/papers/slug/)"),
    "",
    "  SEARCH & FILTER",
    row(km.search,        "Focus the search bar (starts in insert mode)"),
    row("<Esc> insert",   "Drop to normal mode (stays in search bar)"),
    row("<CR>",           "Commit query, jump to results pane"),
    row("j normal",       "Jump from search into topics pane"),
    row("<C-u> insert",   "Clear the query"),
    "",
    "  JEKYLL PREVIEW",
    row(km.serve,         "Toggle jekyll serve (start if stopped, stop if running)"),
    row(km.preview,       "Open http://127.0.0.1:4000/ in default browser"),
    "",
    "  GIT",
    row(km.commit,        "Commit: float with status + message editor"),
    row(km.push,          "Push current branch"),
    row(km.sync,          "Commit and push in one go"),
    "",
    "  OTHER",
    row(km.delete_item,   "Delete selected item (with confirmation)"),
    row(km.refresh,       "Refresh — rescan _database/ and _papers/"),
    row(km.help,          "This help"),
    row(km.quit,          "Close dashboard"),
    "",
    "  MODE CONVENTION: <Esc> in any input float drops to normal mode",
    "  (never closes the UI). Use q in normal mode to cancel / close.",
    "",
    "  Press any key to close this help.",
    "",
  }
  local buf = ui.scratch_buf({ filetype = "biblio_help" })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local total_cols = vim.o.columns
  local total_lines = vim.o.lines - vim.o.cmdheight - 2
  local w = math.min(72, total_cols - 4)
  local h = math.min(#lines + 2, total_lines - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((total_lines - h) / 2),
    col = math.floor((total_cols - w) / 2),
    width = w, height = h,
    style = "minimal", border = "rounded",
    title = " help ", title_pos = "center",
  })
  vim.wo[win].cursorline = false
  vim.wo[win].number = false
  vim.wo[win].signcolumn = "no"
  local function close_help()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  for _, key in ipairs({ "<Esc>", "q", "?", "<CR>", "<Space>" }) do
    vim.keymap.set("n", key, close_help, { buffer = buf, nowait = true, silent = true })
  end
end

-- ─── keymap attachment ──────────────────────────────────────────────────────

local function map_buf(buf, lhs, rhs, mode)
  vim.keymap.set(mode or "n", lhs, rhs,
    { buffer = buf, silent = true, nowait = true })
end

-- ─── tag & batch operations ────────────────────────────────────────────────

--- Prompt the user to rename the tag under the cursor in the tags pane.
local function tag_rename_prompt()
  local tag = item_under_cursor("tags")
  if type(tag) ~= "string" or tag == "" then
    util.notify("Put the cursor on a tag first (not 'All').", vim.log.levels.WARN)
    return
  end

  ui.line_input({
    title  = " Rename tag ",
    prompt = "Rename tag '" .. tag .. "' to:",
    default = tag,
  }, function(new_name)
    if new_name == "" or new_name == tag then
      util.notify("Rename cancelled.")
      return
    end
    local n = require("biblio.tags").rename(tag, new_name)
    util.notify(string.format("Renamed tag '%s' → '%s' in %d topic(s).",
      tag, new_name, n))
    if S.selected_tag == tag then S.selected_tag = new_name end
    M.refresh()
  end)
end

--- Delete the tag under the cursor (with confirmation).
local function tag_delete_prompt()
  local tag = item_under_cursor("tags")
  if type(tag) ~= "string" or tag == "" then
    util.notify("Put the cursor on a tag first (not 'All').", vim.log.levels.WARN)
    return
  end
  if not ui.confirm(string.format("Remove tag '%s' from all topics?", tag)) then
    return
  end
  local n = require("biblio.tags").delete(tag)
  util.notify(string.format("Removed '%s' from %d topic(s).", tag, n))
  if S.selected_tag == tag then S.selected_tag = "" end
  M.refresh()
end

--- Toggle multi-select on the topic under cursor.
local function topic_toggle_select()
  local t = item_under_cursor("topics")
  if type(t) ~= "table" or not t.path then return end
  if S.selected_topics[t.path] then
    S.selected_topics[t.path] = nil
  else
    S.selected_topics[t.path] = true
  end
  render_topics()
end

--- Clear all multi-selected topics.
local function topic_clear_selection()
  S.selected_topics = {}
  render_topics()
end

--- Apply a tag to all multi-selected topics (or just the one under cursor
--- if nothing is multi-selected).
local function topic_apply_tag()
  local targets = {}
  for path, _ in pairs(S.selected_topics) do table.insert(targets, path) end
  if #targets == 0 then
    local t = item_under_cursor("topics")
    if type(t) == "table" and t.path then
      table.insert(targets, t.path)
    end
  end
  if #targets == 0 then
    util.notify("No topics selected. Press m on topics to select.", vim.log.levels.WARN)
    return
  end

  -- Offer existing tags + allow creating new via line_input
  local all_tags = {}
  for _, t in ipairs(S.data.tags) do table.insert(all_tags, t) end

  ui.multi_select({
    title      = string.format(" Tag %d topic(s) ", #targets),
    items      = all_tags,
    allow_new  = true,
    new_prompt = "New tag:",
  }, function(chosen)
    if #chosen == 0 then
      util.notify("No tags chosen.")
      return
    end
    local total = 0
    for _, tag in ipairs(chosen) do
      total = total + require("biblio.tags").apply_to_topics(targets, tag)
    end
    util.notify(string.format("Applied %d tag(s) across %d topic(s) (%d updates).",
      #chosen, #targets, total))
    S.selected_topics = {}
    M.refresh()
  end)
end

local function attach_pane_keymaps(buf, pane)
  local km = cfg.options.keymaps
  map_buf(buf, km.new_paper, function()
    paper.prompt_new_paper(function() M.refresh() end)
  end)
  map_buf(buf, km.new_topic, function()
    topic.prompt_new_topic(function(path)
      M.close()
      open_file_for_editing(path)
    end)
  end)
  map_buf(buf, km.search,       focus_search)
  map_buf(buf, km.refresh,      function() M.refresh() end)
  map_buf(buf, km.quit,         function() M.close() end)
  map_buf(buf, km.help,         show_help)
  map_buf(buf, km.focus_tags,   function() vim.api.nvim_set_current_win(S.wins.tags) end)
  map_buf(buf, km.focus_topics, function() vim.api.nvim_set_current_win(S.wins.topics) end)
  map_buf(buf, km.focus_papers, function() vim.api.nvim_set_current_win(S.wins.papers) end)
  map_buf(buf, km.open_item,    function() open_selected(pane) end)
  map_buf(buf, km.delete_item,  function() do_delete(pane) end)

  -- Jekyll preview + git. `serve` toggles (start if stopped, stop if running).
  -- After toggling we re-render the hints bar so the ▶/■ indicator updates.
  map_buf(buf, km.serve, function()
    require("biblio.serve").toggle()
    -- Give the job state a moment to settle before we re-render.
    vim.schedule(function() if S then render_hints() end end)
  end)
  map_buf(buf, km.preview, function() require("biblio.serve").open_browser() end)
  map_buf(buf, km.commit,  function() require("biblio.git").prompt_commit() end)
  map_buf(buf, km.push,    function() require("biblio.git").push() end)
  map_buf(buf, km.sync,    function() require("biblio.git").prompt_commit({ push = true }) end)

  -- Pane-specific operations.
  if pane == "tags" then
    map_buf(buf, "R", tag_rename_prompt)
    map_buf(buf, "D", tag_delete_prompt)   -- uppercase D to avoid collision with `d` (delete item)
  elseif pane == "topics" then
    map_buf(buf, "m", topic_toggle_select)      -- mark for batch ops
    map_buf(buf, "M", topic_clear_selection)    -- unmark all
    map_buf(buf, "a", topic_apply_tag)          -- add tag to marked topics (or current)
  end

  map_buf(buf, "h", function()
    if pane == "topics" then vim.api.nvim_set_current_win(S.wins.tags)
    elseif pane == "papers" then vim.api.nvim_set_current_win(S.wins.topics) end
  end)
  map_buf(buf, "l", function()
    if pane == "tags" then vim.api.nvim_set_current_win(S.wins.topics)
    elseif pane == "topics" then vim.api.nvim_set_current_win(S.wins.papers) end
  end)
end

local function attach_search_keymaps(buf)
  -- Normal mode:
  --   <CR>   commit query and jump to results pane
  --   q      close the whole dashboard
  --   i/a/o  (Vim default) re-enter insert to edit the query
  --   t/T/P  (via attach_pane_keymaps-style maps below) jump to other panes
  map_buf(buf, "<CR>", commit_search, "n")
  map_buf(buf, "q",    function() M.close() end, "n")

  -- Insert mode:
  --   <CR>   commit query and jump to results pane (also drops out of insert)
  --   <C-s>  same as <CR>
  --   <C-u>  clear the query in place, stay in insert
  --   <Esc>  (Vim default) drop to normal mode; never closes.
  map_buf(buf, "<CR>",  function() vim.cmd("stopinsert"); commit_search() end, "i")
  map_buf(buf, "<C-s>", function() vim.cmd("stopinsert"); commit_search() end, "i")
  map_buf(buf, "<C-u>", function() clear_search_inplace(buf) end, "i")

  -- Shortcuts to other panes (normal mode only — don't interfere with typing).
  local km = cfg.options.keymaps
  map_buf(buf, km.focus_tags,   function() vim.api.nvim_set_current_win(S.wins.tags)   end, "n")
  map_buf(buf, km.focus_topics, function() vim.api.nvim_set_current_win(S.wins.topics) end, "n")
  map_buf(buf, km.focus_papers, function() vim.api.nvim_set_current_win(S.wins.papers) end, "n")

  -- `j` from the search bar (normal mode) jumps to the first result in the
  -- topics pane. Since the search bar is a single line, `j` doing anything
  -- else would be a no-op — using it to "drop into results" matches how
  -- users naturally move "down" out of the search bar.
  map_buf(buf, "j", function()
    vim.api.nvim_set_current_win(S.wins.topics)
    pcall(vim.api.nvim_win_set_cursor, S.wins.topics, { 1, 0 })
  end, "n")
end

local function on_search_text_changed()
  local line = vim.api.nvim_buf_get_lines(S.bufs.search, 0, 1, false)[1] or ""
  local q = strip_prompt(line)
  if q == S.search_query then return end
  S.search_query = q
  S.selected_topic = nil
  render_tags(); render_topics(); render_papers()
end

-- ─── neo-tree integration ───────────────────────────────────────────────────

local function try_open_neotree(focus_win)
  if not cfg.options.open_neotree then return end
  local ok = pcall(require, "neo-tree")
  if not ok then return end
  local dir = cfg.options.blog_root

  -- neo-tree's :Neotree command often ends up with focus in the tree window,
  -- even when invoked from another window. We defer it, then re-assert the
  -- dashboard focus right after it settles.
  vim.schedule(function()
    -- `action=focus` would grab focus; `reveal=false` avoids extra jumping.
    -- We use `show` which opens without mandating focus, and then force our
    -- focus back regardless.
    pcall(vim.cmd, "Neotree filesystem show dir=" .. vim.fn.fnameescape(dir))
    vim.schedule(function()
      if focus_win and vim.api.nvim_win_is_valid(focus_win) then
        pcall(vim.api.nvim_set_current_win, focus_win)
      end
    end)
  end)
end

-- ─── public API ─────────────────────────────────────────────────────────────

function M.refresh()
  if not is_open() then return end
  S.data = scanner.scan_all()
  if S.selected_tag ~= "" and not vim.tbl_contains(S.data.tags, S.selected_tag) then
    S.selected_tag = ""
  end
  S.selected_topic = nil
  render_all()
end

function M.close()
  if not S then return end
  local wins = S.wins
  S = nil  -- clear state first so WinClosed callbacks don't re-enter
  for _, pane in ipairs(PANES) do
    local w = wins[pane]
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
end

function M.open()
  if is_open() then
    vim.api.nvim_set_current_win(S.wins.topics); return
  end

  if vim.fn.isdirectory(cfg.database_path()) == 0 or vim.fn.isdirectory(cfg.papers_path()) == 0 then
    util.notify(string.format(
      "Blog root looks wrong: expected %s and %s to exist.",
      cfg.database_path(), cfg.papers_path()), vim.log.levels.ERROR)
    return
  end

  local geom = compute_geometry()
  local bufs, wins = {}, {}

  local function mkwin(buf, g, title)
    local opts = {
      relative = "editor",
      row = g.row, col = g.col,
      width  = math.max(10, g.width - 2),
      height = math.max(1,  g.height - 2),
      style  = "minimal",
      border = "rounded",
    }
    if title then opts.title = title; opts.title_pos = "center" end
    return vim.api.nvim_open_win(buf, false, opts)
  end

  bufs.search = ui.scratch_buf({ filetype = "biblio_search" })
  wins.search = mkwin(bufs.search, geom.search, " biblio ")

  bufs.tags = ui.scratch_buf({ filetype = "biblio_tags" })
  wins.tags = mkwin(bufs.tags, geom.tags, " Tags ")

  bufs.topics = ui.scratch_buf({ filetype = "biblio_topics" })
  wins.topics = mkwin(bufs.topics, geom.topics, " Topics ")

  bufs.papers = ui.scratch_buf({ filetype = "biblio_papers" })
  wins.papers = mkwin(bufs.papers, geom.papers, " Papers ")

  bufs.hints = ui.scratch_buf({ filetype = "biblio_hints" })
  wins.hints = mkwin(bufs.hints, geom.hints, nil)

  for _, pane in ipairs(PANES) do
    local w = wins[pane]
    vim.wo[w].number         = false
    vim.wo[w].relativenumber = false
    vim.wo[w].signcolumn     = "no"
    vim.wo[w].foldcolumn     = "0"
    vim.wo[w].wrap           = false
    vim.wo[w].cursorline     = (pane == "tags" or pane == "topics" or pane == "papers")
    vim.wo[w].winhighlight   = "Normal:NormalFloat,CursorLine:Visual,FloatBorder:FloatBorder"
  end

  S = {
    bufs = bufs, wins = wins,
    data = scanner.scan_all(),
    selected_tag = "",
    selected_topic = nil,
    selected_topics = {},   -- path -> true for multi-selected topics
    topics_view = {},
    papers_view = {},
    search_query = "",
  }

  render_all()

  attach_pane_keymaps(bufs.tags,   "tags")
  attach_pane_keymaps(bufs.topics, "topics")
  attach_pane_keymaps(bufs.papers, "papers")
  attach_search_keymaps(bufs.search)

  local group = vim.api.nvim_create_augroup("BiblioDashboard", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter" },
    { group = group, buffer = bufs.tags,   callback = on_tag_move })
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter" },
    { group = group, buffer = bufs.topics, callback = on_topic_move })
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" },
    { group = group, buffer = bufs.search, callback = on_search_text_changed })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      if not S then return end
      local closed = tonumber(args.match)
      for _, pane in ipairs(PANES) do
        if S.wins[pane] == closed then
          vim.schedule(M.close); return
        end
      end
    end,
  })

  try_open_neotree(wins.topics)

  vim.api.nvim_set_current_win(wins.topics)
  pcall(vim.api.nvim_win_set_cursor, wins.topics, { 1, 0 })
end

return M
