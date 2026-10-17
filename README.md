# ownvim — my own Neovim build

🇷🇺 [Русская версия](README.ru.md)

Neovim without LazyVim: ~1200 lines of own code, ideas taken from LazyVim. Everything is set in one
JSON file, no Lua needed. Starts in 20 ms (the LazyVim build in `nvim/` takes 49).

```bash
ownvim            # own build (NVIM_APPNAME=ownvim nvim)
nvim              # still LazyVim for now
```

## Settings

- `defaults.jsonc` — every default with an explanation. Don't edit it.
- `settings.jsonc` — **only what you change** (`space f c` or `:Settings`). Delete a line — the default is back.

Save `settings.jsonc` — theme, options, keys and module settings **apply at once**.
Turning a module or plugin on/off takes `:restart`. A JSON error or a typo in a name is marked on
its line, and the editor keeps running on the previous settings.

```jsonc
{
  "theme": "rose-pine",                                  // or "auto" — the one picked with alt-s
  "options": { "relativenumber": true },                 // any option from :help options
  "modules": {
    "smear_cursor": true,                                // turn a module on
    "modes": { "auto_normal_ms": 0 },                    // module settings
  },
  "keys": {
    "n <leader>z": ":Lazy",                              // a command
    "n <leader>ff": "files.git",                         // an action (list: space s k)
    "i jk": false,                                       // remove a key
  },
  "plugins": {
    "folke/zen-mode.nvim": { "cmd": "ZenMode", "opts": {} }, // any plugin, lazy.nvim style
    "folke/flash.nvim": false,                           // drop a module's plugin
  },
}
```

Comments and trailing commas are fine, as in Zed's and VS Code's settings.json.

## Modules

| module | what's inside |
|---|---|
| `basics` | yank highlight, cursor back where it was, `q` closes helper windows, a new file's folder is created |
| `ui` | start screen, notifications, a "bubbles" status line with the mode in Russian, which-key, indent guides |
| `picker` | find files, text, commands, file tree (Snacks); `alt-c` in a picker — project ↔ launch folder |
| `treesitter` | highlighting, indent, folds; languages listed in settings, missing ones install themselves |
| `editing` | pairs, text objects `af`/`ic`/`ao`, surround `gsa`/`gsd`/`gsr`, `s` to jump, TODO |
| `themes` | tokyonight, rose-pine in the terminal's colors and seven more — `alt-s` with a preview |
| `modes` | mode shown by cursor and line color, leaves insert after a pause |
| `autosave` | files write themselves, outside changes are picked up |
| `russian` | commands in the Russian layout (`о` = `j`, `вв` = `dd`), alt keys work in it too |
| `scrollbar` | a scrollbar with marks for errors, git and search |
| `smear_cursor` | smear cursor (off) |

Module code is `lua/own/modules/<name>.lua`; parts shared with the LazyVim build (themes, modes,
cheat sheet) come from `nvim/lua/dotfiles/` without copies.

## Next

Stage 1 of 4 — the base. Next: Go as an IDE (gopls, completion, formatting, tests, debugger),
git, moving my own modules over (endpoints, `.http`, ▶, background tests, Claude). Once it
catches up, `ownvim` becomes `nvim`.
