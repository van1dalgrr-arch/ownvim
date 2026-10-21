# Языки

[← Документация](README.md)

- [Что есть из коробки](#что-есть-из-коробки)
- [Автоустановка](#автоустановка) — любой другой язык
- [Добавить язык вручную](#добавить-язык-вручную)
- [Языковые серверы](#языковые-серверы)
- [Ошибки на строках](#ошибки-на-строках)
- [Форматирование](#форматирование) · [Линтеры](#линтеры)
- [Автодополнение](#автодополнение)
- [C / C++](#c--c) · [Rust](#rust)
- [Откуда ставятся программы](#откуда-ставятся-программы)

## Что есть из коробки

| язык | сервер | форматирование | линтер |
|---|---|---|---|
| Go | gopls (staticcheck, gofumpt, подсказки типов) | goimports + gofumpt | golangci-lint (с `.golangci.yml` проекта) |
| SQL (Postgres) | postgres_lsp | pg_format | — |
| Docker | docker_language_server (Dockerfile, compose) | — | hadolint |
| C / C++ | clangd (+ clang-tidy) | clang-format | — |
| CMake | neocmake | — | — |
| Python | basedpyright + ruff | ruff (импорты и формат) | — |
| Rust | rust_analyzer (clippy при сохранении) | rustfmt | clippy |
| JSON · YAML | jsonls · yamlls | сервер | — |
| shell · TOML | — | shfmt · taplo | — |

Подсветка, отступы и складки — treesitter; парсер любого языка ставится сам при первом открытии файла.

## Автоустановка

Открыли файл языка, для которого ничего не настроено, — **ownvim сам включает сервер, форматтер и линтер и ставит
их**, ничего не спрашивая (VS Code в этот момент только предлагает поставить расширение).

- **Проверенный набор** — 24 языка, для которых известно, что ставить: TypeScript / JavaScript / React (vtsls +
  prettierd), Svelte, Astro, HTML, CSS / SCSS / Less, GraphQL, Markdown (marksman + prettierd), Lua (lua_ls + stylua),
  Bash (bashls + shfmt + shellcheck), TOML, Zig, PHP, Terraform, Protobuf (buf), XML, LaTeX, Helm, Nix.
- **Любой другой язык** ищется в реестре mason: один подходящий сервер — ставится сам; несколько — ownvim один раз
  спросит, какой. Серверы «для всего сразу» (орфография, ast-grep, сканеры безопасности) не предлагаются.
- **Не код** (текст, логи, коммиты, csv) — ничего не ставится.

```jsonc
"auto": {
  "enabled": true,
  "discover": true,                                          // искать в mason языки не из набора
  "languages": {
    "typescript": { "lsp": ["vtsls"], "format": ["biome"] }, // свой выбор
    "php": false,                                            // для этого языка ничего не ставить
  },
},
```

`:AutoTools` — что включилось само, `:AutoTools <язык>` — забыть язык (при следующем открытии решить заново).
Включённые так языки — отдельный слой настроек под `settings.jsonc`, поэтому ваше всегда главнее:
`"lsp": { "servers": { "vtsls": false } }` выключит даже то, что включилось само.

> Часть серверов требует сам язык: intelephense (PHP) — Node, серверы Java, Kotlin, Ruby, Elixir — их тулчейн.
> Если его нет, установка не пройдёт, и ownvim скажет об этом.

## Добавить язык вручную

Например, Zig со своим форматтером:

```jsonc
"lsp": { "servers": { "zls": true } },
"format": { "languages": { "zig": ["zigfmt"] } },
"lint": { "languages": { "zig": [] } },
```

Имена: серверы — [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/tree/master/lsp), форматтеры —
[conform.nvim](https://github.com/stevearc/conform.nvim#formatters), линтеры —
[nvim-lint](https://github.com/mfussenegger/nvim-lint#available-linters). Программы поставятся сами при первом
открытии файла этого языка.

## Языковые серверы

```jsonc
"lsp": {
  "servers": {
    "gopls": { "settings": { "gopls": { "staticcheck": true } } },  // свои настройки
    "rust_analyzer": true,                                           // с настройками по умолчанию
    "basedpyright": false,                                           // выключить
  },
  "inlay_hints": { "enabled": true, "exclude": [] },  // подсказки типов в строке; пробел uh — выкл
  "codelens": true,                                   // надписи над кодом (go.mod: tidy, обновить, govulncheck)
},
```

Объект сервера — как `vim.lsp.config`: `cmd`, `filetypes`, `settings`, `init_options`, `root_markers`…
Новые `settings` уходят в работающий сервер сразу, без перезапуска.

| клавиша | что |
|---|---|
| `gd` / `gr` / `gI` / `gy` | определение / использования / реализации / тип |
| `K` | описание под курсором |
| `пробел ca` | исправления и действия с кодом |
| `пробел cr` | переименовать |
| `пробел cl` | какие серверы работают |

## Ошибки на строках

- **Error Lens** — сообщение аккуратной плашкой справа от строки, длинное — в несколько строк.
- **Ошибки видны прямо во время набора**, без выхода из вставки: сервер присылает их через ~0,3 с после последней
  клавиши. Линтеры (golangci-lint), которые читают файл с диска, — после сохранения.
- Все ошибки проекта — нижняя панель, вкладка «Проблемы» (`пробел jp`).

```jsonc
"diagnostics": { "virtual_text": false, "update_in_insert": true, "severity_sort": true },  // как vim.diagnostic.config
"modules": { "error_lens": { "preset": "modern", "insert": false } },  // не показывать плашки во время набора
```

## Форматирование

При сохранении (и автосохранении) и по `пробел cf`; `пробел uf` — выключить на время, `пробел cF` — чем
форматируется этот файл.

```jsonc
"format": {
  "on_save": true,
  "lsp": "fallback",   // нет своих форматтеров — форматирует сервер; never, prefer, first, last
  "languages": { "go": ["goimports", "gofumpt"], "sql": ["pg_format"] },
  "formatters": { "pg_format": { "prepend_args": ["--spaces", "2"] } },  // настройки форматтера, как в conform
},
```

## Линтеры

Проверки сверх сервера, их замечания — на строках, как ошибки сервера.

```jsonc
"lint": {
  "events": ["BufReadPost", "BufWritePost", "InsertLeave"],
  "languages": { "go": ["golangcilint"], "dockerfile": ["hadolint"] },
  "linters": { "golangcilint": { "ignore_exitcode": true } },  // как в nvim-lint
},
```

## Автодополнение

Меню при наборе, описание справа, подсказка аргументов, серое продолжение в строке, сниппеты.

```jsonc
"completion": {
  "keymap": "vscode",          // tab и enter — принять; "enter", "super-tab", "default" (ctrl-y)
  "ghost_text": true,
  "sources": ["lsp", "path", "snippets", "buffer"],
  "friendly_snippets": true,   // готовые сниппеты для всех языков; false — только свои
  "blink": {},                 // любые настройки blink.cmp как есть
},
```

Свои сниппеты — `snippets/<язык>.json` в формате VS Code. Для Go уже есть `ife`, `errw`, `tt`, `bench`, `gh`…

## C / C++

clangd (дополнение, ошибки, clang-tidy, переходы; `пробел cs` — `.h` ↔ `.cpp`), clang-format при сохранении
(стиль — `.clang-format` проекта, иначе LLVM), CMake-сервер, отладчик codelldb (`F9` → «Запустить программу»
спросит путь к бинарнику, или «Подключиться к процессу»), задачи cmake / make / «собрать и запустить текущий файл»
(`пробел rr`). Чтобы clangd знал флаги проекта, нужен `compile_commands.json` — его делает задача
«cmake: настроить».

## Rust

Нужен сам Rust: `brew install rustup && rustup default stable` (rust-analyzer и clippy — `rustup component add rust-analyzer clippy`).
Дальше из коробки: rust-analyzer с clippy при сохранении (подсказки имён параметров выключены — шумят), rustfmt при
сохранении, **`Cargo.toml`** — справа от зависимости её последняя версия с crates.io, `K` — описание крейта, `пробел ca` —
обновить версию, дополнение версий и фич. Отладка — `F9` → **«Rust: собрать и отладить»**: `cargo build` и запуск под
codelldb, путь к бинарнику ownvim берёт из вывода cargo (работает и в workspace). Задачи (`пробел rr`): `cargo run`,
`cargo test`, `cargo clippy`, `cargo build --release`.

## Откуда ставятся программы

```jsonc
"tools": { "install": "mason" },   // "system" — только то, что уже есть в PATH (brew и т.п.)
```

С `mason` недостающие серверы, форматтеры и линтеры ставятся сами в `~/.local/share/ownvim/mason` — при первом
открытии файла их языка, а не все сразу. Что поставлено — `:Mason`. Rust-тулзы берутся из rustup
(`brew install rustup && rustup default stable`).
