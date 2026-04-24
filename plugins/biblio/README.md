# biblio.nvim

A Neovim plugin for managing a Jekyll-based academic blog with `_database/` (topics) and `_papers/` (references) collections. Built specifically for the layout used in [Xiao-daihua.github.io](https://github.com/Xiao-daihua/Xiao-daihua.github.io), but configurable.

## What it does

- **Floating dashboard.** `:Biblio` opens a single composite floating UI — search bar at the top, three result panes (Tags | Topics | Papers), permanent hints at the bottom. No tabs, no buffer switching. Close it and your workspace is untouched.
- **Live search across everything.** Press `/`, type, and tags / topics / papers filter together in real time. `<C-u>` clears. `<Esc>` or `<CR>` commits and jumps into the results.
- **Paste-BibTeX paper creation with preview.** Press `np`, paste your BibTeX, and the plugin parses it, enriches it from the arXiv and Crossref APIs, and shows you the generated YAML in a preview float. Accept, edit, or discard — nothing is written until you confirm.
- **One-key topic creation.** `nt` prompts for a title, then a multi-select over existing tags (with the option to add new ones), then writes a stub `_database/NNNNslug.md`.
- **Inline paper references from the editor.** While editing a topic file, press `<C-p>` (normal or insert mode) to fuzzy-search all your papers and insert `[Title](/papers/slug/)` at the cursor.
- **Auto neo-tree.** When the dashboard opens, neo-tree reveals your blog root in the side panel so you can still browse the repo visually.
- **Tag-driven navigation.** Cursor on a tag filters the topics pane. Cursor on a topic filters the papers pane to show only papers it links to.

## Install

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
    dir = vim.fn.expand("~/.config/nvim/plugins/biblio"),
    lazy = false,
    config = function()
        require("biblio").setup({
            blog_root = vim.fn.expand("~/path/to/Xiao-daihua.github.io"),
        })
    end,
    keys = {
        { "<leader>B", "<cmd>Biblio<cr>", desc = "Biblio: open dashboard" },
    },
}
```

### Manual

Copy the plugin folder anywhere on your `runtimepath`, then add `require("biblio").setup({ blog_root = "…" })` to your `init.lua`.

## Requirements

- Neovim **0.9+** (uses `vim.keymap.set`, `vim.ui.select`; `vim.system` is used when available, `vim.fn.system` as fallback).
- `curl` on `$PATH` (for arXiv and Crossref fetches).
- [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) — **optional**. If installed, biblio auto-reveals your blog root on open. No hard dependency.
- No Lua dependencies. No `plenary.nvim`, no `telescope`.

## Usage

### Commands

| Command | What it does |
|---|---|
| `:Biblio` or `:Biblio open` | Open the dashboard |
| `:Biblio close` | Close the dashboard |
| `:Biblio paper` | Open the new-paper prompt directly |
| `:Biblio topic` | Open the new-topic prompt directly |
| `:Biblio ref` | Insert a paper reference at cursor |
| `:Biblio refresh` | Rescan `_database/` and `_papers/` |
| `:Biblio serve` | Start `bundle exec jekyll serve` in the background |
| `:Biblio serve_stop` | Stop the running jekyll server |
| `:Biblio serve_status` | Is jekyll running? |
| `:Biblio preview` | Open `http://127.0.0.1:4000/` in the default browser |
| `:Biblio commit` | Commit UI: float with `git status --short` and a message editor |
| `:Biblio push` | `git push` the current branch |
| `:Biblio sync` | Commit and push in one go |

### Dashboard keymaps

All keymaps are buffer-local — zero global pollution.

