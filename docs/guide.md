# ownvim — guide

🇷🇺 [Русская версия](guide.ru.md) · [All keys (Russian)](keys.ru.md) · [README](../README.md)

ownvim is a terminal IDE for backend work: Go, C/C++, SQL, Docker, Python, Rust. Everything you see and how it behaves
is set in one file, `settings.jsonc`. No Lua needed.

## Install

Needs Neovim 0.12+, git, `tree-sitter`, `ripgrep` and a terminal with a Nerd Font (Ghostty has the glyphs built in).

```bash
brew install neovim tree-sitter ripgrep
git clone https://github.com/van1dalgrr-arch/ownvim ~/dev/ownvim
ln -s ~/dev/ownvim ~/.config/ownvim
echo 'alias ownvim="NVIM_APPNAME=ownvim nvim"' >> ~/.zshrc && exec zsh
ownvim
```

The first run installs plugins, parsers, language servers, formatters and linters (mason) by itself.
With [dotfiles](https://github.com/van1dalgrr-arch/dotfiles), `install.sh` does all of this.

## New to vim: 13 keys

| what | key |
|---|---|
| start typing / stop | `i` / `esc` or a quick `jk` (and by itself after a 5 s pause) |
| accept a suggestion | `tab` or `enter` (the grey ghost text too) |
| save | `cmd-s` (it also saves by itself) |
| find a file | `space space` or `cmd-p` |
| find text in the project | `space /` |
| file tree | `space e` |
| jump to a line | `enter` — lines get letters, press one |
| definition / usages | `gd` / `gr` |
| docs under the cursor | `K` |
| fix / code actions | `space c a` |
| my settings | `space f c` |
| all keys, searchable | `space s k` (or `space h`) |
| quit | `space q q` |

A second after `space`, a hint shows what can come next. Commands work in the Russian layout too.

## How settings work

- **`defaults.jsonc`** — every default, each line explained. Don't edit it: it's the reference (`space f C`).
- **`settings.jsonc`** — only what you change (`space f c` or `:Settings`). Delete a line — the default is back.

Layers merge by key: one line of a section is enough, the rest comes from the defaults.
**Hints like VS Code's settings.json**: completion of keys and values in `settings.jsonc`, `K` on a key shows its
description from `defaults.jsonc`, a wrong type or value is marked at once (the schema builds itself).
**Save — it applies**: theme, options, keys, colors, status line, tabs, icons, font, servers, formatters, linters at
once; turning modules and plugins on/off takes `:restart` (ownvim says so). **A mistake shows at once**: broken JSON or
a typo in a module, option, action or theme name is marked on its line, and the editor keeps the previous settings.

## Recipes

### Theme

```jsonc
"theme": "dev-night",
"theme": { "dark": "dev-night", "light": "dev-day" },   // follows the system
```

- `alt-s` — pick with a live preview; `enter` writes the choice to `settings.jsonc`.
- **Any VS Code theme** from Open VSX or the Marketplace, by extension id: `:ThemeInstall dracula-theme.theme-dracula`
  (or a link to a `.vsix`/`.json`, or a file path). It is converted into an ownvim theme (`themes/<name>.json`).
- **Your own**: `:ThemeNew mine sunset` — edit and save, the editor repaints. A theme is
  `{ "name", "include", "palette": {...}, "syntax": {...}, "groups": {...} }`; palette needs only `bg` and `fg`.
  `:ThemeEdit` opens the current theme, `space u i` shows the highlight group under the cursor.
- **Tweak any theme without touching it**, like `workbench.colorCustomizations`:
  `"colors": { "syntax": { "comment": { "italic": false } }, "[dracula-theme]": { "palette": { "bg": "#1e1e2e" } } }`.
- `"appearance": { "transparent": true }` — Ghostty's blur shows through.

### Icons

`"icons": { "theme": "backend" }` — default, mono, accent, backend, ascii. `:IconTheme` to pick,
`:IconThemeInstall <json url>`. Your own glyphs on top:
`"icons": { "overrides": { "extension": { "go": { "glyph": "", "color": "cyan" } } } }`.
VS Code icon themes are SVG, which a terminal can't show — so icon themes are Nerd Font glyphs.

### Font

`"font": { "family": "Geist Mono", "size": 15, "ligatures": false, "line_height": "10%" }` — written to Ghostty
(`~/.config/ghostty/ownvim.ghostty`, shared by all Ghostty windows). `:Font` — pick an installed one,
`:FontInstall Geist Mono` — install via brew / Nerd Fonts and switch.

### Status line, tabs, breadcrumbs, start screen

```jsonc
"statusline": {
  "style": "bubbles",   // arrows, slant, flat, plain
  "right": ["tests", "diff", "lsp", "k8s", "position", "time"],
  "custom": { "k8s": { "shell": "kubectl config current-context", "every_ms": 10000, "color": "pink" } }
},
"tabline": { "style": "bar", "show": "always" },
"breadcrumbs": { "separator": " / " },
"dashboard": { "header": ["MY EDITOR"], "sections": ["header", "buttons", "recent", "startup"] },
```

### Motion and VS Code details

`"animations": { "cursor": { "enabled": false }, "scroll": { "enabled": false } }`;
modules `brackets`, `sticky_scroll`, `minimap` (off by default), `scrollbar`.

### Keys

```jsonc
"keys": {
  "n <leader>z": ":Lazy",             // a command
  "n <D-b>": "explorer",              // an action (list: space s k)
  "i jk": false,                      // remove
  "n <leader>y": { "do": "\"+y", "desc": "Yank to the clipboard" },
},
```

### A language

`"lsp": { "servers": { "zls": true } }, "format": { "languages": { "zig": ["zigfmt"] } }` — the parser, server and
tools install themselves on the first file (`"tools": { "install": "system" }` — PATH only).

### Tasks and plugins

`"tasks": { "list": [{ "name": "migrate up", "cmd": "migrate … up", "when": ["migrations"] }] }` — `space r r`;
`${root}`, `${file}`, `${file_dir}`, `${image}` in `cmd`.
`"plugins": { "folke/zen-mode.nvim": { "cmd": "ZenMode", "opts": {} }, "folke/flash.nvim": false }` — lazy.nvim fields.

## If something is off

- **`:OwnHealth`** (`space u X`) checks everything — settings, programs, servers, formatters, linters, parsers, font,
  startup time — and says how to fix each problem.

- A mark in `settings.jsonc` — put the cursor on it, the message says what's wrong.
- A server didn't attach — `space c l`, `:Mason`. Rust needs `rustup`.
- Formatting — `space c F`; `space u f` turns it off for now.
- Everything broke — rename `settings.jsonc`: ownvim starts on the defaults.

## Inside

`lua/own/` — settings (JSONC, layers, checks, live apply), keys and actions, `theme/` (engine, VS Code converter),
`modules/<name>.lua` (`plugins`, `setup`, `reload`), `tools/` (endpoints, `.http`, ▶, background tests, Claude review).
A new module is a file plus `"<name>": true` in `modules`. Keys reference: `nvim --headless -l scripts/keys.lua`.
