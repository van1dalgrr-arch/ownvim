# ownvim — my own Neovim build

🇷🇺 [Русская версия](README.ru.md)

Neovim without LazyVim: ~2300 lines of own code, ideas taken from LazyVim. Everything is set in one
JSON file, no Lua needed. Starts in about 40 ms (the LazyVim build in dotfiles takes 49).

## Install

Needs Neovim 0.12+, git, `tree-sitter` and `ripgrep` (`brew install neovim tree-sitter ripgrep`) and a Nerd Font.

```bash
git clone https://github.com/van1dalgrr-arch/ownvim ~/dev/ownvim
ln -s ~/dev/ownvim ~/.config/ownvim
alias ownvim="NVIM_APPNAME=ownvim nvim"   # in ~/.zshrc
ownvim                                   # the first run installs the plugins
```

With [dotfiles](https://github.com/van1dalgrr-arch/dotfiles), `install.sh` does all this, and rose-pine
takes the terminal theme's palette (`themes/<theme>.sh`).

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
| `icons` | icon themes — JSON in `icons/`: default, mono, accent, backend (Go/SQL/Docker/migrations stand out), ascii; `:IconTheme` — pick, `:IconThemeInstall` — from a link; own glyphs and colors — `"icons.overrides"`. Used in the tree, pickers, completion menu |
| `themes` | own theme engine: a theme is JSON in `themes/` (Dev Night, Dev Day, Sunset); `:ThemeNew` — your own (save — it repaints), `:ThemeInstall publisher.name` — any VS Code theme (Open VSX / Marketplace), `:ThemeEdit`; `"theme": { "dark", "light" }` follows the system; `"colors"` — overrides on top, as in VS Code; `alt-s` — picker with a preview, writes settings.jsonc. Plugin themes (tokyonight, rose-pine…) still work |
| `modes` | mode shown by cursor and line color, leaves insert after a pause |
| `autosave` | files write themselves, outside changes are picked up |
| `russian` | commands in the Russian layout (`о` = `j`, `вв` = `dd`), alt keys work in it too |
| `scrollbar` | a scrollbar with marks for errors, git and search |
| `smear_cursor` | smear cursor (off) |
| `completion` | completion (blink): menu with docs, ghost text, signature help, snippets (own ones in `snippets/<lang>.json`, for Go: `ife`, `errw`, `tt`, `gh`…). Section `completion` |
| `format` | format on save (conform): Go — goimports + gofumpt, SQL — pg_format, Python — ruff, Rust — rustfmt, shell — shfmt, TOML — taplo; the rest — the language server. `space c f`, `space u f` toggles. Section `format` |
| `lint` | linters on top of the server (nvim-lint): Go — golangci-lint (with the project's `.golangci.yml`), Dockerfile — hadolint. Section `lint` |
| `test` | tests (neotest): `space t r` — nearest, `t t` — file, `t T` — all, `t o` — output; a failed check is an error on its line. Go, Python (Rust — with cargo-nextest). Section `test` |
| `debug` | debugger (nvim-dap + delve): F9 run, F8 step, F7 into, shift-F8 out, ctrl-F8 breakpoint (kept across restarts); panels and variable values in the code; attach to dlv in Docker. Section `debug` |
| `database` | database (dadbod): `space D` / `alt-d` — connections and tables, the project's connection from `.env` by itself; table completion in `.sql`. Section `database` |
| `lsp` | language servers for Go, SQL (Postgres), Docker, Python, Rust, JSON, YAML — mason installs them; errors on their lines, `gd`/`gr`/`K`, rename `space c r`, fixes `space c a`, inlay hints. Sections `lsp`, `diagnostics`, `tools` |

Module code is `lua/own/modules/<name>.lua`, the core is `lua/own/` (settings, JSONC, keys, actions).

## Next

Stage 1 of 4 — the base. Next: Go as an IDE (gopls, completion, formatting, tests, debugger),
git, moving my own modules over (endpoints, `.http`, ▶, background tests, Claude). Once it
catches up, `ownvim` becomes the main `nvim`.
