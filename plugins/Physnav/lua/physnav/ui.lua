-- physnav/ui.lua  v6
-- Improvements over v5:
--   UI: filled header bars, accent left-bar on selection, coloured preview titlebar,
--       sidebar section header, richer status bar with query/tag context
--   Code: tag_color_cache reset fixed, new-note de-nested, keymap cleaned up,
--         AND tag filter mode, search shown inline in header

local M        = {}
local api      = vim.api
local proj_mod = require("physnav.projects")
local hl_mod   = require("physnav.highlights")
local git_mod  = require("physnav.git")

-- -----------------------------------------------------------------
--  State
-- -----------------------------------------------------------------
local state = {
  win         = nil,
  buf         = nil,
  cfg         = nil,
  projects    = {},
  filtered    = {},
  selected    = 1,
  query       = "",
  active_tags = {},
  -- "normal" | "tags"
  mode        = "normal",
  tag_cursor  = 1,
  tag_and     = false,   -- false=OR logic, true=AND logic for tag filter
  all_tags    = {},
  layout      = {},
  ns          = nil,
  git_status  = {},
}

-- tag colour cache: stored as module-level table, reset via pairs loop
local tag_color_cache = {}
local tag_color_idx   = 0

local function reset_tag_colors()
  for k in pairs(tag_color_cache) do tag_color_cache[k] = nil end
  tag_color_idx = 0
end

-- -----------------------------------------------------------------
--  Text helpers
-- -----------------------------------------------------------------
local function is_open()
  return state.win and api.nvim_win_is_valid(state.win)
end
local function dw(s)  return vim.fn.strdisplaywidth(s) end
local function pad(s, w)
  local d = dw(s); if d >= w then return s end
  return s .. string.rep(" ", w - d)
end
local function trunc(s, max_w)
  if dw(s) <= max_w then return s end
  local r = s
  while dw(r) > max_w - 1 and #r > 0 do r = r:sub(1, -2) end
  return r .. ">"
end

-- -----------------------------------------------------------------
--  Layout
-- -----------------------------------------------------------------
local function calc_layout(cfg)
  local ui  = api.nvim_list_uis()[1]
  local tw  = math.floor(ui.width  * cfg.width)
  local th  = math.floor(ui.height * cfg.height)
  local col = math.floor((ui.width  - tw) / 2)
  local row = math.floor((ui.height - th) / 2)
  local sb_w   = cfg.sidebar_width
  local pr_w   = cfg.preview_width
  local main_w = tw - sb_w - 2 - pr_w  -- 2 separators
  return {
    tw = tw, th = th, row = row, col = col,
    sb_w = sb_w, pr_w = pr_w, main_w = main_w,
    sep1 = sb_w,           -- col of left separator
    sep2 = sb_w + 1 + main_w,  -- col of right separator
  }
end

