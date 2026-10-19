# ownvim — my own Neovim build

🇷🇺 [Русская версия](README.ru.md)

Neovim without LazyVim: ~4500 lines of own code, ideas taken from LazyVim. Everything is set in one
JSON file, no Lua needed. Starts in 38 ms, 69 with a Go file open (the LazyVim build in dotfiles: 107 on the same file).

**[Guide](docs/guide.md)** — install, settings recipes, troubleshooting · **[All keys](docs/keys.ru.md)** (Russian)

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
    "minimap": true,                                     // turn a module on
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
| `ui` | start screen from JSON (header, buttons, sections — section `dashboard`), notifications, which-key, indent guides |
| `font` | the Ghostty font from `settings.jsonc` (family, size, ligatures, line height, OpenType features); `:Font` — pick an installed one, `:FontInstall <name>` — install via brew / Nerd Fonts. Ghostty has Nerd Font glyphs built in — any font works |
| `tabline` | VS Code-like tabs: icon, name, ● when unsaved, close button; mouse click, middle click closes; same names get their folder; scrolls to the current one. Section `tabline` |
| `breadcrumbs` | breadcrumbs on top: folder › file › type › function at the cursor (from the syntax tree, any language). Section `breadcrumbs` |
| `statusline` | own status line: blocks in JSON (mode, branch, errors, file, LSP, position, time, search, macro + your own — text or a command's output on a timer), styles bubbles / arrows / slant / flat / plain, colors from the theme. Section `statusline` |
| `picker` | find files, text, commands (Snacks); `alt-c` in a picker — project ↔ launch folder |
| file tree | own (`space e`): git colors and letters, error dots, compact folders, create/rename/delete to trash/copy/paste; look — section `explorer` (`"engine": "snacks"` for the snacks tree) |
| `treesitter` | highlighting, indent, folds; languages listed in settings, missing ones install themselves |
| `editing` | pairs, text objects `af`/`ic`/`ao`, surround `gsa`/`gsd`/`gsr`, `s` to jump, TODO |
| `icons` | icon themes — JSON in `icons/`: default, mono, accent, backend (Go/SQL/Docker/migrations stand out), ascii; `:IconTheme` — pick, `:IconThemeInstall` — from a link; own glyphs and colors — `"icons.overrides"`. Used in the tree, pickers, completion menu |
| `themes` | own theme engine: a theme is JSON in `themes/` (Dev Night, Dev Day, Sunset); `:ThemeNew` — your own (save — it repaints), `:ThemeInstall publisher.name` — any VS Code theme (Open VSX / Marketplace), `:ThemeEdit`; `"theme": { "dark", "light" }` follows the system; `"colors"` — overrides on top, as in VS Code; `alt-s` — picker with a preview, writes settings.jsonc. Plugin themes (tokyonight, rose-pine…) still work |
| `modes` | mode shown by cursor and line color, leaves insert after a pause |
| `autosave` | files write themselves, outside changes are picked up |
| `russian` | commands in the Russian layout (`о` = `j`, `вв` = `dd`), alt keys work in it too |
| `scrollbar` | a scrollbar with marks for errors, git and search |
| `animations` | smooth cursor (also while typing, like cursorSmoothCaretAnimation) and smooth scroll — each on/off, speed in `animations` |
| `brackets` | colored bracket pairs, like VS Code; level colors from the theme |
| `sticky_scroll` | the function header sticks on top, like VS Code's Sticky Scroll |
| `minimap` | a VS Code-like minimap on the right (off; `space u m`) |
| `completion` | completion (blink): menu with docs, ghost text, signature help, snippets (own ones in `snippets/<lang>.json`, for Go: `ife`, `errw`, `tt`, `gh`…). Section `completion` |
| `format` | format on save (conform): Go — goimports + gofumpt, SQL — pg_format, Python — ruff, Rust — rustfmt, shell — shfmt, TOML — taplo; the rest — the language server. `space c f`, `space u f` toggles. Section `format` |
| `lint` | linters on top of the server (nvim-lint): Go — golangci-lint (with the project's `.golangci.yml`), Dockerfile — hadolint. Section `lint` |
| `test` | tests (neotest): `space t r` — nearest, `t t` — file, `t T` — all, `t o` — output; a failed check is an error on its line. Go, Python (Rust — with cargo-nextest). Section `test` |
| `debug` | debugger (nvim-dap + delve): F9 run, F8 step, F7 into, shift-F8 out, ctrl-F8 breakpoint (kept across restarts); panels and variable values in the code; attach to dlv in Docker. Section `debug` |
| `database` | database (dadbod): `space D` / `alt-d` — connections and tables, the project's connection from `.env` by itself; table completion in `.sql`. Section `database` |
| `git` | changes in the gutter, `]h`/`[h` — hunks, `space g h s/r/p` — stage / reset / preview, blame (`space u B`), diffview — three-way merge, file history, branch vs main (`space g m`), lazygit (`alt-g`), branches, commits, undo history without git (`space U`). Section `git` |
| `go` | Go like GoLand: ▶ next to `main` and tests (`space r x`, debugger — `r X`), actions with a preview (`space c a`), refactorings (`c x/i/w`), "implements: io.Reader" on types, generation (`space G` — tags, interface, tests, if err, JSON → struct), peek (`gp d/r/i/t`), coverage (`G v`), Go scratch (`r g`). Section `go` |
| `tasks` | tasks, like ctrl-r in Zed (`space r r`, `alt-t`): the list lives in `settings.jsonc`, with `when` and `${root}`/`${file}`. Section `tasks` |
| `ai` | Claude Code: `alt-c` — show/hide, `space a x` — fix the error under the cursor, `a R` — branch review (findings on their lines). Section `ai` |
| `http` | Postman in a file: `.http`, enter sends; Gin endpoints (`space r e`, `alt-a`), `api.http` from the routes (`r h`, `alt-p`) |
| `autotest` | Go tests in the background after a save: `✓ 42` / `✗ 1` in the status line, a failed check on its line; `space t A` |
| `error_lens` | errors to the right of the line, like Error Lens |
| `multicursor` | multiple cursors: `ctrl-n`, `space m` |
| `dial` | `ctrl-a`/`ctrl-x`: your own per-language cycles in settings (Go: `:=`↔`=`, `Error`↔`Fatal`, HTTP methods and statuses…) |
| `cloak` · `yanky` · `files` | `.env` secrets masked · yank history (`space p`) · yazi, find-and-replace, structural replace (ast-grep) |
| `comfort` · `learn` | `enter` — jump to a line · motion hints and a habit coach |
| `system` · `kubernetes` | `alt-o` — containers, `alt-w` — GitHub (gw), `space P` — code screenshot · `space k` — kubectl.nvim |
| `sessions` | project sessions: open ownvim in a folder with no files — tabs and splits come back; `space q s/S/d` |
| `lsp` | language servers for Go, C/C++ (clangd + clang-tidy, `space c s` — `.h` ↔ `.cpp`), CMake, SQL (Postgres), Docker, Python, Rust, JSON, YAML — mason installs them; errors on their lines, `gd`/`gr`/`K`, rename `space c r`, fixes `space c a`, inlay hints. Sections `lsp`, `diagnostics`, `tools` |

Module code is `lua/own/modules/<name>.lua`, the core is `lua/own/` (settings, JSONC, keys, actions).

## Next

All 4 stages of the plan are done ([ROADMAP](ROADMAP.md)): core and settings, IDE, own design, git and tools.
Next — whatever is missing in daily work; once ownvim replaces the LazyVim build, it becomes the main `nvim`.
