# ownvim

🇷🇺 [Русская версия](README.ru.md)

**A terminal IDE for backend development, built on Neovim.** Go, Rust, Python, JavaScript / TypeScript, SQL, Docker,
C/C++, and any other language whose tools install themselves. Everything you see and how it behaves is configured in
one JSON file, no Lua. It's made so you can comfortably sit in front of it for five hours straight.

## What's inside

- **Like an IDE.** Every panel has its place. On the left: project, search & replace, git changes, outline, tests,
  database, extensions. At the bottom: terminal, run output, problems and tasks. Modes Code · Tests · Debug · Git ·
  Database are one key away, "▶ api" sits at the top right as in GoLand. Search everywhere: `space space`. The layout
  is remembered per project.
- **Languages like in GoLand.** Go, Rust, Python and JS/TS all get the same things:
  - ▶ next to `main` and tests: `space r x` runs, `r X` debugs;
  - background tests on save: `✓ 42` / `✗ 1` in the status line, a failed assertion shows up as an error on its line;
  - run configurations (every `package main`, every cargo binary, Django / FastAPI, `npm run dev`);
  - coverage, a scratch project, snippets, tasks.

  Python finds `.venv` / poetry / conda on its own. Rust expands macros and explains errors (`space R`).
- **Easy on the eyes.**
  - A soft filter on top of any theme: slightly lower contrast and saturation, the background is never pure black.
  - In the evening the theme gradually gets warmer, like Night Shift but only in the editor.
  - Every 20 minutes a quiet hint to look into the distance (the 20-20-20 rule).
  - Soft velvet and linen themes.
  - Mode switches without flashes; diagnostics don't flash on half-typed words.
- **Smooth.** The cursor glides, also while typing, like VS Code's smooth caret. Scrolling eases out. Splits and panels
  slide in, floating windows fade in, mode colors blend. `:Smooth` shows what's active and plays a demo.
- **Fast.** Code is on screen ~70 ms after launch; a typed letter appears ~6 ms after the keypress.
- **Configured like VS Code.**
  - `settings.jsonc` with key completion, descriptions and validation; save it and it applies immediately.
  - A searchable settings list (`cmd-,`).
  - An extensions panel: turn a module on or off with one key, plus a plugin store.
- **Everything installs itself.** Plugins, parsers, language servers, formatters, linters and debuggers install on
  first launch and the first time you open a file in a new language.
- **For backend work.**
  - SQL: completion from migrations and the project database; migrations (new / up / down / status), the down
    migration is written for you.
  - Docker: live `compose.yaml`, Dockerfile layer sizes, debugging inside containers. Kubernetes.
  - APIs: Gin endpoints, `.http` requests.
- **Extensible without code, and in Go.**
  - Without code: a JSONC bundle (`:PluginNew`) with keys, tasks, and your own checks with errors on lines.
  - In Go: everything built-in features can do (`:GoExtensionNew`): commands, completion items, `K` docs, fixes,
    panels; save and it works.
- **Good-looking.** 41 built-in themes (gopher, oxide, nocturne, quill and harbor are tuned for Go and Rust) plus popular
  VS Code themes; install any Marketplace theme with `:ThemeInstall`. Folder icons by meaning, prompt-style frames,
  status line and tabs built from JSON, Error Lens and Sticky Scroll.
- **In VS Code too.** `vscode/` is a separate VS Code install with the same keys (`space r x`, `space r m`…) and its own
  extension: ▶, SQL from migrations, Docker, endpoints. It doesn't touch your main VS Code.

## Install

You need Neovim 0.12+, git, Go, `tree-sitter`, `ripgrep` and a Nerd Font (Ghostty has the icons built in).

```bash
brew install neovim tree-sitter ripgrep go
git clone https://github.com/van1dalgrr-arch/ownvim ~/dev/ownvim
ln -s ~/dev/ownvim ~/.config/ownvim
echo 'alias ownvim="NVIM_APPNAME=ownvim nvim"' >> ~/.zshrc && exec zsh
ownvim        # the first launch installs everything it needs (~1 minute)
```

