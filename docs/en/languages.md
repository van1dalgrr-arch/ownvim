# Languages

[← Documentation](README.md)

- [Out of the box](#out-of-the-box)
- [Automatic installation](#automatic-installation) — any other language
- [Adding a language by hand](#adding-a-language-by-hand)
- [Language servers](#language-servers)
- [Inline errors](#inline-errors)
- [Formatting](#formatting) · [Linters](#linters)
- [Completion](#completion)
- [C / C++](#c--c) · [Rust](#rust)
- [Where programs come from](#where-programs-come-from)

## Out of the box

| language | server | formatting | linter |
|---|---|---|---|
| Go | gopls (staticcheck, gofumpt, type hints) | goimports + gofumpt | golangci-lint (with the project's `.golangci.yml`) |
| SQL (Postgres) | postgres_lsp | pg_format | — |
| Docker | docker_language_server (Dockerfile, compose) | — | hadolint |
| C / C++ | clangd (+ clang-tidy) | clang-format | — |
| CMake | neocmake | — | — |
| Python | basedpyright + ruff | ruff (imports and format) | — |
| Rust | rust_analyzer (clippy on save) | rustfmt | clippy |
| JSON · YAML | jsonls · yamlls | the server | — |
| shell · TOML | — | shfmt · taplo | — |

Highlighting, indentation and folds come from treesitter; any language's parser installs itself the first time you
open a file in it.

## Automatic installation

Open a file in a language nothing is configured for, and **ownvim enables and installs its server, formatter and
linter on its own**, without asking (VS Code only suggests installing an extension at that moment).

- **A curated set** of 24 languages where the right tools are known: TypeScript / JavaScript / React (vtsls +
  prettierd), Svelte, Astro, HTML, CSS / SCSS / Less, GraphQL, Markdown (marksman + prettierd), Lua (lua_ls + stylua),
  Bash (bashls + shfmt + shellcheck), TOML, Zig, PHP, Terraform, Protobuf (buf), XML, LaTeX, Helm, Nix.
- **Any other language** is looked up in the mason registry: if exactly one server fits, it installs; if several do,
  ownvim asks once. Servers "for everything" (spell checkers, ast-grep, security scanners) are never offered.
- **Not code** (text, logs, commits, csv) — nothing is installed.

```jsonc
"auto": {
  "enabled": true,
  "discover": true,                                          // search mason for languages outside the set
  "languages": {
    "typescript": { "lsp": ["vtsls"], "format": ["biome"] }, // your own choice
    "php": false,                                            // install nothing for this language
  },
},
```

`:AutoTools` — what got enabled automatically; `:AutoTools <language>` — forget a language (decide again next time a
file opens). Languages enabled this way form a separate settings layer below `settings.jsonc`, so yours always wins:
`"lsp": { "servers": { "vtsls": false } }` disables even what was enabled automatically.

> Some servers need the language itself: intelephense (PHP) needs Node; the Java, Kotlin, Ruby and Elixir servers need
> their toolchains. Without it, installation fails and ownvim tells you so.

## Adding a language by hand

For example, Zig with its own formatter:

```jsonc
"lsp": { "servers": { "zls": true } },
"format": { "languages": { "zig": ["zigfmt"] } },
"lint": { "languages": { "zig": [] } },
```

Names: servers — [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/tree/master/lsp), formatters —
[conform.nvim](https://github.com/stevearc/conform.nvim#formatters), linters —
[nvim-lint](https://github.com/mfussenegger/nvim-lint#available-linters). The programs install themselves the first
time you open a file in that language.

## Language servers

```jsonc
"lsp": {
  "servers": {
    "gopls": { "settings": { "gopls": { "staticcheck": true } } },  // your own settings
    "rust_analyzer": true,                                           // default settings
    "basedpyright": false,                                           // off
  },
  "inlay_hints": { "enabled": true, "exclude": [] },  // inline type hints; space uh — toggle
  "codelens": true,                                   // labels above code (go.mod: tidy, upgrade, govulncheck)
},
```

A server object is the same as `vim.lsp.config`: `cmd`, `filetypes`, `settings`, `init_options`, `root_markers`…
New `settings` reach the running server immediately, without a restart.

| key | what |
|---|---|
| `gd` / `gr` / `gI` / `gy` | definition / references / implementations / type |
| `K` | documentation under the cursor |
| `space ca` | fixes and code actions |
| `space cr` | rename |
| `space cl` | which servers are running |

## Inline errors

- **Error Lens** — the message as a neat badge to the right of the line; a long one wraps across lines.
- **Errors show while you type**, without leaving insert mode: the server sends them ~0.3 s after the last keystroke.
  Linters that read the file from disk (golangci-lint) report after saving.
- Every error in the project — the bottom panel, the "Problems" tab (`space jp`).

```jsonc
"diagnostics": { "virtual_text": false, "update_in_insert": true, "severity_sort": true },  // like vim.diagnostic.config
"modules": { "error_lens": { "preset": "modern", "insert": false } },  // hide badges while typing
```

## Formatting

On save (and autosave) and with `space cf`; `space uf` — turn it off for now, `space cF` — what formats this file.

```jsonc
"format": {
  "on_save": true,
  "lsp": "fallback",   // no formatters of its own — the server formats; never, prefer, first, last
  "languages": { "go": ["goimports", "gofumpt"], "sql": ["pg_format"] },
  "formatters": { "pg_format": { "prepend_args": ["--spaces", "2"] } },  // formatter settings, as in conform
},
```

## Linters

Checks beyond the server; their findings appear on the lines like server errors.

```jsonc
"lint": {
  "events": ["BufReadPost", "BufWritePost", "InsertLeave"],
  "languages": { "go": ["golangcilint"], "dockerfile": ["hadolint"] },
  "linters": { "golangcilint": { "ignore_exitcode": true } },  // as in nvim-lint
},
```

## Completion

A menu while typing, documentation on the side, argument hints, a grey inline continuation, snippets. The completion
plugin loads on your first keystroke in insert mode, not at startup.

```jsonc
"completion": {
  "keymap": "vscode",          // tab and enter accept; "enter", "super-tab", "default" (ctrl-y)
  "ghost_text": true,
  "sources": ["lsp", "path", "snippets", "buffer"],
  "friendly_snippets": true,   // ready-made snippets for every language; false — only your own
  "blink": {},                 // any blink.cmp settings as is
},
```

Your own snippets — `snippets/<language>.json` in VS Code format. Go already has `ife`, `errw`, `tt`, `bench`, `gh`…

## C / C++

clangd (completion, errors, clang-tidy, navigation; `space cs` — `.h` ↔ `.cpp`), clang-format on save (style from the
project's `.clang-format`, otherwise LLVM), a CMake server, the codelldb debugger (`F9` → "Run program" asks for the
binary path, or "Attach to process"), cmake / make / "build and run the current file" tasks (`space rr`). For clangd to
know the project flags it needs `compile_commands.json` — the "cmake: configure" task creates it.

## Rust

Rust itself is needed: `brew install rustup && rustup default stable` (rust-analyzer and clippy — `rustup component add rust-analyzer clippy`).
Then out of the box: rust-analyzer with clippy on save (parameter-name hints are off — they're noisy), rustfmt on save,
**`Cargo.toml`** — each dependency shows its latest crates.io version on the right, `K` — crate description, `space ca` —
bump the version, version and feature completion. Debugging — `F9` → **"Rust: собрать и отладить"** (build and debug):
`cargo build` and a codelldb launch, with the binary path taken from cargo's output (workspaces too). Tasks
(`space rr`): `cargo run`, `cargo test`, `cargo clippy`, `cargo build --release`.

## Where programs come from

```jsonc
"tools": { "install": "mason" },   // "system" — only what's already in PATH (brew etc.)
```

With `mason`, missing servers, formatters and linters install themselves into `~/.local/share/ownvim/mason` — the
first time a file of their language opens, not all at once. What's installed — `:Mason`. Rust tools come from rustup
(`brew install rustup && rustup default stable`).
