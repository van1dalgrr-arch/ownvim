# Getting started

[← Documentation](README.md)

- [Requirements](#requirements)
- [Install](#install)
- [First launch](#first-launch)
- [13 keys for day one](#13-keys-for-day-one)
- [Coming from VS Code](#coming-from-vs-code)
- [Next](#next)

## Requirements

| | why |
|---|---|
| Neovim **0.12+** | the editor itself (`brew install neovim`) |
| git | installing plugins |
| `tree-sitter` | building parsers for highlighting (`brew install tree-sitter`) |
| `ripgrep` | project search (`brew install ripgrep`) |
| Go | the ownvim core (`core/`) is built on first launch (`brew install go`); without Go a fallback settings engine is used |
| a Nerd Font | icons; Ghostty has them built in, so any font works there |

The recommended terminal is **Ghostty**: ownvim can change its font (`:Font`), show images (kitty protocol) and use a
transparent background. Everything else works the same in other terminals.

Optional, used when installed: `lazygit` (git), `yazi` (files), `docker` (the Docker module), `kubectl` (Kubernetes),
`freeze` (code screenshots), ImageMagick (jpg/webp images), `trash` (delete to the bin).

## Install

```bash
brew install neovim tree-sitter ripgrep go
git clone https://github.com/van1dalgrr-arch/ownvim ~/dev/ownvim
ln -s ~/dev/ownvim ~/.config/ownvim
echo 'alias ownvim="NVIM_APPNAME=ownvim nvim"' >> ~/.zshrc && exec zsh
ownvim
```

`NVIM_APPNAME=ownvim` keeps ownvim separate from your regular `nvim`: its own settings (`~/.config/ownvim`), plugins
and data (`~/.local/share/ownvim`). Your main Neovim setup is untouched.

With the [dotfiles](https://github.com/van1dalgrr-arch/dotfiles), `install.sh` does all of this.

## First launch

The first launch takes about a minute: ownvim installs plugins, language parsers, language servers, formatters and
linters. After that, code is on screen ~70 ms after launch.

Then:

1. **`:OwnHealth`** — checks that everything is in place: settings, programs, servers, font. Every problem comes with
   instructions on how to fix it.
2. **`space fc`** — open your settings (`settings.jsonc`). It is almost empty: everything comes from the defaults.
3. **`alt-s`** — pick a theme: moving through the list recolors the whole editor right away.

Open a file in a language nothing is configured for, and its server, formatter and linter install themselves
(see [Languages](languages.md#automatic-installation)).

## 13 keys for day one

`space` is the main key (leader). A second after pressing it, a hint at the bottom shows what you can press next.

| what | key |
|---|---|
| start / stop typing | `i` / `esc`, or a quick `jk` (`ол` in the Russian layout); after 5 s without typing — by itself |
| accept a completion | `tab` or `enter` (the grey inline continuation — also `tab`) |
| save | `cmd-s` (files save themselves anyway) |
| copy / paste / cut | `cmd-c` / `cmd-v` / `cmd-x` (without a selection — the line), `cmd-a` — all, `cmd-z` — undo |
| find a file | `space space` or `cmd-p` |
| search text in the project | `space /` |
| file tree | `space e` |
| jump to a line | `enter` — letters appear next to the lines, press one |
| go to definition / references | `gd` / `gr` |
| documentation under the cursor | `K` |
| fix an error, code actions | `space ca` |
| all keys, searchable | `space sk` |
| quit | `space qq` |

Commands also work in the Russian layout (`о` = `j`, `Ж` = `:`), no need to switch. Full list — [Keys](../keys.ru.md)
(descriptions in Russian) or `space sk` inside ownvim.

## Coming from VS Code

| VS Code | ownvim |
|---|---|
| `settings.json` | `settings.jsonc` (`space fc`) — the same JSON with comments, with key completion and validation |
| Default Settings | `defaults.jsonc` (`space fC`) — every default with an explanation |
| Command Palette (`cmd-shift-p`) | `cmd-shift-p` — all commands; `space sk` — all keys and actions |
| Quick Open (`cmd-p`) | `cmd-p` or `space space` |
| Search in project (`cmd-shift-f`) | `space /`; find and replace — `space sr` |
| Explorer | `space e` or the icon on the left |
| Extensions | `:Plugins` (`space L`) — a catalog of ~1400 plugins |
| Color Theme (`cmd-k cmd-t`) | `alt-s`; any Marketplace theme — `:ThemeInstall publisher.name` |
| `workbench.colorCustomizations` | the `colors` section |
| Terminal · Problems | bottom panel: `space j`, tabs — `space jt` / `jp` / `jo` |
| Go to Definition / References | `gd` / `gr` |
| Quick Fix (`cmd-.`) | `space ca` |
| Rename Symbol (`F2`) | `space cr` or `shift-F6` (`F2` jumps to the next error, as in GoLand) |
| Error Lens, Sticky Scroll, bracket colors, minimap | modules `error_lens`, `sticky_scroll`, `brackets`, `minimap` |
| Source Control | `alt-g` (lazygit), changes in the gutter, `space gm` — branch vs main |
| Run and Debug | `F9` — run, `F8` — step, `ctrl-F8` — breakpoint (as in GoLand) |
| Tasks (`tasks.json`) | the `tasks` section, run with `space rr` |

## Next

- [Configuration](configuration.md) — change anything without touching code.
- [Appearance](appearance.md) — themes, icons, font.
- [Working with code](workflow.md) — search, editing, git, Claude.