With [dotfiles](https://github.com/van1dalgrr-arch/dotfiles), `install.sh` does all of this. For Rust:
`brew install rustup && rustup default stable`; for Python: `brew install uv`.

## First keys

| | |
|---|---|
| `space space` | find anything: a file, a symbol, a command |
| `space e` · `space sp` · `space ge` | file tree · project search · git changes |
| `space r x` / `r X` | ▶ run / debug what the cursor is in (main or a test) |
| `space r r` | run the selected configuration (top right) |
| `space ca` · `F12` · `shift-F6` | fixes and actions · go to definition · rename |
| `alt-s` | pick a theme with live preview |
| `space fc` · `cmd-,` | my settings as a file · as a list |
| `space` and wait | every key (which-key) |

13 keys for day one and coming from VS Code — in [Getting started](docs/en/getting-started.md).

## Configure in a minute

```jsonc
// settings.jsonc — space fc. Only what differs from defaults.jsonc
{
  "theme": { "dark": "velvet", "light": "linen" },     // follows the system; alt-s — pick with preview
  "soft": { "night": { "from": "20:00" } },            // the evening mode for your eyes starts earlier
  "animations": { "scroll": { "duration_ms": 300 } },  // even softer scrolling
  "statusline": { "style": "frame" },
  "options": { "relativenumber": true },               // any Neovim option
  "modules": { "minimap": true },                      // enable a module
  "keys": { "n <leader>z": ":Lazy" },                  // your own key
  "plugins": { "folke/zen-mode.nvim": { "cmd": "ZenMode" } },  // any plugin
}
```

## Documentation

| | |
|---|---|
| [Getting started](docs/en/getting-started.md) | install, 13 keys for day one, coming from VS Code |
| [Configuration](docs/en/configuration.md) | settings layers, what applies immediately, reference of every section |
| [Workspace](docs/en/workspace.md) ⭐ | panels, modes, run configurations, search everywhere |
| [Appearance](docs/en/appearance.md) | themes, easy on the eyes, smoothness, icons, font, status line |
| [Languages](docs/en/languages.md) | Rust, Python, C/C++; servers, formatting, linters, automatic installation |
| [Go](docs/en/go.md) · [DevOps](docs/en/devops.md) | run, tests, debugging, generation · Docker, databases, tasks |
| [Working with code](docs/en/workflow.md) | search, editing, git, Claude, sessions, friction notes |
| [JSONC plugins](docs/en/jsonc-plugins.md) ⭐ · [Go extensions](docs/en/go-extensions.md) ⭐ · [Extending](docs/en/extending.md) · [Scripts](docs/en/extensions.md) | your own commands, keys and events; plugins; scripts |
| [Modules](docs/en/reference/modules.md) · [Commands](docs/en/reference/commands.md) · [Keys](docs/keys.ru.md) (Russian) | references |
| [Troubleshooting](docs/en/troubleshooting.md) · [Architecture](docs/en/architecture.md) | |
| [ownvim in VS Code](vscode/README.md) (Russian) | a separate VS Code install with ownvim's features |

Everything together — [docs/en/README.md](docs/en/README.md).

## About authorship

ownvim is my idea and my design: what the editor should have, how it should look and behave, what is inconvenient
and what to fix. But Lua and Neovim are not my stack, so **most of the code and documentation was written by an AI
(Claude)** to my requirements, and I checked the result in real work.

Ideas come from LazyVim, VS Code, GoLand and Zed. The code is ~16,000 lines of Lua in `lua/own/` plus ~5,500 lines of
the Go core in `core/` (logic moves from Lua to Go piece by piece; already in Go: the settings engine, the bridge,
Docker, endpoints, the `.http` client, background tests for Go and Rust, checks). Roadmap — [ROADMAP](ROADMAP.md).
