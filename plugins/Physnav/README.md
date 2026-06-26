# physnav.nvim

> A terminal-native project browser for LaTeX and Typst physics notes.

## What changed in this rewrite

- **Search fixed** — now uses `vim.ui.input` instead of the broken `vim.on_key` approach; no more errors when typing in search
- **No auto-tagging** — tags start empty and are 100% user-managed; no more surprise tags added on scan
- **UI cleanup** — all symbols are plain ASCII (`[tex]`, `[typ]`, `+`/`-`, `>`); no more garbled unicode in terminals that don't support wide glyphs
- **Border style** — switched to `single` border (plain ASCII `|`, `-`, `+`); more terminal-native
- **Tag persistence on rescan** — rescanning preserves your existing tags (merges by project name)
- **WinLeave auto-close** — smarter: won't close while `vim.ui.input` is active

---

## Features

- **Tag-based filtering** — organise projects with custom tags; sidebar shows all tags with counts
- **Fuzzy search** — filter by project name, category, and tags (`/` to open search prompt)
- **Project preview** — right panel shows type, main file, lecture count, PDF status, tags
- **PDF viewer** — open compiled PDFs with your system viewer
- **Compile** — run `latexmk` or `typst compile` in a terminal split
- **Persistent tags** — tag edits saved to JSON in `~/.local/share/nvim/`

---

## Installation (lazy.nvim)

```lua
-- ~/.config/nvim/lua/plugins/physnav.lua
return {
  dir = vim.fn.expand("~/.config/nvim/plugins/physnav"),
  lazy = false,
  config = function()
    require("physnav").setup({
      root          = vim.fn.expand("~/Phys"),
      open_cmd      = "edit",       -- or "tabedit", "vsplit"
      width         = 0.92,
      height        = 0.88,
      sidebar_width = 22,
      preview_width = 30,
    })
  end,
  keys = {
    { "<leader>P",  "<cmd>PhysNav<cr>",     desc = "PhysNav: open project browser" },
    { "<leader>ps", "<cmd>PhysNavScan<cr>", desc = "PhysNav: rescan projects" },
  },
}
```

---

## Quickstart (no lazy)

```lua
vim.opt.rtp:prepend(vim.fn.expand("~/.config/nvim/plugins/physnav"))
require("physnav").setup({ root = vim.fn.expand("~/Phys") })
vim.keymap.set("n", "<leader>P", "<cmd>PhysNav<cr>", { desc = "PhysNav" })
```

---

## Expected directory layout

```
~/Phys/
├── EPFL_lecture/
│   ├── QFT_1_course/          <- LaTeX (has main.tex)
│   │   ├── main.tex
│   │   ├── lec1.tex ... lec14.tex
│   │   └── main.pdf
│   └── GR_2_course/           <- Typst (has main.typ)
│       ├── main.typ
│       └── doc/
│           └── lec1.typ ...
└── Notes/
    └── Minimal_CFT/
        └── main.tex
```

PhysNav scans `root/{category}/{project}/`.
Categories scanned: `EPFL_lecture`, `Notes`.

---

## Layout

Four panes:

```
╭─ search ─────────────────────────────────────────────╮
│  /  type to filter…                                  │
╰──────────────────────────────────────────────────────╯
╭─ tags ──╮ ╭─ notes 9/24 ─────────────────────────────╮
│ ● All   │ │   ▾ WIP   (3)                            │
│ ○ qft   │ │       QFT_renorm                         │
│ ○ cft   │ │   ▸ IDEA  (5)                            │
│ …       │ │   ▸ SHELF (16)                           │
╰─────────╯ ╰──────────────────────────────────────────╯
╭─ keys ───────────────────────────────────────────────╮
│  j/k move · l open · h fold · w/i/x status · / search │
╰──────────────────────────────────────────────────────╯
```

- **search** (top) — press `/` to focus it, type to filter live, `Enter`/`Esc` back to the list.
- **tags** (left) — press `t` (or `Tab`) to enter; `j`/`k` move, `Enter`/`Space` toggle a tag, `a` switches AND/OR, `t`/`q`/`Esc` back to the list. Selecting tags filters the notes shown.
- **notes** (main) — the status board; the only pane you navigate with hjkl.
- **keys** (bottom) — a live cheat-sheet that changes with the active pane.

## How it's organised

The notes pane groups notes into three **status buckets**:

| Bucket  | Meaning                                            |
|---------|----------------------------------------------------|
| `WIP`   | actively writing — **open by default**             |
| `IDEA`  | opened-but-not-started; **new notes land here**     |
| `SHELF` | everything else — finished or set aside            |

`IDEA` and `SHELF` start folded. There is no "done": a note is on your mind
(`WIP`), waiting (`IDEA`), or off your plate (`SHELF`). Status is saved in the
JSON data file and survives rescans.

## Navigation (in the notes pane)

| Key        | On a bucket header   | On a note         |
|------------|----------------------|-------------------|
| `j` / `k` | move up / down (headers + visible notes; blanks skipped) ||
| `l`        | unfold the bucket    | open the note     |
| `h`        | fold the bucket      | fold the note's bucket |
| `Enter`    | toggle fold          | open the note     |
| `gg` / `G`| first / last item    | first / last item |

## Keybinds

| Key     | Action                                       |
|---------|----------------------------------------------|
| `w`/`i`/`x` | move note → WIP / IDEA / SHELF            |
| `K`     | detail popup for the selected note           |
| `p`     | open compiled PDF                            |
| `c`     | compile in a terminal split                  |
| `g` / `L` | git push / log                             |
| `e`     | edit tags for the selected note              |
| `n`     | new note from template (starts in IDEA)      |
| `d`     | delete project                               |
| `/`     | focus the search box                         |
| `t` / `Tab` | jump to the tags pane                    |
| `r`     | rescan from disk                             |
| `Esc`   | clear an active filter, else close           |
| `q`     | close      ·   `?`  help                     |

---

## Commands

| Command         | Description                              |
|-----------------|------------------------------------------|
| `:PhysNav`      | Open the project browser                 |
| `:PhysNavScan`  | Rescan projects (preserves your tags)    |

---

## Configuration

```lua
require("physnav").setup({
  root          = "~/Phys",
  data_file     = vim.fn.stdpath("data") .. "/physnav_projects.json",
  open_cmd      = "edit",    -- edit | tabedit | vsplit
  width         = 0.92,
  height        = 0.88,
  preview_width = 30,
  sidebar_width = 22,
})
```

---

## How tags work

Tags are **empty by default**. PhysNav no longer infers tags from project names.

Press `t` on any project to set tags (comma-separated). Tags are saved to the
JSON data file and survive rescans (merged by project name).

Example:
```
Tags for QFT_1_course (comma-separated): QFT, EPFL, course
```

---

## Troubleshooting

**No projects shown**
- Check `root` in your config.
- Run `:PhysNavScan`.
- Projects need `.tex` or `.typ` files at the top level (or in `doc/` for Typst).

**Search prompt doesn't appear**
- This uses `vim.ui.input`. Make sure nothing overrides it unexpectedly (e.g. a
  plugin like `noice.nvim` — it should still work fine, but the prompt style
  may differ).

**PDF opener not working**
- PhysNav tries: `xdg-open`, `open`, `zathura`, `evince`, `okular`.
- Ensure at least one is in your `$PATH`.
