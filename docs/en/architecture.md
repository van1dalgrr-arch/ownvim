# Architecture

[← Documentation](README.md)

For those who want to change ownvim itself. You can use it without any of this.

- [Principles](#principles)
- [Files](#files)
- [Go core and bridge](#go-core-and-bridge)
- [Startup order](#startup-order)
- [Settings: layers and live application](#settings-layers-and-live-application)
- [Modules](#modules)
- [Keys and actions](#keys-and-actions)
- [Themes](#themes)
- [Programs: mason and automatic installation](#programs-mason-and-automatic-installation)
- [Where things are stored](#where-things-are-stored)
- [Checking changes](#checking-changes)

## Principles

1. **Configuration is JSON, not Lua.** Anything you might want to change is in `settings.jsonc`, explained in
   `defaults.jsonc`.
2. **Applies immediately.** Save the settings and the change is visible without a restart wherever possible.
3. **Fast.** Code is on screen ~70 ms after launch; a letter ~6 ms after the keypress: plugins load lazily
   (completion — on first typing), decorations (git signs, rainbow brackets, TODO, sticky header, linter) — after the
   first paint, external programs — asynchronously.
4. **Own code where a plugin gets in the way.** Status line, tabs, file tree, themes, icons, tasks, the `.http`
   client, endpoints, Docker are ownvim's own code; plugins are used where they're good (lazy.nvim, snacks, blink,
   conform, nvim-lint, neotest, dap…).
5. **A mistake doesn't break the editor.** A wrong setting is highlighted; the editor keeps the previous settings.

## Files

```
init.lua                  → require("own").setup()
defaults.jsonc            every default, explained (the reference)
settings.jsonc            user settings (only the differences)
themes/*.json             themes (ownvim's own and converted from VS Code)
icons/*.json              icon themes
snippets/<language>.json  your own snippets (VS Code format)
extensions/               script extensions (Python etc.)
core/                     the Go core (the ownvimd program)
  cmd/ownvimd/            entry point: settings load|set, serve (the bridge), version
  jsonc/                  JSON with comments, readable error messages
  settings/               settings engine: merging layers, validation, the auto-install layer, writing a key, cache
  bridge/                 msgpack-RPC bridge to Neovim (Register — add a method)
  sdk/                    the Go extension kit: Command, Key, On, Ctx (docs/en/go-extensions.md)
  extensions/<name>/      Go extensions: docker, endpoints, http, autotest, checks (built-in), examples; all.go — their list
  httpx/                  HTTP requests for endpoints and .http: send, response, token, curl
lua/own/
  init.lua                startup order, applying settings on save
  core.lua                building ownvimd, running its commands, the bridge (request / notify), build errors on lines
  ext.lua                 Go extensions in ownvim: manifest → commands, keys, events, panels; the API behind sdk.Ctx
  ext_lsp.lua             the in-editor "ownvim" server: Go extensions' completion, K, fixes via LSP
  settings.lua            settings: the Go core cache, live application, warn; a fallback Lua engine when Go is missing
  jsonc.lua               JSON with comments and trailing commas
  schema.lua              JSON schema for completion in settings.jsonc
  keys.lua · actions.lua  keys from the keys section and the actions behind them
  auto.lua                automatic tool installation for unfamiliar languages (a settings layer)
  tools.lua               mason: install a server or program if it's missing
  root.lua                project root
  tree.lua                file tree
  store.lua               plugin store (:Plugins)
  health.lua              :OwnHealth
  themes.lua · palette.lua theme picker (alt-s), rose-pine in terminal colors
  modes.lua               mode colors, leaving insert mode after a pause
  theme/                  theme engine: palette → highlight groups, VS Code theme converter, installation
  modules/<name>.lua      modules — one per feature; modules/workspace.lua — panels in fixed places (edgy), modes, layout per project
  tools/                  tools: ▶ run, background tests, Claude review, screenshot, notes;
                          launch.lua — run configurations (top right), everywhere.lua — search everywhere
scripts/keys.lua          docs/keys.ru.md from defaults.jsonc
scripts/bench_*.py        speed measurements: paint after launch, typing latency
```

## Go core and bridge

Logic is moving from Lua to Go piece by piece. Already in Go: the settings engine, Docker in your code, Gin endpoints,
the `.http` client — the last three are written on `core/sdk`, like any extension of your own ([Go extensions](go-extensions.md)). Lua stays a thin layer — whatever runs on every redraw and keystroke,
plugin configs, registering keys and events.

- **Building.** `ownvimd` is built into `~/.local/share/ownvim/ownvimd`: on first launch — right away (`go build`);
  after Go code changes — in the background, a second after the first paint (`own.core.rebuild_async`).
- **Commands** — for what's needed synchronously and statelessly: `require("own.core").run({ "settings", "load", … })`.
- **The bridge** — for modules that talk to Neovim: `ownvimd serve` starts on the first call,
  `require("own.core").request("method", …)` waits for the answer, `.notify` doesn't. A call costs ~0.01–0.05 ms, the
  first one (starting the process) ~3 ms. A new method — `bridge.Register("name", func(…) (…, error))` in Go.
- **Settings** are needed before plugins load, and starting a process costs more than reading a file, so Go writes the
  result to `own-settings.cache.json` together with a fingerprint of the source files (mtime and size of
  `defaults.jsonc`, `settings.jsonc`, `own-auto.json`, the options list, the modules folder and the program itself).
  At startup Lua checks the fingerprint (a few `stat` calls) and reads the cache — 0.6 ms vs 3 ms for the old Lua
  engine; Go runs only when something changed (+~7 ms once).
- **Core tests:** `cd core && go test ./...`.

## Startup order

```
1. settings        the Go core cache (or ownvimd settings load if files changed): defaults + JSONC bundles
                   + auto-install + settings.jsonc  →  settings.current
2. globals, options before plugins: the leader must be known in advance
3. lazy.nvim       plugins of enabled modules (M.plugins) + the plugins section
4. modules         M.setup(opts) of each enabled module, alphabetically; a failure is a warning, not an error
5. theme, keys
6. services        notes, tree, auto-install, :Settings, :OwnHealth
7. watching        settings.jsonc or defaults.jsonc saved → reread → apply
```

## Settings: layers and live application

`settings.load()` takes the Go core's result (`core/settings`): it reads both files, checks the top level, module and
option names (Lua writes the option list to `own-options.json`) and merges:

```
merge(merge(defaults, auto_layer), user)
```

- `merge` — objects by key, everything else replaced; `true` on top of an object keeps the object; `{}` — an empty object.
- `auto_layer` — languages ownvim enabled itself (`auto.lua`, the `own-auto.json` file): servers in `lsp.servers`,
  formatters and linters per language. The layer sits below `settings.jsonc`, so the user always wins.
- Errors go to `settings.problems` (path → diagnostics) and are shown on the lines of the open settings file.
  `settings.warn(key, text)` finds the key in `settings.jsonc`, then in `defaults.jsonc`.
- `settings.set(key, value)` — `ownvimd settings set`: writes a top-level value to `settings.jsonc` without touching the
  comments around it (only a top-level key is matched; nested keys with the same name are left alone).

On save, `init.on_change(new, old)` applies globals and options, calls each module's `M.reload(opts)`, the theme and
the keys. If the set of modules or the `plugins` section changed, it asks for `:restart`.

## Modules

Contract and rules — [Extending → Your own module](extending.md#your-own-module). In short:

| field | called |
|---|---|
| `plugins(opts)` or a table | when building the lazy.nvim plugin list |
| `setup(opts)` | at startup, after plugins |
| `reload(opts)` | when settings are saved |

`opts` is the `modules.<name>` object without `enabled`. A module is on if its value is `true` or an object without
`"enabled": false`.

## Keys and actions

The `keys` section: `"modes key": what`. `keys.lua` parses the value: an action name from `actions.lua` (function +
description), raw keys, a `:command`, an object `{ do, desc, remap }` or `false`. Action descriptions show in
which-key, `space sk` and the [reference](../keys.ru.md) built by `scripts/keys.lua`. Alt combinations are duplicated
for the Russian layout automatically (the `russian` module).

## Themes

An ownvim theme is JSON: `palette` (colors), `syntax` (code roles → colors), `groups` (any highlight groups),
`include` (inheritance). `theme/groups.lua` builds every group from the palette: interface, syntax, treesitter, LSP
semantic tokens, plugin groups. `theme/vscode.lua` converts a VS Code theme (`tokenColors`, `semanticTokenColors`,
`colors`) into this format; `theme/install.lua` downloads the extension from Open VSX / the Marketplace. Each theme is a
regular colorscheme (a `colors/<name>.lua` shim is generated), so `:colorscheme` and the `alt-s` picker work.

## Programs: mason and automatic installation

- `tools.lua` — a program is needed: in PATH — use it; not there — install a mason package (by server name from the
  registry or by program name); nowhere to get it — a warning in the settings. The mason registry isn't loaded at
  startup: server packages are cached in `own-lsp-packages.json`.
- Servers install at startup if enabled; formatters and linters — the first time a file of their language opens.
- `auto.lua` — on `FileType` of an unfamiliar language: the curated set from `auto.languages` or a mason registry
  search by the `filetypes` of nvim-lspconfig configs (servers covering more than 6 languages are dropped). The
  decision is written to `own-auto.json`, settings are reread, and `lsp`, `format`, `lint` apply it via `reload()`.

## Where things are stored

| path | what |
|---|---|
| `~/.config/ownvim` | ownvim itself (a link to the repository) and `settings.jsonc` |
| `~/.local/share/ownvim/lazy` | plugins |
| `~/.local/share/ownvim/mason` | servers, formatters, linters |
| `~/.local/share/ownvim/ownvimd` | the Go core (builds itself) |
| `~/.local/share/ownvim/own-settings.cache.json` | final settings and problems with a fingerprint of the source files |
| `~/.local/share/ownvim/own-options.json` | nvim option names for validating the `options` section |
| `~/.local/share/ownvim/own-auto.json` | automatically enabled languages |
| `~/.local/share/ownvim/own-notes.json` | friction notes |
| `~/.local/share/ownvim/own-settings.schema.json` | JSON schema for settings completion |
| `~/.local/state/ownvim/colorscheme` | the theme picked in `alt-s` |
| `~/.local/state/ownvim/sessions` | project sessions |
| `~/.local/state/ownvim/*.log` | logs: `lsp.log`, `mason.log`, `conform.log`, `dap.log`, `ownvimd.log` (bridge)… |

## Checking changes

- **`:OwnHealth`** — settings, programs, servers, formatters, parsers, font, theme, startup time.
- **Speed as a person sees it**, in a real pseudo-terminal (the script answers nvim's queries like Ghostty does):
  - `python3 scripts/bench_paint.py <folder> main.go Println` — how many ms after launch the code is drawn on screen;
  - `python3 scripts/bench_typing.py <folder> main.go` — from a keypress in insert mode to the letter on screen.
  Compare with the previous commit: `git worktree add /tmp/base/ownvim HEAD`, then `XDG_CONFIG_HOME=/tmp/base python3 …`.
- **Where startup time goes:** `NVIM_APPNAME=ownvim nvim --startuptime /tmp/st.txt +qa main.go`; which plugins loaded
  and why — `require("lazy.core.config").plugins[name]._.loaded`.
- **Headless:** check behavior with `NVIM_APPNAME=ownvim nvim --headless -c 'luafile check.lua' file`, where
  `check.lua` waits for loading via `vim.defer_fn`, checks the state (diagnostics, extmarks, LSP clients) and writes the
  result to a file.
- **Keys reference** after changing `keys` — `scripts/keys.lua`.