-- -----------------------------------------------------------------
--  Tag colour cycling (6 distinct colours, stable per tag name)
-- -----------------------------------------------------------------
local TAG_COLORS = {
  "PhysNavLatex", "PhysNavTypst", "PhysNavNotes",
  "PhysNavCourse", "PhysNavTag",  "PhysNavKey",
}
local function tag_hl(tag)
  if not tag_color_cache[tag] then
    tag_color_idx = (tag_color_idx % #TAG_COLORS) + 1
    tag_color_cache[tag] = TAG_COLORS[tag_color_idx]
  end
  return tag_color_cache[tag]
end

-- -----------------------------------------------------------------
--  Batched async git status
-- -----------------------------------------------------------------
local function load_git_statuses()
  local cb_map = {}
  for _, p in ipairs(state.projects) do
    local name = p.name
    cb_map[name] = function(s)
      state.git_status[name] = s or ""
      vim.schedule(function() if is_open() then M._render() end end)
    end
  end
  git_mod.status_async_batch(state.projects, cb_map)
end

-- -----------------------------------------------------------------
--  Render
-- -----------------------------------------------------------------
function M._render()
  if not is_open() then return end
  local buf    = state.buf
  local l      = state.layout
  local tw, th = l.tw, l.th
  local sb_w, main_w, pr_w = l.sb_w, l.main_w, l.pr_w

  -- Blank canvas
  local lines = {}
  for i = 1, th do lines[i] = string.rep(" ", tw) end

  local hls = {}
  local function push_hl(g, ln1, cs, ce)
    table.insert(hls, { g, ln1 - 1, cs, ce })
  end

  local function write(ln, col, text, grp)
    if ln < 1 or ln > th then return end
    local before = lines[ln]:sub(1, col)
    if #before < col then before = before .. string.rep(" ", col - #before) end
    lines[ln] = before .. text .. lines[ln]:sub(col + #text + 1)
    if grp then push_hl(grp, ln, col, col + #text) end
  end

  local function wpad(ln, col, text, width, grp)
    write(ln, col, pad(trunc(text, width), width), grp)
  end

  local sb_col   = 0
  local main_col = l.sep1 + 1
  local pr_col   = l.sep2 + 1

  -- Column separators
  for ln = 1, th do
    write(ln, l.sep1, "|", "PhysNavSep")
    write(ln, l.sep2, "|", "PhysNavSep")
  end

  -- -- Row 1: Header bars (filled background across each panel) --
  -- Sidebar header: "TAGS" + filter logic indicator
  local tag_logic = state.tag_and and " [AND]" or ""
  wpad(1, sb_col, " TAGS" .. tag_logic, sb_w, "PhysNavSidebarBar")

  -- Main header: title + live search query
  local q_sfx = ""
  if state.query ~= "" then
    q_sfx = '  / "' .. state.query .. '"'
  end
  -- Fill entire main header bar
  wpad(1, main_col, " PhysNav" .. q_sfx, main_w, "PhysNavHeaderBar")
  -- Re-colour just the search portion
  if state.query ~= "" then
    local qc = main_col + dw(" PhysNav  / ")
    push_hl("PhysNavSearch", 1, qc - 4, qc + dw('"' .. state.query .. '"'))
  end
  -- Re-colour "PhysNav" title portion
  push_hl("PhysNavHeaderTitle", 1, main_col, main_col + dw(" PhysNav"))

  -- Preview header: project count + mode badge (filled)
  local total_str = string.format(" %d/%d", #state.filtered, #state.projects)
  if state.mode == "tags" then total_str = total_str .. " [TAGS]" end
  wpad(1, pr_col, total_str, pr_w, "PhysNavHeaderBar")
  push_hl("PhysNavHeaderCount", 1, pr_col, pr_col + pr_w)

  -- -- Row 2: Context hint bar --
  -- Sidebar divider
  write(2, sb_col, string.rep("-", sb_w), "PhysNavSep")
  write(2, pr_col, string.rep("-", pr_w), "PhysNavSep")

  local hint
  if state.mode == "tags" then
    hint = "  j/k  Enter toggle+back  Space toggle  a AND/OR  Esc cancel"
  elseif state.query ~= "" then
    hint = '  search: "' .. state.query .. '"   / change   <C-c> clear'
  elseif #state.active_tags > 0 then
    local logic = state.tag_and and "AND" or "OR"
    hint = "  [" .. logic .. "] " .. table.concat(state.active_tags, " | ") .. "   <C-c> clear"
  else
    hint = "  /  search   T  tags   n  new   d  del   g  push   l  log   ?  help"
  end
  wpad(2, main_col, hint, main_w, "PhysNavHint")
  -- Highlight active filter parts
  if state.query ~= "" or #state.active_tags > 0 then
    push_hl("PhysNavHintActive", 2, main_col, main_col + 2)
  end

  -- -- Sidebar: tag list --
  local all_active = (#state.active_tags == 0)
  local all_label  = string.format("  %s All  (%d)",
    all_active and "*" or " ", #state.projects)
  wpad(3, sb_col, all_label, sb_w,
    all_active and "PhysNavTagAllActive" or "PhysNavTagInactive")

  for i, tag in ipairs(state.all_tags) do
    local ln = 3 + i
    if ln > th - 1 then break end
    local cnt = 0
    for _, p in ipairs(state.projects) do
      for _, t in ipairs(p.tags or {}) do if t == tag then cnt = cnt + 1; break end end
    end
    local active = vim.tbl_contains(state.active_tags, tag)
    local is_cur = (state.mode == "tags" and i == state.tag_cursor)
    local mark   = active and "*" or " "
    local label  = string.format("  %s %s (%d)", mark, trunc(tag, sb_w - 8), cnt)

    if is_cur then
      wpad(ln, sb_col, label, sb_w, "PhysNavTagCursor")
    elseif active then
      wpad(ln, sb_col, label, sb_w, nil)
      push_hl("PhysNavTagActive", ln, sb_col, sb_col + 4)
      local ns = sb_col + 4
      push_hl(tag_hl(tag), ln, ns, ns + #trunc(tag, sb_w - 8))
      push_hl("PhysNavMuted", ln, ns + #trunc(tag, sb_w - 8),
        ns + #trunc(tag, sb_w - 8) + 5)
    else
      wpad(ln, sb_col, label, sb_w, "PhysNavTagInactive")
      local ns = sb_col + 4
      push_hl(tag_hl(tag), ln, ns, ns + #trunc(tag, sb_w - 8))
    end
  end

  -- -- Main: project list --
  local list_top    = 3
  local list_bottom = th - 1
  local list_rows   = list_bottom - list_top + 1
  local scroll      = math.max(0, state.selected - math.floor(list_rows / 2) - 1)

  for i, p in ipairs(state.filtered) do
    local ln = list_top + (i - 1) - scroll
    if ln < list_top    then goto continue end
    if ln > list_bottom then break end

    local is_sel  = (i == state.selected)
    local typ_str = p.type == "typst" and "[typ]" or "[tex]"
    local pdf_str = p.has_pdf and "+" or "."
    local lec_str = p.lec_count > 0 and string.format(" x%d", p.lec_count) or ""
    local gs      = state.git_status[p.name]
    local git_str = (gs and gs ~= "") and (" " .. gs) or ""
    local cat_ch  = p.category == "EPFL_lecture" and "E" or "N"

    -- Layout: [sel_bar][pdf] name... [type][lec][git] [cat]
    -- sel_bar = 2 chars (accent col + space), pdf = 1, space = 1, name, space, type, lec, git, space, cat
    local fixed  = 2 + 1 + 1 + #typ_str + #lec_str + #git_str + 2
    local name_w = math.max(4, main_w - fixed)
    local name   = trunc(p.name, name_w)

    if is_sel then
      -- Full selected row: filled background
      local row_txt = string.format("  %s %s%s%s%s %s",
        pdf_str, pad(name, name_w), typ_str, lec_str, git_str, cat_ch)
      wpad(ln, main_col, row_txt, main_w, "PhysNavSelected")
      -- Accent: first 2 cols of main panel = vertical bar feel
      push_hl("PhysNavSelAccent", ln, main_col, main_col + 2)
      -- Type badge colour (on selected bg)
      local tc = main_col + 2 + 1 + 1 + name_w + 1
      push_hl(p.type == "typst" and "PhysNavTypstSel" or "PhysNavLatexSel",
        ln, tc, tc + #typ_str)
    else
      local row_txt = string.format("  %s %s%s%s%s %s",
        pdf_str, pad(name, name_w), typ_str, lec_str, git_str, cat_ch)
      wpad(ln, main_col, row_txt, main_w, nil)
      -- pdf dot
      push_hl(p.has_pdf and "PhysNavPDF" or "PhysNavNoPDF",
        ln, main_col + 2, main_col + 3)
      -- name
      push_hl("PhysNavNormal", ln, main_col + 4, main_col + 4 + name_w)
      -- type badge
      local tc = main_col + 2 + 1 + 1 + name_w + 1
      push_hl(p.type == "typst" and "PhysNavTypst" or "PhysNavLatex",
        ln, tc, tc + #typ_str)
      -- lec count
      if #lec_str > 0 then
        push_hl("PhysNavLecCount", ln, tc + #typ_str, tc + #typ_str + #lec_str)
      end
      -- git
      if #git_str > 0 then
        local gc = tc + #typ_str + #lec_str + 1
        push_hl("PhysNavGitDirty", ln, gc, gc + #git_str)
      end
      -- category badge (last char)
      local cc = main_col + main_w - 1
      push_hl(p.category == "EPFL_lecture" and "PhysNavCatEPFL" or "PhysNavCatNotes",
        ln, cc, cc + 1)
    end
    ::continue::
  end

  -- -- Preview panel --
  local sel = state.filtered[state.selected]
  if sel then
    local pr_ln = 3

    -- Coloured project title bar
    local title_hl = sel.type == "typst" and "PhysNavPreviewBarTyp" or "PhysNavPreviewBarTex"
    local type_badge = sel.type == "typst" and " typ" or " tex"
    wpad(pr_ln, pr_col,
      pad(type_badge, 5) .. trunc(sel.name, pr_w - 5),
      pr_w, title_hl)
    pr_ln = pr_ln + 1

    -- Fields
    local gs_val = state.git_status[sel.name]
    local fields = {
      { "cat",  sel.category,  "PhysNavPreviewVal" },
      { "main", sel.main or "-", "PhysNavPreviewVal" },
      { "path", trunc(sel.path, pr_w - 7), "PhysNavMuted" },
      { "lec",  sel.lec_count > 0 and tostring(sel.lec_count) or "-",
                               "PhysNavLecCount" },
      { "pdf",  sel.has_pdf and "yes" or "no",
                sel.has_pdf and "PhysNavPDF" or "PhysNavNoPDF" },
      { "git",  (gs_val and gs_val ~= "") and gs_val or "clean",
                (gs_val and gs_val ~= "") and "PhysNavGitDirty" or "PhysNavGitClean" },
    }
    for _, f in ipairs(fields) do
      if pr_ln > th - 6 then break end
      local kw  = 6
      local key = pad(" " .. f[1], kw)
      local val = trunc(tostring(f[2]), pr_w - kw - 1)
      write(pr_ln, pr_col, pad(key .. " " .. val, pr_w), nil)
      push_hl("PhysNavPreviewKey", pr_ln, pr_col, pr_col + kw)
      push_hl(f[3], pr_ln, pr_col + kw + 1, pr_col + pr_w)
      pr_ln = pr_ln + 1
    end

    -- Tags section
    pr_ln = pr_ln + 1
    if pr_ln <= th - 4 then
      wpad(pr_ln, pr_col, " tags:", pr_w, "PhysNavPreviewKey"); pr_ln = pr_ln + 1
    end
    if pr_ln <= th - 3 then
      local tags = sel.tags or {}
      if #tags > 0 then
        wpad(pr_ln, pr_col, " " .. table.concat(tags, "  "), pr_w, nil)
        local tc = pr_col + 1
        for _, t in ipairs(tags) do
          push_hl(tag_hl(t), pr_ln, tc, tc + #t); tc = tc + #t + 2
        end
      else
        wpad(pr_ln, pr_col, " (no tags -- press t)", pr_w, "PhysNavMuted")
      end
    end

    -- Keybind cheatsheet pinned to bottom
    local keybinds = {
      { "Enter", "open + NeoTree" },
      { "p",     "open PDF"       },
      { "g",     "git push"       },
      { "l",     "git log"        },
      { "t",     "edit tags"      },
      { "n",     "new note"       },
      { "d",     "delete"         },
      { "r",     "rescan"         },
    }
    local kb_start = th - #keybinds
    for ki, kb in ipairs(keybinds) do
      local kln = kb_start + ki - 1
      if kln < 3 or kln > th - 1 then goto kbskip end
      wpad(kln, pr_col, pad(" " .. kb[1], 7) .. kb[2], pr_w, nil)
      push_hl("PhysNavKey",   kln, pr_col + 1, pr_col + 1 + #kb[1])
      push_hl("PhysNavMuted", kln, pr_col + 7, pr_col + pr_w)
      ::kbskip::
    end
  end

  -- -- Status bar (last line, filled background) --
  local mode_hl, mode_str
  if state.mode == "tags" then
    mode_hl  = "PhysNavStatusTags"
    mode_str = " TAGS "
  else
    mode_hl  = "PhysNavStatusNormal"
    mode_str = " NAV  "
  end

  -- Right side: active query / tag indicators
  local r_parts = {}
  if state.query ~= "" then
    table.insert(r_parts, '/"' .. trunc(state.query, 14) .. '"')
  end
  if #state.active_tags > 0 then
    local logic = state.tag_and and "AND" or "OR"
    table.insert(r_parts, logic .. ":" .. #state.active_tags)
  end
  local r_str = #r_parts > 0 and ("  " .. table.concat(r_parts, "  ")) or ""

  local keys_str
  if state.mode == "tags" then
    keys_str = "  j/k  Enter back  Space keep  a AND/OR  Esc cancel"
  else
    keys_str = "  Enter  /  T  n  d  g  l  t  r  ?  q"
  end

  write(th, 0, mode_str, mode_hl)
  -- Separator
  write(th, #mode_str, "|", "PhysNavStatusSep")
  -- Keys
  local keys_end = #mode_str + 1 + dw(keys_str)
  write(th, #mode_str + 1, keys_str, "PhysNavStatusFill")
  -- Right-aligned context info
  if #r_str > 0 then
    local r_col = tw - #r_str
    if r_col > keys_end + 2 then
      write(th, r_col, r_str, "PhysNavStatusQuery")
    end
  end
  -- Fill remaining status bar
  local fill_start = #mode_str + 1 + dw(keys_str) + 1
  if fill_start < tw then
    write(th, fill_start,
      string.rep(" ", tw - fill_start - math.max(0, #r_str)), "PhysNavStatusFill")
  end

  -- Flush
  api.nvim_buf_set_option(buf, "modifiable", true)
  api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_buf_set_option(buf, "modifiable", false)
  for _, h in ipairs(hls) do
    pcall(api.nvim_buf_add_highlight, buf, state.ns, h[1], h[2], h[3], h[4])
  end
  local sel_ln = list_top + (state.selected - 1) - scroll
  if sel_ln >= list_top and sel_ln <= list_bottom then
    pcall(api.nvim_win_set_cursor, state.win, { sel_ln, 0 })
  end
end

-- -----------------------------------------------------------------
--  Refresh
-- -----------------------------------------------------------------
local function refresh()
  if not is_open() then return end
  state.filtered = proj_mod.filter(
    state.projects, state.query, state.active_tags, state.cfg.sort_by, state.tag_and)
  state.selected = math.min(state.selected, math.max(1, #state.filtered))
  M._render()
end

-- -----------------------------------------------------------------
--  Tag filter helpers
-- -----------------------------------------------------------------
local function toggle_tag_filter(tag)
  local idx = nil
  for i, t in ipairs(state.active_tags) do if t == tag then idx = i; break end end
  if idx then table.remove(state.active_tags, idx)
  else        table.insert(state.active_tags, tag) end
  state.selected = 1
end

-- -----------------------------------------------------------------
--  NeoTree / netrw
-- -----------------------------------------------------------------
local function open_neotree(path)
  local ok = pcall(vim.cmd, "Neotree dir=" .. vim.fn.fnameescape(path) .. " reveal")
  if not ok then pcall(vim.cmd, "Explore " .. vim.fn.fnameescape(path)) end
end

-- -----------------------------------------------------------------
--  Refocus after git float closes
-- -----------------------------------------------------------------
local function refocus_physnav()
  if is_open() then pcall(api.nvim_set_current_win, state.win) end
end

-- -----------------------------------------------------------------
--  Actions
-- -----------------------------------------------------------------
local function open_project()
  local p = state.filtered[state.selected]
  if not p then return end
  local target = p.path .. "/" .. (p.main or "main.tex")
  local path   = p.path
  local cmd    = state.cfg.open_cmd
  proj_mod.touch(state.cfg.data_file, state.projects, p.name)
  M.close()
  vim.cmd(cmd .. " " .. vim.fn.fnameescape(target))
  pcall(vim.cmd, "cd " .. vim.fn.fnameescape(path))
  vim.schedule(function() open_neotree(path) end)
end

local function open_pdf()
  local p = state.filtered[state.selected]
  if not p then return end
  local pdf = p.path .. "/main.pdf"
  if vim.fn.filereadable(pdf) == 0 then
    vim.notify("PhysNav: no PDF for " .. p.name, vim.log.levels.WARN); return
  end
  for _, o in ipairs({ "xdg-open","open","zathura","evince","okular" }) do
    if vim.fn.executable(o) == 1 then
      vim.fn.jobstart({ o, pdf }, { detach = true }); return
    end
  end
  vim.notify("PhysNav: no PDF viewer found", vim.log.levels.WARN)
end

local function do_git_push()
  local p = state.filtered[state.selected]
  if not p then return end
  git_mod.push_project(p, nil, refocus_physnav)
end

local function do_git_log()
  local p = state.filtered[state.selected]
  if not p then return end
  git_mod.show_log(p, refocus_physnav)
end

local function do_search()
  vim.ui.input({ prompt = "Search: ", default = state.query }, function(input)
    if input ~= nil then state.query = vim.trim(input); state.selected = 1 end
    if is_open() then pcall(api.nvim_set_current_win, state.win); refresh() end
  end)
end

local function do_tag_edit()
  local p = state.filtered[state.selected]
  if not p then return end
  vim.ui.input({
    prompt  = 'Tags for "' .. p.name .. '" (comma-separated): ',
    default = table.concat(p.tags or {}, ", "),
  }, function(input)
    if input ~= nil then
      local new_tags = {}
      for tag in input:gmatch("[^,]+") do
        local t = vim.trim(tag); if t ~= "" then table.insert(new_tags, t) end
      end
      proj_mod.update_tags(state.cfg.data_file, state.projects, p.name, new_tags)
      state.all_tags = proj_mod.all_tags(state.projects)
      reset_tag_colors()
    end
    if is_open() then pcall(api.nvim_set_current_win, state.win); refresh() end
  end)
end

-- -----------------------------------------------------------------
--  New note wizard  (flat sequential, avoids deep nesting)
-- -----------------------------------------------------------------
local function do_new_note()
  local cfg = state.cfg

  -- Collect all inputs first via sequential coroutine-style callbacks,
  -- then clone in one shot.
  local category, name, new_tags

  local function step3_clone()
    local dest = cfg.root .. "/" .. category .. "/" .. name
    if vim.fn.isdirectory(dest) == 1 then
      vim.notify("PhysNav: already exists: " .. dest, vim.log.levels.ERROR)
      if is_open() then pcall(api.nvim_set_current_win, state.win) end; return
    end
    vim.notify("PhysNav: cloning template ...", vim.log.levels.INFO)
    vim.fn.jobstart({ "git", "clone", "--depth=1", cfg.typst_template, dest }, {
      on_exit = function(_, code)
        vim.schedule(function()
          if code ~= 0 then
            vim.notify("PhysNav: clone failed (code " .. code .. ")", vim.log.levels.ERROR)
            if is_open() then pcall(api.nvim_set_current_win, state.win) end; return
          end
          vim.fn.jobstart({ "rm", "-rf", dest .. "/.git" }, {
            on_exit = function(_, _)
              vim.schedule(function()
                local new_proj = {
                  name = name, category = category, path = dest,
                  type = "typst", main = "main.typ",
                  lec_count = 0, has_pdf = false,
                  tags = new_tags, last_opened = os.time(),
                }
                proj_mod.add_project(cfg.data_file, state.projects, new_proj)
                state.all_tags = proj_mod.all_tags(state.projects)
                reset_tag_colors()
                vim.notify("PhysNav: created " .. category .. "/" .. name, vim.log.levels.INFO)
                refresh()
                for i, p in ipairs(state.filtered) do
                  if p.name == name then state.selected = i; break end
                end
                refresh()
                M.close()
                vim.cmd(cfg.open_cmd .. " " .. vim.fn.fnameescape(dest .. "/main.typ"))
                pcall(vim.cmd, "cd " .. vim.fn.fnameescape(dest))
                vim.schedule(function() open_neotree(dest) end)
              end)
            end,
          })
        end)
      end,
    })
  end

  local function step2_name()
    vim.ui.input({ prompt = "Project name: " }, function(input)
      if not input or vim.trim(input) == "" then
        if is_open() then pcall(api.nvim_set_current_win, state.win) end; return
      end
      name = vim.trim(input):gsub("%s+", "_")
      vim.ui.input({ prompt = "Tags (comma-separated, blank ok): " }, function(tag_input)
        new_tags = {}
        if tag_input and vim.trim(tag_input) ~= "" then
          for tag in tag_input:gmatch("[^,]+") do
            local t = vim.trim(tag); if t ~= "" then table.insert(new_tags, t) end
          end
        end
        vim.schedule(step3_clone)
      end)
    end)
  end

  vim.ui.select(cfg.categories, { prompt = "Category:" }, function(sel)
    if not sel then
      if is_open() then pcall(api.nvim_set_current_win, state.win) end; return
    end
    category = sel
    vim.schedule(step2_name)
  end)
end

-- -----------------------------------------------------------------
--  Delete project
-- -----------------------------------------------------------------
local function detect_trash_cmd()
  for _, cmd in ipairs({ "trash", "trash-put", "gio trash" }) do
    local bin = cmd:match("^(%S+)")
    if vim.fn.executable(bin) == 1 then return cmd end
  end
  return nil
end

local function do_delete_project()
  local p = state.filtered[state.selected]
  if not p then return end
  local trash_cmd = state.cfg.trash_cmd or detect_trash_cmd()
  local method    = trash_cmd and "trash" or "PERMANENTLY DELETE"
  vim.ui.input({
    prompt = string.format('[%s] Confirm name to delete "%s": ', method, p.name),
  }, function(input)
    if input == nil or vim.trim(input) ~= p.name then
      vim.notify("PhysNav: delete cancelled", vim.log.levels.INFO)
      if is_open() then pcall(api.nvim_set_current_win, state.win) end; return
    end
    local path = p.path
    local name = p.name
    local function after(ok)
      vim.schedule(function()
        if ok then
          proj_mod.remove_project(state.cfg.data_file, state.projects, name)
          state.all_tags = proj_mod.all_tags(state.projects)
          reset_tag_colors()
          state.selected = math.max(1, state.selected - 1)
          vim.notify("PhysNav: deleted " .. name, vim.log.levels.INFO)
          if is_open() then pcall(api.nvim_set_current_win, state.win); refresh() end
        else
          vim.notify("PhysNav: delete failed: " .. name, vim.log.levels.ERROR)
          if is_open() then pcall(api.nvim_set_current_win, state.win) end
        end
      end)
    end
    if trash_cmd then
      local parts = vim.split(trash_cmd, " ")
      table.insert(parts, path)
      vim.fn.jobstart(parts, { on_exit = function(_, c) after(c == 0) end })
    else
      vim.fn.jobstart({ "rm", "-rf", path }, { on_exit = function(_, c) after(c == 0) end })
    end
  end)
end

-- -----------------------------------------------------------------
--  Help
-- -----------------------------------------------------------------
local function show_help()
  vim.notify(table.concat({
    "PhysNav  keybindings",
    string.rep("-", 48),
    "  j / k / Down / Up   navigate list",
    "  gg / G              jump to first / last",
    "  Enter               open project main file + NeoTree",
    "  p                   open compiled PDF",
    "  g                   git push (PhysNav stays open)",
    "  l                   git log  (PhysNav stays open)",
    "  t                   edit tags for project",
    "  n                   new note from typst template",
    "  d                   delete project (trash / rm -rf)",
    "  /                   fuzzy search",
    "  T                   toggle tag-browser mode",
    "  <C-c>               clear search + tag filters",
    "  r                   force rescan from disk",
    "  q / Esc             quit (or clear filters first)",
    "  ?                   this help",
    "",
    "  Tag-browser mode (T):",
    "    j/k               move cursor",
    "    Enter             toggle tag + return to list",
    "    Space             toggle tag (stay in tag mode)",
    "    a                 toggle AND / OR filter logic",
    "    Esc               exit, keep filters unchanged",
  }, "\n"), vim.log.levels.INFO, { title = "PhysNav" })
end

-- -----------------------------------------------------------------
--  Keymaps
-- -----------------------------------------------------------------
local function setup_keymaps(buf)
  local opts = { buffer = buf, noremap = true, silent = true, nowait = true }
  local function nmap(key, fn) vim.keymap.set("n", key, fn, opts) end

  -- Navigation
  nmap("j", function()
    if state.mode == "tags" then
      state.tag_cursor = math.min(state.tag_cursor + 1, #state.all_tags)
    else
      state.selected = math.min(state.selected + 1, math.max(1, #state.filtered))
    end
    refresh()
  end)
  nmap("k", function()
    if state.mode == "tags" then
      state.tag_cursor = math.max(state.tag_cursor - 1, 1)
    else
      state.selected = math.max(state.selected - 1, 1)
    end
    refresh()
  end)
  nmap("<Down>", function()
    state.selected = math.min(state.selected + 1, math.max(1, #state.filtered)); refresh()
  end)
  nmap("<Up>", function()
    state.selected = math.max(state.selected - 1, 1); refresh()
  end)
  nmap("gg", function() state.selected = 1; refresh() end)
  nmap("G",  function() state.selected = math.max(1, #state.filtered); refresh() end)

  -- Enter
  nmap("<CR>", function()
    if state.mode == "tags" then
      local tag = state.all_tags[state.tag_cursor]
      if tag then toggle_tag_filter(tag); state.mode = "normal"; refresh() end
    else
      open_project()
    end
  end)
  nmap("<2-LeftMouse>", open_project)

  -- Tag browser
  nmap("T", function()
    state.mode = (state.mode == "tags") and "normal" or "tags"
    if state.mode == "tags" then state.tag_cursor = 1 end
    refresh()
  end)
  nmap("<Space>", function()
    if state.mode == "tags" then
      local tag = state.all_tags[state.tag_cursor]
      if tag then toggle_tag_filter(tag); refresh() end
    end
  end)
  -- Toggle AND/OR logic
  nmap("a", function()
    if state.mode == "tags" or #state.active_tags > 0 then
      state.tag_and = not state.tag_and
      state.selected = 1
      refresh()
    end
  end)

  -- Esc: exit mode / clear filters / quit
  nmap("<Esc>", function()
    if state.mode == "tags" then
      state.mode = "normal"; refresh()
    elseif state.query ~= "" or #state.active_tags > 0 then
      state.mode = "normal"; state.query = ""; state.active_tags = {}
      state.tag_and = false; refresh()
    else
      M.close()
    end
  end)
  nmap("<C-c>", function()
    state.query = ""; state.active_tags = {}
    state.mode  = "normal"; state.tag_and = false; refresh()
  end)

  -- Actions
  nmap("/", function() vim.schedule(do_search) end)
  nmap("p", open_pdf)
  nmap("g", function() vim.schedule(do_git_push) end)
  nmap("l", function() vim.schedule(do_git_log) end)
  nmap("t", function() vim.schedule(do_tag_edit) end)
  nmap("n", function() vim.schedule(do_new_note) end)
  nmap("d", function() vim.schedule(do_delete_project) end)
  nmap("r", function()
    state.projects   = proj_mod.scan_and_save()
    state.all_tags   = proj_mod.all_tags(state.projects)
    state.git_status = {}
    reset_tag_colors()
    refresh()
    load_git_statuses()
    vim.notify("PhysNav: rescanned", vim.log.levels.INFO)
  end)
  nmap("?", show_help)
  nmap("q", function() M.close() end)
end

-- -----------------------------------------------------------------
--  Open / Close
-- -----------------------------------------------------------------
function M.open(cfg)
  if is_open() then M.close(); return end

  hl_mod.setup()

  state.cfg         = cfg
  state.query       = ""
  state.active_tags = {}
  state.mode        = "normal"
  state.tag_and     = false
  state.selected    = 1
  state.tag_cursor  = 1
  state.git_status  = {}
  state.ns          = api.nvim_create_namespace("physnav")
  reset_tag_colors()

  state.projects = proj_mod.load(cfg.data_file, cfg.root, cfg.categories, false)
  state.all_tags = proj_mod.all_tags(state.projects)
  state.filtered = proj_mod.filter(state.projects, "", {}, cfg.sort_by, false)

  local buf = api.nvim_create_buf(false, true)
  state.buf = buf
  api.nvim_buf_set_option(buf, "buftype",    "nofile")
  api.nvim_buf_set_option(buf, "bufhidden",  "wipe")
  api.nvim_buf_set_option(buf, "swapfile",   false)
  api.nvim_buf_set_option(buf, "filetype",   "physnav")
  api.nvim_buf_set_option(buf, "modifiable", false)
  api.nvim_buf_set_var(buf, "physnav_main", true)

  state.layout = calc_layout(cfg)
  local l = state.layout

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    row = l.row, col = l.col, width = l.tw, height = l.th,
    style = "minimal", border = "single",
    title = " PhysNav ", title_pos = "center",
  })
  state.win = win

  api.nvim_win_set_option(win, "cursorline",     false)
  api.nvim_win_set_option(win, "number",         false)
  api.nvim_win_set_option(win, "relativenumber", false)
  api.nvim_win_set_option(win, "signcolumn",     "no")
  api.nvim_win_set_option(win, "wrap",           false)
  api.nvim_win_set_option(win, "winhighlight",
    "Normal:Normal,FloatBorder:PhysNavBorder,FloatTitle:PhysNavHeaderTitle")

  setup_keymaps(buf)

  -- WinLeave: close unless destination is a prompt or physnav child float
  api.nvim_create_autocmd("WinLeave", {
    buffer   = buf,
    callback = function()
      vim.schedule(function()
        if not is_open() then return end
        local cur = api.nvim_get_current_win()
        if cur == state.win then return end
        local cur_buf = api.nvim_win_get_buf(cur)
        local ok_bt, bt = pcall(api.nvim_buf_get_option, cur_buf, "buftype")
        if ok_bt and bt == "prompt" then return end
        local ok_ch, is_child = pcall(api.nvim_buf_get_var, cur_buf, "physnav_child")
        if ok_ch and is_child then return end
        M.close()
      end)
    end,
  })

  api.nvim_create_autocmd("VimResized", {
    buffer   = buf,
    callback = function()
      if not is_open() then return end
      state.layout = calc_layout(state.cfg)
      local nl = state.layout
      api.nvim_win_set_config(state.win, {
        relative = "editor", row = nl.row, col = nl.col,
        width = nl.tw, height = nl.th,
      })
      refresh()
    end,
  })

  refresh()
  vim.schedule(load_git_statuses)
end

function M.close()
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_win_close(state.win, true)
  end
  if state.buf and api.nvim_buf_is_valid(state.buf) then
    pcall(api.nvim_buf_delete, state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
end

return M
