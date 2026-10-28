# Configuration

[← Documentation](README.md)

Everything you see and how it behaves is set in JSON. No Lua required.

- [Two files](#two-files)
- [How settings are merged](#how-settings-are-merged)
- [When changes apply](#when-changes-apply)
- [Completion and validation](#completion-and-validation)
- [Modules](#modules)
- [Keys](#keys)
- [Neovim options](#neovim-options)
- [Section reference](#section-reference)

## Two files

| file | contents | open |
|---|---|---|
| `defaults.jsonc` | every default, each line explained. It is a reference — don't edit it | `space fC`, `:Settings defaults` |
| `settings.jsonc` | **only what you change**. Delete a line and the default comes back | `space fc`, `:Settings` |

Both are JSONC, like `settings.json` in VS Code and Zed: `//` and `/* */` comments and trailing commas are allowed.

```jsonc
{
  "theme": "sunset",
  "options": { "relativenumber": true },
  "statusline": { "style": "arrows" },
}
```

## How settings are merged

Layers stack on top of each other; each next one wins:

```
defaults.jsonc  →  JSONC bundles  →  automatically enabled languages  →  settings.jsonc
(defaults)         (extensions/*.jsonc)  (own-auto.json, see Languages)   (yours — always wins)
```

- **Objects merge by key.** One line of a section is enough; the rest comes from the defaults:
  `"statusline": { "style": "arrows" }` changes only the style.
- **Lists and values are replaced as a whole.** `"tasks": { "list": [ … ] }` replaces the entire task list.
- **`true` on top of an object** keeps the object: `"modes": true` means "on, with default settings".
- **`{}` is an empty object, not "erase everything":** `"keys": {}` does not remove the default keys.
- **`"key+"` appends to a list:** `"tasks": { "list+": [ your task ] }` adds to the default tasks instead of replacing them.
- **JSONC bundles** (`extensions/*.jsonc`) are layers between the defaults and `settings.jsonc`: [JSONC plugins](jsonc-plugins.md).

## When changes apply

**Save `settings.jsonc` and it applies immediately:** theme, colors, options, keys, status line, tabs, icons, font,
language servers (new `settings` reach the running server without a restart), formatters, linters, most module settings.

**After `:restart`** (ownvim tells you): turning a module on or off, adding or removing a plugin, the start screen,
test adapters, debugger configurations. Details — the "immediately?" column of the [reference](#section-reference).

## Completion and validation

- **Completion, like VS Code.** In `settings.jsonc`, keys and values complete: themes, styles, modules, actions for
  keys, 400+ language servers. `K` on a key shows its description from `defaults.jsonc`. The schema builds itself
  from the defaults, themes and modules.
- **Mistakes show up immediately.** Broken JSON, an unknown section, a typo in a module, option or action name — a
  highlight on the line with an explanation. The editor keeps running on the previous settings.
- **Completely broken** — rename `settings.jsonc`: ownvim starts on the defaults.

## Modules

Features are split into modules (`lua/own/modules/<name>.lua`). Turn on, off or configure them in the `modules` section:

```jsonc
"modules": {
  "minimap": true,                                    // turn on
  "learn": false,                                     // turn off
  "modes": { "auto_normal_ms": 0, "escape": ["jk"] }, // configure (and turn on)
}
```

All modules and their settings — [Modules](reference/modules.md).

## Keys

```jsonc
"keys": {
  "n <leader>z": ":Lazy",                              // a command
  "n <leader>ff": "files.git",                         // an ownvim action (list — space sk)
  "n <D-b>": "explorer",                               // cmd-b — the tree, like VS Code
  "n <leader>uH": false,                               // remove a key
  "n <leader>y": { "do": "\"+y", "desc": "To the system clipboard", "remap": false },
}
```

Before the key come the modes, as letters: `n` normal, `i` insert, `x` visual, `s` select, `o` operator-pending,
`t` terminal, `c` command line (`nx` — normal and visual). The value is an action name, raw keys (`"<C-w>h"`), a
command (`":Lazy"`), an object `{ "do", "desc", "remap" }` or `false`. Alt combinations are duplicated for the Russian
layout automatically. All keys — [Keys](../keys.ru.md).

## Neovim options

```jsonc
"options": { "relativenumber": true, "wrap": true, "scrolloff": 8 },  // any :help options
"globals": { "autoformat": false },                                    // vim.g.*
```

An unknown option is highlighted in `settings.jsonc`.

## Section reference

| section | what it sets | details | immediately? |
|---|---|---|---|
| `theme` | a theme or `{ "dark": …, "light": … }` following the system | [Appearance](appearance.md#themes) | yes |
| `colors` | color tweaks on top of a theme | [Appearance](appearance.md#tweak-colors-of-any-theme) | yes |
| `appearance` | transparent background | [Appearance](appearance.md) | yes |
| `icons` | icon theme, your own icons | [Appearance](appearance.md#icons) | yes |
| `font` | the Ghostty font | [Appearance](appearance.md#font) | yes |
| `statusline` · `tabline` · `breadcrumbs` | status line, tabs, breadcrumbs | [Appearance](appearance.md#interface) | yes |
| `dashboard` | start screen | [Appearance](appearance.md#start-screen) | after `:restart` |
| `explorer` | file tree | [Working with code](workflow.md#file-tree) | yes |
| `project` | project root: launch folder or nearest `.git` | [Configuration](configuration.md) | yes |
| `animations` | smooth cursor and scrolling | [Appearance](appearance.md#animations) | yes |
| `options` · `globals` | Neovim options and `vim.g` | [above](#neovim-options) | yes |
| `keys` | keys | [above](#keys) | yes |
| `modules` | modules: on/off and their settings | [Modules](reference/modules.md) | on/off — after `:restart` |
| `plugins` | your own plugins | [Extending](extending.md) | after `:restart` |
| `lsp` · `diagnostics` | language servers, how errors look | [Languages](languages.md) | yes |
| `completion` | completion | [Languages](languages.md#completion) | partly |
| `format` · `lint` | formatters and linters | [Languages](languages.md) | yes |
| `tools` | where programs come from: `mason` or `system` | [Languages](languages.md#where-programs-come-from) | after `:restart` |
| `auto` | what to install automatically for unfamiliar languages | [Languages](languages.md#automatic-installation) | yes |
| `test` · `debug` | tests and the debugger | [Go](go.md) | partly |
| `go` | ▶ next to functions, "implements", coverage | [Go](go.md) | yes |
| `database` | database connections | [DevOps](devops.md#databases) | yes |
| `tasks` | tasks | [DevOps](devops.md#tasks) | yes |
| `git` | gutter signs, blame, base branch | [Working with code](workflow.md#git) | yes (signs — after `:restart`) |
| `ai` | the Claude Code panel | [Working with code](workflow.md#claude) | yes |
| `sessions` | project sessions | [Working with code](workflow.md#sessions) | yes |
| `commands` | your own script commands | [Script extensions](extensions.md) | yes |
| `checks` | your own checks: a command on an event, errors on the lines | [JSONC plugins](jsonc-plugins.md#checks-your-own-linter-in-three-lines) | yes |
| `extensions` | Go extension settings | [Go extensions](go-extensions.md#extension-settings) | yes |