| Key | Action |
|---|---|
| `np` | New paper (paste BibTeX, preview, accept/discard) |
| `nt` | New topic |
| `/` | Focus the search bar (starts in insert) |
| `j` in search normal | Jump from search bar into topics pane |
| `<Esc>` in search insert | Drop to normal mode (search bar stays open) |
| `<CR>` in search | Commit query, jump to results pane |
| `<C-u>` in search insert | Clear query |
| `q` in search normal | Close dashboard |
| `t` / `T` / `P` | Focus Tags / Topics / Papers pane |
| `h` / `l` | Move one pane left / right |
| `j` / `k` | Down / up within a pane |
| `<CR>` in results pane | Open selected item for editing |
| `R` on a tag | Rename tag across all topics |
| `D` on a tag | Delete tag from all topics (confirmed) |
| `m` on a topic | Mark topic for batch operations (shows `✓`) |
| `M` on topics pane | Unmark all |
| `a` on topics pane | Apply tag(s) to marked topics (or cursor topic) |
| `d` | Delete selected item (with confirmation) |
| `s` | Toggle jekyll serve (start if stopped, stop if running) |
| `S` | Open preview in browser |
| `gc` | Commit changes (opens commit UI) |
| `gp` | Push current branch |
| `gs` | Commit + push (sync) |
| `r` | Refresh |
| `?` | Help (full keybinding reference) |
| `q` | Close dashboard |

**Mode convention (all input floats):** `<Esc>` always drops you from insert to normal mode — it never closes the UI. Use `q` in normal mode to close / cancel.

### Managing tags

Your tags accumulate fast and sometimes you want to clean up. biblio can edit tags across all your topic files in one shot, surgically (the markdown body is untouched).

**Rename a tag** — put the cursor on a tag in the Tags pane and press `R`. Enter the new name. Every topic that had the old tag now has the new one (duplicates are de-duped if both existed).

**Delete a tag** — `D` on a tag prompts for confirmation, then removes that tag from every topic that had it.

**Tag multiple topics at once** — on the Topics pane, press `m` on each topic you want to tag (a `✓` appears next to its title). Press `a` to open the multi-select tag picker — existing tags plus an option to create a new one. All marked topics get all selected tags. `M` on the Topics pane clears the selection.

You can also press `a` without marking anything; it then applies to just the topic under the cursor.



Press `s` on the dashboard to **toggle** `bundle exec jekyll serve` — first press starts it in the background, next press stops it. The hints bar at the bottom of the dashboard shows `▶ s serve` when idle, `■ s serve` when running.

The job runs under `vim.fn.jobstart` so neovim stays responsive. Output is silent unless the process fails, in which case the last few stderr lines surface via `vim.notify`.

- `:Biblio serve_status` — is it running?
- `:Biblio serve_stop` — stop it explicitly (same as pressing `s` again).
- `:Biblio preview` (or `S` on the dashboard) — open `http://127.0.0.1:4000/` in your OS default browser (tries `xdg-open`, `open`, `wslview`).

Requires `bundle` on your PATH. Doesn't install or update gems — run `bundle install` manually the first time.

### Git commit and push

Press `gc` on the dashboard, or `:Biblio commit`, to open the commit UI:

- Top of the float shows current branch, repo path, and `git status --short`
- Below the `▶` marker is an editable message area (starts in insert mode)
- `<CR>` or `<C-s>` — commit. You'll be asked whether to push.
- `p` in normal mode — commit and push without asking
- `q` in normal mode — cancel
- `<Esc>` in insert — drop to normal (does not cancel)

The commit always stages everything under `blog_root` with `git add -A`. Never amends, never force-pushes, never touches other branches. If your branch has no upstream, push fails with a clear message telling you to run `git push -u origin <branch>` once manually.

Alternative entrypoints:
- `gp` / `:Biblio push` — just push (no commit)
- `gs` / `:Biblio sync` — commit + push in one go (skips the push prompt)

### In the editor: inserting paper references

While editing any `.md` file in `_database/`, press `<C-p>` (or run `:Biblio ref` from anywhere) to open the paper picker:

- Type to live-filter by title, author, year, journal, arXiv id, or DOI
- `<Down>` / `<Up>` or `<C-n>` / `<C-p>` navigate the result list
- `<CR>` inserts `[Title](/papers/slug/)` at your cursor
- `<Esc>` cancels and restores cursor + insert mode

### Adding a paper

1. Press `np` on the dashboard (or `:Biblio paper` anywhere).
2. Paste BibTeX. `<Esc>` drops to normal mode; from normal:
   - `<CR>` or `<C-s>` — parse and fetch
   - `q` — cancel
