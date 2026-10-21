# Commands

[← Documentation](../README.md)

ownvim's commands (`:Name`). Plugin commands (`:Lazy`, `:Mason`, `:Glance`…) are in their own documentation; all of
them at once — `cmd-shift-p` or `space sC`.

## Settings and health

| command | what | key |
|---|---|---|
| `:Settings` | open your `settings.jsonc` | `space fc` |
| `:Settings defaults` | open `defaults.jsonc` — every default | `space fC` |
| `:OwnHealth` | check settings, programs, servers, formatters, parsers, font, theme, startup time | `space uX` |
| `:restart` | restart ownvim (needed after enabling modules and plugins) | |

## Appearance

| command | what | key |
|---|---|---|
| `:ThemeNew name [base]` | your own theme based on another; save the file and it recolors | |
| `:ThemeEdit` | open the current theme's file | |
| `:ThemeInstall publisher.name` | a VS Code theme (Open VSX / Marketplace), a `.vsix`, `.json` or a path | |
| `:IconTheme [name]` | pick an icon theme | |
| `:IconThemeInstall link` | install an icon theme from a `.json` | |
| `:Font [name]` | pick an installed font | |
| `:FontInstall name` | install a font (brew: Google Fonts, Nerd Fonts) and activate it | |

Theme picker with preview — `alt-s` / `space uC`.

## Languages and tools

| command | what |
|---|---|
| `:AutoTools` | which languages ownvim configured itself and what it installed for them |
| `:AutoTools language` | forget a language — decide again the next time a file opens |
| `:Mason` | servers, formatters, linters: what's installed (`space cm`) |
| `:DockerLayers` | pick the image whose layer sizes to show in the Dockerfile |
| `:TestsPanel` | the "Тесты в фоне" (background tests) panel (`space tv`) |
| `:AutoTests` | background tests: off / on (`space tA`) |

## Extending

| command | what | key |
|---|---|---|
| `:Plugins` | plugin store: ~1400 awesome-neovim plugins | `space L` |
| `:Lazy` | installed plugins, updates, installation errors | `space l` |
| `:Commands` | your own script commands | `space C` |
| `:ExtensionNew name` | an `extensions/name.py` template and a line in `commands` | |
| `:GoExtensionNew name` | a Go extension template: `core/extensions/name/name.go` ([guide](../go-extensions.md)) | |
| `:GoExtensions` | what Go extensions declared: commands and events | |
| `:PluginNew name` | a no-code JSONC bundle: `extensions/name.jsonc` with every section explained ([guide](../jsonc-plugins.md)) | |
| `:Checks` | run your own checks (the `checks` section) for the current file | |
| `:View [name]` | open or close a Go extension panel | |

## Comfort

| command | what | key |
|---|---|---|
| `:Quiet` | quiet mode: hide everything distracting; again — restore | `space uq` |
| `:Rest` | start a break (☕ and a countdown in the status line) | |
| `:RestLater` | remind me about a break in 10 minutes | |

## Notes

| command | what | key |
|---|---|---|
| `:NoteAdd` | record an annoyance along with its place | `space ?` |
| `:Notes` | the list of notes | `space N` |
