# Extending

[← Documentation](README.md)

Ways to add your own:

| way | when | you need to know |
|---|---|---|
| [**JSONC plugin**](jsonc-plugins.md) ⭐ | keys, tasks, your own checks, status line blocks — as a bundle | nothing, it's all JSON |
| [**Go extension**](go-extensions.md) ⭐ | almost everything: commands, keys, events, labels and findings on lines, windows, network, code parsing | Go |
| [Script extension](extensions.md) | your own command over text: sort, transform, generate | any language: stdin → stdout |
| [Plugin](#plugins) | a ready-made Neovim plugin from the catalog | nothing, it's all in `settings.jsonc` |
| [Your own module](#your-own-module) | a new ownvim feature with its own settings | Lua and the Neovim API |

## Plugins

### Store

`:Plugins` (`space L`) — the [awesome-neovim](https://github.com/rockerBOO/awesome-neovim) catalog: ~1400 plugins with
descriptions and sections, search across everything, `●` — already installed.

| | |
|---|---|
| `enter` | install: a line is added to `settings.jsonc`, ownvim offers to restart |
| `ctrl-x` | remove |
| `ctrl-o` | open the GitHub page |

### By hand

```jsonc
"plugins": {
  "folke/zen-mode.nvim": { "cmd": "ZenMode", "opts": { "window": { "width": 100 } } },
  "folke/twilight.nvim": true,          // default settings
  "folke/flash.nvim": false,            // remove a plugin that a built-in module uses
},
```

Fields are the same as [lazy.nvim](https://lazy.folke.io/spec): `opts`, `event`, `cmd`, `ft`, `keys`, `branch`,
`version`… Plugins install and uninstall after `:restart`. Manage installed ones — `:Lazy` (`space l`).

## Your own module

A module is a file `lua/own/modules/<name>.lua` that returns a table:

```lua
-- What the module does, in a line or two (this header ends up in the reference).
-- Module settings: { "option": value }
local M = {}

-- plugins for lazy.nvim (a table or a function of the module settings)
function M.plugins(opts)
  return { { "author/plugin", event = "VeryLazy", opts = {} } }
end

-- startup: opts is the modules.<name> object without the enabled field
function M.setup(opts) end

-- settings.jsonc was saved — apply the new settings live (optional)
function M.reload(opts) end

return M
```

And a line in `defaults.jsonc`, in the `modules` section: `"<name>": true` (or an object with settings and a comment).

The rules the built-in modules follow:

- **Settings come only from JSON.** Anything a user might want to change goes into the module settings or its own
  `settings.jsonc` section, explained in `defaults.jsonc`.
- **Apply live** where possible (`reload`); where not, say that `:restart` is needed.
- **Don't slow down startup.** Load plugins lazily (`event`, `cmd`, `ft`, `keys`; decorations — `VeryLazy`, after the
  first paint), do heavy work after drawing (`vim.schedule`, `vim.defer_fn`), run external programs asynchronously
  (`vim.system`).
- **Report errors where they're visible.** A settings problem — `settings.warn(key, message)`: a highlight on the
  `settings.jsonc` line.
- **Keys** go through actions in `lua/own/actions.lua` and lines in the `keys` section, so they show up in `space sk`
  and in the [reference](../keys.ru.md).

After changing keys in `defaults.jsonc`, regenerate the reference:

```bash
NVIM_APPNAME=ownvim nvim --headless -l scripts/keys.lua > docs/keys.ru.md
```

How ownvim is built as a whole — [Architecture](architecture.md).
