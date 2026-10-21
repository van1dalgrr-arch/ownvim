# Go

[← Documentation](README.md)

Go is ownvim's main language; the ideas come from GoLand.

- [Run: ▶ next to main and tests](#run--next-to-main-and-tests)
- [Tests](#tests) · [in the background](#background-tests) · [coverage](#coverage)
- [Debugger](#debugger)
- [Navigation and refactoring](#navigation-and-refactoring)
- [Code generation](#code-generation)
- [HTTP: endpoints and `.http` requests](#http-endpoints-and-http-requests)
- [Settings](#settings)

Out of the box: gopls (staticcheck, gofumpt, the `nilness`, `shadow`, `unusedparams`… analyses, type hints),
goimports + gofumpt formatting on save, golangci-lint with the project's `.golangci.yml`. More — [Languages](languages.md).

## Run: ▶ next to main and tests

A ▶ sign appears to the left of `func main`, `TestX`, `BenchmarkX`, `FuzzX`, `ExampleX`, as in GoLand.

| key | what |
|---|---|
| `space rx` | run the function under the cursor: a test via neotest (✓/✗ next to it), `main` in a terminal below |
| `space rX` | the same under the debugger (delve) |
| `space rg` | a Go scratchpad: an empty `main.go` in a temporary folder |
| `space rr` / `alt-t` | tasks: `go run`, air, gotestsum, golangci-lint, govulncheck, pprof… ([Tasks](devops.md#tasks)) |

## Tests

| key | what |
|---|---|
| `space tr` | test under the cursor |
| `space tt` / `tT` | tests in the file / the whole project |
| `space tl` | rerun the last one |
| `space td` | test under the cursor in the debugger |
| `space to` / `tO` | test output / output panel |
| `space ts` | test tree |
| `space tw` | rerun on save |

Results appear as signs next to the tests. A failed check (`t.Errorf`) becomes an error on its line in `_test.go`.

```jsonc
"test": {
  "adapters": {
    "neotest-golang": { "go_test_args": ["-v", "-race", "-count=1", "-timeout=60s"] },
    "neotest-python": true,
  },
  "failed_as_error": true,   // messages of a failed Go test become errors, not hints
},
```

### Background tests

Save a Go file and a second later `go test` runs for its package (from the cache — instantly). The status line shows
`✓ 42` / `✗ 1` / `✗ build`, and the failed check is highlighted on its line — visible before you commit. `space tA` — toggle.

### Coverage

`space Gv` — run the tests and show coverage right in the code, `space GV` — hide/show, `space Gs` — percentages per file.

## Debugger

nvim-dap + delve. Keys as in GoLand (on a Mac, F-keys via `fn`):

| key | what |
|---|---|
| `F9` | run / continue |
| `F8` / `F7` / `shift-F8` | step over / into / out |
| `ctrl-F8` | breakpoint (`space dB` — conditional) |
| `space dC` | run to cursor |
| `space de` | evaluate expression |
| `space du` | debugger panels |
| `space dt` | stop |

Breakpoints survive restarts, the variables and stack panels open by themselves, and variable values appear in grey
right in the code.

There is a default configuration **"Attach to dlv in Docker (:2345)"**: run
`dlv debug ./cmd/api --headless --listen=:2345 --accept-multiclient --api-version=2` in the container (port 2345
exposed, code in `/app`), and ownvim attaches, mapping the paths. Your own configurations — as in nvim-dap-go:

```jsonc
"debug": {
  "go": {
    "configurations": [
      { "type": "go", "name": "API locally", "request": "launch", "program": "./cmd/api" }
    ]
  }
},
```

## Navigation and refactoring

| key | what |
|---|---|
| `gd` / `gr` / `gI` / `gy` | definition / references / implementations / type |
| `gpd` / `gpr` / `gpi` / `gpt` | the same, but peek in a window without leaving your place |
| `space ch` / `cH` | incoming / outgoing calls |
| `space ca` | code actions with a preview |
| `space cx` | extract a function, variable, constant |
| `space ci` | inline a call or variable |
| `space cw` | rewrite: fill struct, if ↔ else, parameters… |
| `space cr` / `shift-F6` | rename |

Next to types: "implements: io.Reader, fmt.Stringer".

## Code generation

All under `space G`:

| key | what |
|---|---|
| `space Gj` / `Gy` / `Gd` / `Gt` / `Gr` | `json` / `yaml` / `db` / custom tags / remove tags |
| `space Gi` | implement an interface (cursor on the type) |
| `space Ge` | `if err != nil { return … }` with the right zero values |
| `space Gc` | doc comment |
| `space Gf` / `GF` | a test for the function under the cursor / for every function in the file |
| `space Gp` | JSON → Go struct |
| `space Gm` / `Gg` | `go mod tidy` / `go get` a package |
| `space Go` | compiler optimizations: what escapes to the heap, what got inlined |

Snippets: `ife`, `errw`, `tt` (table test), `bench`, `gh` (Gin handler) and more.

## HTTP: endpoints and `.http` requests

- **`space re` / `alt-a`** (`:Endpoints`) — every Gin route with its full path, like GoLand's Endpoints window: `enter` —
  to the handler's definition, `ctrl-r` — send a request to the running API (the token from the login response is
  remembered), `ctrl-y` — copy as curl. The code is parsed with the real parser (`go/ast`), without running it: chained
  groups (`api.Group("/v1").Group("/users")`) and groups passed into other functions (`registerUsers(v1.Group("/users"))`).
- **`space rh` / `alt-p`** — the project's `api.http`, generated from the routes.
- **`.http` files** — Postman in a file, in the VS Code REST Client / JetBrains HTTP Client format: `enter` on a
  request sends it, the response opens in a panel on the right (`esc` — close); `space Rc` — copy as curl. Variables (`@host = …` → `{{host}}`) and
  responses of earlier requests (`{{login.response.body.$.access_token}}`).

```http
@host = http://localhost:8080

### Log in
# @name login
POST {{host}}/auth/login
Content-Type: application/json

{ "email": "a@b.c", "password": "secret" }

### Profile
GET {{host}}/me
Authorization: Bearer {{login.response.body.$.access_token}}
```

## Settings

```jsonc
"go": {
  "run_marks": true,                 // ▶ next to main and tests
  "implements": true,                // "implements: …" next to types
  "coverage_file": "/tmp/cover.out",
},
"lsp": { "servers": { "gopls": { "settings": { "gopls": { "gofumpt": true, "staticcheck": true } } } } },
```
