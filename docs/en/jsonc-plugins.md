# JSONC plugins — no code

[← Documentation](README.md) · 🇷🇺 [Русский](../jsonc-plugins.md)

A bundle is a file `extensions/<name>.jsonc` with the same sections as `settings.jsonc`: keys, tasks, checks, commands,
status line blocks, language servers… Bundles are layered **between the defaults and your `settings.jsonc`** (which
always wins). They're easy to share: "everything for Go backends", "my keys", "a Kubernetes kit" — one file.

- [Your first bundle in a minute](#your-first-bundle-in-a-minute)
- [What a bundle can contain](#what-a-bundle-can-contain)
- [Lists: append instead of replace](#lists-append-instead-of-replace)
- [Checks: your own linter in three lines](#checks-your-own-linter-in-three-lines)
- [Example: a Go backend bundle](#example-a-go-backend-bundle)
- [When it doesn't work](#when-it-doesnt-work)

## Your first bundle in a minute

1. `:PluginNew my-bundle` — creates `extensions/my-bundle.jsonc` with every section explained in a comment with an example.
2. Uncomment what you need (`gcc` on a line), save — **it applies immediately**, no restart.
3. To turn a bundle off without deleting it — `"enabled": false`.

```jsonc
{
  "name": "my-bundle",
  "description": "what it does",
  "keys": { "n <leader>xg": ":Git status" },
  "checks": { "go vet": { "run": "go vet ./...", "pattern": "*.go" } },
}
```

## What a bundle can contain

Any `settings.jsonc` section ([reference](configuration.md#section-reference)). Most often:

| section | what | example |
|---|---|---|
| `keys` | keys | `"n <leader>xg": ":Git status"` |
| `tasks` | tasks (`space rr`) | `"list+": [{ "name": "server", "cmd": "go run ./cmd/api", "when": ["go.mod"] }]` |
| `checks` | your own checks — errors on lines | below |
| `commands` | script commands in any language ([how](extensions.md)) | `"UUID": { "run": "uuidgen", "input": "none", "output": "insert" }` |
| `statusline` | a status line block from a command's output | `"custom": { "k8s": { "shell": "kubectl config current-context", "every_ms": 10000 } }`, `"right+": ["k8s"]` |
| `lsp` · `format` · `lint` | language servers, formatters, linters | `"lsp": { "servers": { "zls": true } }` |
| `modules` | turn on and configure modules | `"modules": { "minimap": true }` |
| `extensions` | Go extension settings | `"extensions": { "examples": { "max_lines": 60 } }` |

Bundle meta fields: `name`, `description`, `enabled`. A mistake in a bundle (JSON, an unknown section) is highlighted
on its line; a broken bundle is skipped and the others keep working.

## Lists: append instead of replace

Lists are replaced as a whole when merging: `"tasks": { "list": [ … ] }` removes every default task. To **append**,
put `+` after the key name:

```jsonc
"tasks": { "list+": [{ "name": "migrations", "cmd": "migrate up", "when": ["migrations"] }] },
"statusline": { "right+": ["k8s"] },
```

This works everywhere — in bundles and in `settings.jsonc`.

## Checks: your own linter in three lines

The `checks` section: a command runs on an event (save by default), and its `file:line:column: text` output becomes
findings on the lines — underline, Error Lens, "Problems" in the bottom panel. Almost any tool with that output format
plugs in this way.

```jsonc
"checks": {
  "go vet": { "run": "go vet ./...", "pattern": "*.go" },
  "shellcheck": { "run": "shellcheck -f gcc ${file}", "pattern": "*.sh,*.bash" },
  "eslint": { "run": "npx eslint -f unix ${file}", "pattern": "*.ts,*.tsx" },
  "todo with an owner": {
    "run": "rg -n --no-heading 'TODO\\(\\w+\\)' ${file}",
    "format": "^(?P<file>[^:]+):(?P<line>\\d+):(?P<message>.*)$",
    "severity": "info"
  },
}
```

| field | what | default |
|---|---|---|
| `run` | the command; `${file}`, `${root}`, `${file_dir}` are substituted | — |
| `pattern` | which files (comma-separated) | `*` |
| `on` | events | `["BufWritePost"]` |
| `cwd` | where to run: `root` — project root, `file` — the file's folder | `root` |
| `severity` | finding level: `error`, `warn`, `info`, `hint` | `warn` (or from the output: `error:` / `warning:`) |
| `format` | a regular expression with `file`, `line`, `message` groups (and `col`, `severity`) | `file:line[:col]: [error:] text` |
| `enabled` | `false` — off | — |

`:Checks` — run the current file's checks now. Each check sets its own findings and removes its old ones when they're
gone. A slow check doesn't get in the way: everything runs in the background, and a new run cancels a stale one.

## Example: a Go backend bundle

```jsonc
// extensions/go-backend.jsonc
{
  "name": "go-backend",
  "description": "migrations, swag, vet on save, k8s context in the status line",
  "checks": {
    "go vet": { "run": "go vet ./...", "pattern": "*.go" },
  },
  "tasks": {
    "list+": [
      { "name": "migrate up", "cmd": "migrate -path migrations -database $DATABASE_URL up", "when": ["migrations"] },
      { "name": "swag init", "cmd": "swag init -g cmd/api/main.go", "when": ["go.mod"] },
    ],
  },
  "keys": {
    "n <leader>xm": ":OverseerRun",
  },
  "statusline": {
    "custom": { "k8s": { "shell": "kubectl config current-context", "every_ms": 15000, "icon": "⎈", "color": "pink" } },
    "right+": ["k8s"],
  },
}
```

## When it doesn't work

| symptom | what to do |
|---|---|
| the bundle didn't apply | open it: the error is highlighted on its line; `"enabled": false`? |
| a check is silent | `:Checks` — run it now; run `run` in a terminal — is the output `file:line: text`? if not, set your own `format` |
| "нет программы" (no program) | install the tool (`brew install shellcheck`…) |
| a bundle overrode my setting | it can't: `settings.jsonc` beats every bundle |

Need more than JSONC can do (your own logic, completion, panels)? — [Go extensions](go-extensions.md).
