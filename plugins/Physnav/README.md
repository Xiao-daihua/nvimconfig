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

## Keybinds

| Key          | Action                                  |
|--------------|-----------------------------------------|
| `j` / `k`   | move down / up                          |
| `Enter`      | open project main file                  |
| `p`          | open compiled PDF                       |
| `c`          | compile in terminal split               |
| `t`          | edit tags for selected project          |
| `/`          | open search prompt                      |
| `T`          | toggle tag-browser mode                 |
| `Space`      | toggle tag filter (in tag-browser mode) |
| `<C-c>`      | clear search + all tag filters          |
| `r`          | rescan projects                         |
| `q` / `Esc` | quit (or clear filters first)           |
| `?`          | show help                               |

**Search** (`/`): a `vim.ui.input` prompt appears. Type your query, press Enter
to apply, or leave blank to clear. The filter is shown in the header.

**Tag browser** (`T`): `j`/`k` move the cursor, `Enter` or `Space` toggle that
tag as an active filter.

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