3. A preview float shows the generated YAML. Choose:
   - `y` / `<CR>` — save, close preview
   - `e` — save and open the file for editing
   - `d` / `<Esc>` — discard; nothing is written

The plugin parses the entry, fetches arXiv abstract + primary category if there's an `eprint`, fetches Crossref metadata if there's a `doi`, merges everything, and generates a filename like `YYYY-firstauthor.md`. Collisions become `YYYY-firstauthor2.md`, `YYYY-firstauthor3.md`.

**Year resolution.** The filename year is resolved in this order: arXiv's `<published>` date → Crossref's issued date → BibTeX `year` field → year-shaped digits in the BibTeX citation key (e.g. `Collier:2023fwi` → `2023`) → `0000` only as a true last resort. Network failures never block — you get whatever data was available.

### Adding a topic

1. Press `nt` on the dashboard (or `:Biblio topic`).
2. Enter a title.
3. A multi-select picker shows your existing tags. `<Tab>` or `<Space>` toggles. Press `n` to add a new tag. `<CR>` submits.
4. A new `_database/NNNNslug.md` is created (with `NNNN` auto-incremented) and opened.

## Configuration

Defaults — override any subset in `setup()`:

```lua
require("biblio").setup({
  blog_root          = nil,             -- resolved: explicit > cwd > git root ancestry
  database_dir       = "_database",
  papers_dir         = "_papers",
  paper_url_prefix   = "/papers/",      -- must match Jekyll's `papers` collection permalink
  open_cmd           = "edit",          -- or "tabedit", "vsplit", "split"
  arxiv_api          = "https://export.arxiv.org/api/query",
  crossref_api       = "https://api.crossref.org/works",
  request_timeout_ms = 10000,
  open_neotree       = true,            -- auto-reveal blog_root in neo-tree when opening

  keymaps = {
    new_paper     = "np",
    new_topic     = "nt",
    search        = "/",
    focus_tags    = "t",
    focus_topics  = "T",
    focus_papers  = "P",
    open_item     = "<CR>",
    delete_item   = "d",
    refresh       = "r",
    help          = "?",
    quit          = "q",
  },
})
```

## File conventions

**`_papers/YYYY-author.md`** — e.g. `2023-collier.md`; collisions become `2023-collier2.md`.

```yaml
---
layout: paper
title: "…"
authors:
  - Last, F.
  - Last, F.
year: 2023
status: published
journal: "…"
volume: "…"
pages: "…"
arxiv: "…"
arxiv_cat: "…"
doi: "…"
abstract: "…"
---
```

**`_database/NNNNslug.md`** — e.g. `0011modulartensorcategories.md`; `NNNN` is the max existing 4-digit prefix plus one.

```yaml
---
layout: topic
title: …
tags: [Tag A, Tag B]
---
```

## Design notes

- **Pure floating UI.** Five floating windows compose the dashboard. Closing any of them tears down the others. Your other buffers are never touched.
- **Opening files replaces the current buffer, not open a new tab.** The default `open_cmd` is `"edit"`, so selecting a paper / topic loads it into the current editor window (skipping neo-tree and other sidebars automatically). Your neo-tree stays put in the same tab instead of accumulating across new tabs. Set `open_cmd = "tabedit"` in setup if you prefer the old behavior.
- **Zero global keymaps.** Only `:Biblio` is registered at startup. The editor `<C-p>` is a buffer-local autocmd-attached map on files under `_database/`.
- **No lazy state.** Panes re-render from disk on `r`.
- **Graceful offline.** arXiv / Crossref being down never blocks paper creation — the preview just shows fewer fields.
- **Preview before write.** Paper generation is a two-step process so you can see exactly what will be written before it hits disk.

## Troubleshooting

- **"Blog root looks wrong"** — The plugin couldn't find `_database/` and `_papers/` under your configured `blog_root` or the current directory. Pass an absolute path to `setup()`.
- **arXiv / Crossref timeouts** — Bump `request_timeout_ms`, or check that `curl` is on your PATH.
- **`<C-p>` not active in a topic file** — Make sure the file is actually inside `<blog_root>/_database/`. The autocmd checks by path prefix.
- **Wrong tag on a topic** — Edit the file directly; `:Biblio refresh` picks it up.

## License

MIT.

