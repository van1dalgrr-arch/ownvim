# ownvim

🇷🇺 [Русская версия](README.ru.md)

**A terminal IDE for backend development, built on Neovim.** Go, SQL, Docker, C/C++, Python, Rust — and any other
language, whose tools install themselves. Everything you see and how it behaves is configured in one JSON file, no Lua.

- **Fast.** Code is on screen ~70 ms after launch; a typed letter appears ~6 ms after the keypress.
- **Configured like VS Code.** `settings.jsonc` with key completion, descriptions and validation; save it and the
  change applies immediately, no restart.
- **Installs itself.** Plugins, parsers, language servers, formatters and linters — on first launch and the first
  time you open a file in a new language.
- **Built for backend work.** ▶ next to `main` and tests, tests running in the background, a debugger that attaches to
  Docker, Go code generation, Gin endpoints, `.http` requests, databases, a live `compose.yaml`, layer sizes in Dockerfiles.
- **Extensible without code and in Go.** No code — a JSONC bundle: keys, tasks, your own checks with errors on the lines
  (`:PluginNew`). In Go — everything the built-ins can do: commands, entries in the completion menu, `K` descriptions,
  fixes in `space ca`, your own panels and status line; save and it works without a restart (`:GoExtensionNew`).
- **Good-looking.** 30+ themes (its own, popular VS Code themes, and any Marketplace theme via `:ThemeInstall`), folder
  icons by meaning, status line and tabs from JSON, Error Lens, Sticky Scroll, a smooth cursor.

## Install

Requires Neovim 0.12+, git, Go, `tree-sitter`, `ripgrep` and a Nerd Font (Ghostty has the icons built in).

```bash
brew install neovim tree-sitter ripgrep go
git clone https://github.com/van1dalgrr-arch/ownvim ~/dev/ownvim
ln -s ~/dev/ownvim ~/.config/ownvim
echo 'alias ownvim="NVIM_APPNAME=ownvim nvim"' >> ~/.zshrc && exec zsh
ownvim        # the first launch installs everything it needs (~1 minute)
```

With the [dotfiles](https://github.com/van1dalgrr-arch/dotfiles), `install.sh` does all of this.

## Configure in a minute

```jsonc
// settings.jsonc — space fc. Only what differs from defaults.jsonc
{
  "theme": "onedark",                                  // or alt-s — pick with a live preview
  "icons": { "theme": "material" },
  "statusline": { "style": "arrows" },
  "options": { "relativenumber": true },               // any Neovim option
  "modules": { "minimap": true },                      // turn a module on
  "keys": { "n <leader>z": ":Lazy" },                  // your own key
  "plugins": { "folke/zen-mode.nvim": { "cmd": "ZenMode" } },  // any plugin
}
```

## Documentation

| | |
|---|---|
| [Getting started](docs/en/getting-started.md) | install, 13 keys for day one, coming from VS Code |
| [Configuration](docs/en/configuration.md) | settings layers, what applies immediately, reference of every section |
| [Appearance](docs/en/appearance.md) | themes, icons, font, status line, panels, animations |
| [Languages](docs/en/languages.md) | servers, formatting, linters, automatic installation |
| [Go](docs/en/go.md) · [DevOps](docs/en/devops.md) | run, tests, debugging, generation · Docker, databases, tasks |
| [Working with code](docs/en/workflow.md) | search, editing, git, Claude, sessions, friction notes |
| [JSONC plugins](docs/en/jsonc-plugins.md) ⭐ · [Go extensions](docs/en/go-extensions.md) ⭐ · [Extending](docs/en/extending.md) · [Scripts](docs/en/extensions.md) | your own commands, keys and events in Go; plugins; scripts |
| [Modules](docs/en/reference/modules.md) · [Commands](docs/en/reference/commands.md) · [Keys](docs/keys.ru.md) (Russian) | references |
| [Troubleshooting](docs/en/troubleshooting.md) · [Architecture](docs/en/architecture.md) | |

Everything together — [docs/en/README.md](docs/en/README.md).

## About authorship

ownvim is my idea and my design: what the editor should have, how it should look and behave, what is inconvenient
and what to fix. But Lua and Neovim are not my stack, so **most of the code and documentation was written by an AI
(Claude)** to my requirements, and I checked the result in real work.

Ideas come from LazyVim, VS Code, GoLand and Zed. The code is ~8700 lines of Lua in `lua/own/` plus a Go core in `core/` (logic is moving from Lua to Go piece by piece; already in Go: the settings engine, the bridge, Docker, endpoints, the `.http` client, background tests, checks); roadmap — [ROADMAP](ROADMAP.md).
