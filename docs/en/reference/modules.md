# Modules

[← Documentation](../README.md)

Every ownvim feature is a module (`lua/own/modules/<name>.lua`). Turn on, off or configure in the `modules` section of
`settings.jsonc`:

```jsonc
"modules": { "minimap": true, "learn": false, "error_lens": { "preset": "classic" } },
```

Turning on and off — after `:restart`; module settings — usually immediately.

## Interface

| module | what it does | default | settings |
|---|---|---|---|
| `ui` | start screen, notifications, key hints (which-key), indent guides, number column | on | the `dashboard` section |
| `themes` | themes and the picker with preview (`alt-s`) | on | the `theme`, `colors` sections |
| `icons` | icon themes (material, default, backend…) | on | the `icons` section |
| `font` | Ghostty font, `:Font`, `:FontInstall` | on | the `font` section |
| `statusline` | ownvim's status line built from blocks | on | the `statusline` section |
| `tabline` | tabs, like VS Code | on | the `tabline` section |
| `breadcrumbs` | folder › file › type › function at the top | on | the `breadcrumbs` section |
| `panels` | icon bar on the left, bottom panel "Terminal · Problems · Tasks" | on | `activity_bar`, `bottom` |
| `animations` | smooth cursor and scrolling | on | the `animations` section |
| `modes` | mode shown by cursor and line color; leaving insert with `jk` / `ол`; leaving insert after a pause | on | `escape`, `escape_ms`, `auto_normal_ms` |
| `scrollbar` | scrollbar with error, git and search marks | on | — |
| `brackets` | colored bracket pairs | on | `colors` |
| `sticky_scroll` | the function header sticks to the top | on | `max_lines` |
| `error_lens` | errors to the right of the line, also while typing | on | `preset`, `break_after`, `insert`, `all_on_cursorline` |
| `quiet` | quiet mode (`space uq`): hide type hints, error badges, animations, breadcrumbs… — again to restore | on | `hide` |
| `rest` | remind you to take a break after 50 minutes of continuous work; `:Rest` — a break with a countdown | on | `work_min`, `break_min`, `show` |
| `minimap` | minimap on the right | **off** | `width` |
| `image_panel` | a side image, a different one per theme | **off** | `image`, `themes`, `side`, `width` |

## Code and languages

| module | what it does | default | settings |
|---|---|---|---|
| `lsp` | language servers, errors, navigation, rename, type hints | on | the `lsp`, `diagnostics`, `tools`, `auto` sections |
| `treesitter` | highlighting, indentation, folds; parsers install themselves | on | `languages`, `auto_install` |
| `completion` | completion (blink.cmp), snippets | on | the `completion` section |
| `format` | format on save (conform) | on | the `format` section |
| `lint` | linters beyond the server (nvim-lint) | on | the `lint` section |
| `editing` | bracket pairs, text objects, surround, flash jumps, TODO | on | — |
| `multicursor` | multiple cursors (`ctrl-n`, `space m`) | on | — |
| `dial` | `ctrl-a`/`ctrl-x` over your own word cycles | on | cycles per language |
| `yanky` | yank history (`space p`) | on | — |
| `commands` | your own script commands in any language | on | the `commands` section |
| `checks` | your own no-code checks: a command on an event, errors on the lines | on | the `checks` section |

## Go, tests, debugging

| module | what it does | default | settings |
|---|---|---|---|
| `go` | ▶ next to main and tests, generation, refactorings, "implements", coverage | on | the `go` section |
| `test` | tests (neotest): running, results, failed checks on their lines | on | the `test` section |
| `autotest` | Go tests in the background after saving, `✓ 42` in the status line, the "Тесты в фоне" panel (`space tv`); in Go | on | — |
| `debug` | debugger (nvim-dap + delve / codelldb), F-keys as in GoLand | on | the `debug` section |
| `http` | `.http` requests, Gin endpoints, `api.http` from the routes (in Go: `core/extensions/http`, `endpoints`) | on | — |
| `rust` | dependency versions in `Cargo.toml`, "Rust: build and debug" (`F9`), cargo tasks | on | — |

## DevOps and data

| module | what it does | default | settings |
|---|---|---|---|
| `docker` | live compose.yaml, Dockerfile layer sizes, `${VAR}` ↔ `.env` | on | `interval_ms`, `compose_status`, `layers`, `env_check` |
| `database` | databases (dadbod), project connection from `.env` | on | the `database` section |
| `tasks` | tasks (`space rr`) | on | the `tasks` section |
| `system` | containers (`alt-o`), GitHub (`alt-w`), code screenshot | on | `containers`, `github` |
| `kubernetes` | kubectl.nvim (`space k`) when `kubectl` is installed | on | — |
| `cloak` | secrets in `.env` masked with asterisks | on | — |

## Work

| module | what it does | default | settings |
|---|---|---|---|
| `basics` | yank highlight, cursor at its last place, `q` closes service windows | on | — |
| `picker` | file, text, command search (snacks) | on | — |
| `files` | yazi, project find-and-replace, structural replace | on | — |
| `git` | gutter changes, blame, diffview, history, lazygit | on | the `git` section |
| `ai` | Claude Code: panel, "fix the error", branch review | on | the `ai` section |
| `sessions` | project sessions | on | the `sessions` section |
| `autosave` | autosave, reloading external changes | on | — |
| `comfort` | `enter` — jump to a line by labels | on | — |
| `russian` | commands in the Russian layout | on | `langmap`, `alt_keys` |
| `learn` | motion hints, habit coach | on | `hints_visible`, `hardtime` |

Detailed settings of each module — the header comments of its file and the `modules` section of `defaults.jsonc`.
