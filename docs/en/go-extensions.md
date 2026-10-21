# Go extensions

[← Documentation](README.md) · 🇷🇺 [Русский](../go-extensions.md)

Your own commands, keys and event handlers — **in Go, without a single line of Lua**. An extension is a plain Go
package in `core/extensions/<name>/`. Save the file, and ownvim rebuilds the core and picks up the change by itself —
no restart.

- [Your first extension in 5 minutes](#your-first-extension-in-5-minutes)
- [Why there's nothing to fear](#why-theres-nothing-to-fear)
- [What you can do: reference](#what-you-can-do-reference)
- [As a language server: completion, K, fixes](#as-a-language-server-completion-k-fixes)
- [Panels and the status line](#panels-and-the-status-line)
- [Recipes](#recipes)
- [Extension settings](#extension-settings)
- [Tests](#tests)
- [When it doesn't work](#when-it-doesnt-work)
- [How it works](#how-it-works)

## Your first extension in 5 minutes

1. In ownvim: **`:GoExtensionNew hello`** — creates `core/extensions/hello/hello.go` with a working template and
   comments.
2. Change what the command does. For example:
   ```go
   sdk.Command("Hello", "Say hello", func(c *sdk.Ctx) error {
   	c.Notify("hi! you're in %s, line %d, word «%s»", c.File, c.Line, c.Word)
   	return nil
   })
   sdk.Key("n <leader>xh", "Hello")
   ```
3. Save (`cmd-s`, or it saves itself). A couple of seconds later — a "Go core rebuilt" notification.
4. **`:Hello`** or **`space x h`**.

What the extensions declared — **`:GoExtensions`**. Ready examples — `core/extensions/examples/` (`:WordCount`,
`:SortLines`, `:LongFuncs`).

## Why there's nothing to fear

| what happened | what you get |
|---|---|
| a compile error | a highlight **on the line** of the Go file (like a linter) and a notification; the previous core keeps working |
| fixed and saved | the highlight goes away, the new version is picked up |
| the extension returned an error | a notification `Name: error text` |
| **a panic** (nil map, slice out of range…) | a notification with the cause and the **file:line** where it happened; the editor and the core stay alive |
| the extension takes a while (network, a big file) | the editor doesn't freeze: commands run in the background |
| forgot what `c` can do | `K` on `sdk.Ctx` or a method — a description with an example; gopls completes everything below |
| named the file `something_test.go` | `:GoExtensionNew` won't allow it: for Go that's a test file and isn't built |
| broke it completely | delete `core/extensions/<name>` and save any `.go` in `core/` — the extension is gone |

## What you can do: reference

### Registration (in `init()`)

| function | what |
|---|---|
| `sdk.Command(name, desc, func(c *sdk.Ctx) error)` | the `:name` command. Name — capital Latin letter first: `WordCount`. Works with a selection too (`:'<,'>Name`) |
| `sdk.Key("n <leader>xw", "Name")` | a key for the command: modes (`n` normal, `x` visual, `i` insert) and the key |
| `sdk.On("BufWritePost", "*.go", func(c *sdk.Ctx) error)` | react to an event; several — comma-separated: `"BufEnter,BufWritePost"` |

You can also bind a key from `settings.jsonc` without touching Go: `"keys": { "n <leader>xw": ":WordCount" }`.

### What's known (`c.…`)

| field | what |
|---|---|
| `c.File` · `c.Root` · `c.Filetype` | file path · project root · type (`go`, `yaml`…) |
| `c.Line` · `c.Col` · `c.Word` | cursor (from 1) · word under the cursor |
| `c.SelStart` · `c.SelEnd` | selected lines (from 1); `0` — no selection |
| `c.Event` · `c.Match` | for `On`: which event and on which file |
| `c.Buf` · `c.Ext` | buffer number · your extension's name |

### Text

| method | what |
|---|---|
| `c.Lines()` | every line of the file |
| `c.LinesRange(from, to)` | lines `from` to `to` (from 1, inclusive) |
| `c.CurrentLine()` | the line under the cursor |
| `c.Selection()` | the selection as one string (`""` — none) |
| `c.SetLines(from, to, lines)` | replace lines; the whole file — `SetLines(1, -1, …)` |
| `c.ReplaceSelection(text)` | replace the selection |
| `c.InsertBelow(text)` | insert below the cursor |

### Show

| method | what |
|---|---|
| `c.Notify(format, …)` · `c.Warn(…)` | a notification (like `fmt.Sprintf`) |
| `c.Marks([]sdk.Mark{{Line: 5, Text: "60 lines", Color: "red"}})` | labels to the right of lines (like the `compose.yaml` statuses); `nil` — clear |
| `c.Problems([]sdk.Problem{{Line: 3, Col: 5, Message: "…", Severity: "error"}})` | findings on lines like a linter: underline, Error Lens, "Problems" |
| `c.Window(title, text, ft)` | a window below with text (`q` — close); `ft` — highlighting: `"markdown"`, `"json"`, `"go"` |
| `c.ProblemsFor(path, problems)` | findings in **any** open file (a failed test in its own `_test.go`, even while you're in another one) |

Label colors: `red`, `orange`, `yellow`, `green`, `blue`, `purple`, `grey` — or any highlight group (`"Comment"`).
Each extension has its own labels and findings: new ones replace the previous ones of the same extension.

A label made of colored pieces — `sdk.Mark{Line: 2, Parts: []sdk.Part{{Text: "● running", Color: "green"}, {Text: " · :8080", Color: "grey"}}}`;
pin it to the right edge — `Right: true`.

### Ask the person

| method | what |
|---|---|
| `c.Select(prompt, items)` | pick from a list → index (from 0) and `true`; closed — `-1, false` |
| `c.Input(prompt, def)` | enter a string → text and `true` |
| `c.Pick(title, []sdk.PickItem, opts)` | a searchable list with a **file preview** (like `space space`): `enter` — go to `File:Line` (with `Definition: true` — and on to the definition via LSP), `ctrl-y` — copy `Copy`, your own keys in `opts.Keys` — return their name |

The extension waits for the answer in the background — the editor keeps working.

### Windows and keys

| method | what |
|---|---|
| `c.SidePanel(title, text, ft)` · `c.CloseSidePanel()` | a right-side panel, one per extension: if open, it's redrawn (HTTP responses) |
| `c.Terminal(cmd, cwd)` | a command in a terminal below: logs, a shell, a build |
| `c.MapKey("n", "<cr>", desc, func)` | a key **only in this file**; return `sdk.ErrPass` and the key works as usual (that's how `enter` on a compose service opens a menu but works normally on other lines) |
| `c.SetCursor(line, col)` · `c.Feed("A")` · `c.Clipboard(text)` | cursor · "press" keys after everything else · clipboard |

### Background, data, storage

| what | how |
|---|---|
| a background task | `sdk.Every(3*time.Second, func(c) …)`; what's on screen — `c.VisibleBuffers()`, work with a buffer — `c.ForBuffer(b)` |
| data for a Lua UI | `sdk.Func("name", …)` — Lua calls `require("own.ext").call("name", { … })` (arguments in `c.Args`); the answer — `c.Publish(key, value)` → `require("own.ext").data[key]` and a `User OwnExtData` event |
| remember across restarts | `c.Store().Set("key", value)` · `c.Store().Get("key", &out)` |

### Act

| method | what |
|---|---|
| `c.Open(file, line)` | open a file at a line |
| `c.Command("write")` | any Vim command |
| `c.Setting(key, def)` · `c.SettingInt(key, def)` | the extension's setting from `settings.jsonc` ([below](#extension-settings)) |
| `c.Nvim()` | the full Neovim client ([go-client](https://pkg.go.dev/github.com/neovim/go-client/nvim)) — for everything else |

Plus the whole Go standard library: `os/exec`, `net/http`, `go/ast`, `encoding/json`, `regexp`… — and any package
(`cd core && go get …`).

## As a language server: completion, K, fixes

An extension can become a **built-in language server**: its suggestions show up in the regular completion menu, its
description on `K`, its fixes in `space ca`, next to gopls and rust-analyzer. Nothing to wire up: ownvim attaches the
"ownvim" server to files of the types that have providers.

```go
// completion: after "${" in compose.yaml — variables from .env
sdk.Completion("yaml", "${", func(c *sdk.Ctx, prefix string) []sdk.CompletionItem {
	return []sdk.CompletionItem{{Label: "DB_URL", Detail: "postgres://…", Kind: "variable", Doc: "from `.env`"}}
})

// K — markdown; "" — nothing to say (let the other servers speak)
sdk.Hover("yaml", func(c *sdk.Ctx) string {
	return "**" + c.Word + "** — from `.env`, line 3"
})

// space ca — fixes for the cursor line
sdk.CodeActions("yaml", func(c *sdk.Ctx) []sdk.Action {
	return []sdk.Action{{Title: "Add to .env", Run: func(c *sdk.Ctx) error { /* … */ return nil }}}
})
```

| what | fields |
|---|---|
| `CompletionItem` | `Label`, `Insert` (what to insert; `Snipp: true` — a snippet `${1:name}`), `Detail`, `Doc` (markdown), `Kind` (`function`, `variable`, `field`, `keyword`, `snippet`…) |
| `Action` | `Title`, `Kind` (`quickfix`, `refactor`, `source`), `Run` — what to do when chosen |

File types are comma-separated (`"go,gomod"`), `"*"` — all. The full example is `core/extensions/docker/providers.go`:
`${VAR}` completion from `.env` (secrets masked), `K` — the variable's value and where it comes from, `space ca` — add
it to `.env` or set a default.

## Panels and the status line

A **panel** is a side or bottom window with rows, like "Tests" or "Structure" in an IDE:

```go
sdk.View("todo", sdk.ViewSpec{
	Title: "Project TODO",
	Side:  "right", // left, bottom
	Rows: func(c *sdk.Ctx) []sdk.Row {
		return []sdk.Row{
			{Parts: []sdk.Part{{Text: "✗ ", Color: "red"}, {Text: "fix login"}}, File: "/path/auth.go", Line: 42},
			{Depth: 1, Text: "details…"},
		}
	},
	Keys: map[string]sdk.RowKey{
		"d": {Desc: "done", Run: func(c *sdk.Ctx, row sdk.Row) error { /* … */ return c.RefreshView("todo") }},
	},
})
sdk.Command("Todo", "TODO panel", func(c *sdk.Ctx) error { return c.ToggleView("todo") })
```

In a panel: `enter` — go to `File:Line`, your own keys from `Keys`, `R` — refresh, `q` — close; the key hints are in its
title. Open it with `c.ShowView` / `c.ToggleView` or `:View name`; refresh it if open — `c.RefreshView`. A custom
`enter` — `Open: func(c, row) (bool, error)`.

**The status line** — `c.SetStatus("✓ 42", "green", "go")`: a label in the `ext` block, only while a file of those
types is open (`""` — always); `c.SetStatus("", "", "")` — remove it.

An example with both is `core/extensions/autotest`: background tests, the "Тесты в фоне" panel (`space tv`) with
packages and tests (`enter` — to the test function, located with `go/ast`; `r` — rerun the package), `✓ 42 / ✗ 1` in the
status line, failed checks in their own `_test.go` via `ProblemsFor`.

## Recipes

**Replace the selection** — base64, JSON → one line, anything:

```go
sdk.Command("B64", "Selection to base64", func(c *sdk.Ctx) error {
	return c.ReplaceSelection(base64.StdEncoding.EncodeToString([]byte(c.Selection())))
})
sdk.Key("x <leader>xb", "B64")
```

**A check on save** — findings on lines, like a linter:

```go
sdk.On("BufWritePost", "*.go", func(c *sdk.Ctx) error {
	var ps []sdk.Problem
	for i, line := range c.Lines() {
		if strings.Contains(line, "fmt.Println(") {
			ps = append(ps, sdk.Problem{Line: i + 1, Message: "debug Println — remove before committing", Severity: "warn"})
		}
	}
	return c.Problems(ps)
})
```

**Run a program and show its output:**

```go
sdk.Command("GitLog", "Recent commits of the file", func(c *sdk.Ctx) error {
	out, err := exec.Command("git", "-C", c.Root, "log", "--oneline", "-15", "--", c.File).CombinedOutput()
	if err != nil {
		return fmt.Errorf("git: %s", out)
	}
	return c.Window("git log "+filepath.Base(c.File), string(out), "git")
})
```

**Call the network** (the editor won't freeze):

```go
sdk.Command("Health", "GET /health", func(c *sdk.Ctx) error {
	resp, err := http.Get("http://localhost:8080/health")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	c.Notify("health: %s", resp.Status)
	return nil
})
```

**Parse Go code with the real parser** — `go/ast`: see `:LongFuncs` in `core/extensions/examples/examples.go`.

**Big real examples** — ownvim's built-in modules are written on this same SDK; read them as a model:

| extension | what it shows |
|---|---|
| `core/extensions/docker` | events, background polling (`Every`), multicolor labels, findings, `MapKey` + `ErrPass`, `Select`, `Terminal`, `Store`, `Func`/`Publish` for the start screen, YAML parsing with line numbers |
| `core/extensions/endpoints` | project-wide `go/ast` parsing, `Pick` with preview and go-to-definition, `Input`, `SidePanel`, HTTP |
| `core/extensions/http` | buffer-local keys, `.http` format parsing, `net/http`, responses kept across restarts (`Store`), `Clipboard`, `SetCursor` |
| `core/extensions/autotest` | a panel (`View`), the status line (`SetStatus`), findings in other files (`ProblemsFor`), cancelling stale runs |
| `core/extensions/checks` | `Func` for a Lua module, running commands, parsing output with regular expressions |

## Extension settings

```jsonc
// settings.jsonc
"extensions": {
  "examples": { "max_lines": 60 },
  "hello": { "greeting": "hey" },
},
```

```go
greeting := c.Setting("greeting", "hi").(string)
limit := c.SettingInt("max_lines", 40)
```

The key is the extension's folder name. Save `settings.jsonc` and the next run of the command sees the new value.

## Tests

An extension is plain Go: move the logic into a function without `sdk.Ctx` and check it with `go test`:

```go
// core/extensions/hello/hello_test.go
func TestGreet(t *testing.T) {
	if got := greet("world"); got != "hi, world" {
		t.Fatalf("got %q", got)
	}
}
```

```bash
cd ~/dev/ownvim/core && go test ./...
```

## When it doesn't work

| symptom | what to do |
|---|---|
| no command after saving | a build error — see the highlight in the Go file and `:OwnHealth`; `:GoExtensions` — what ownvim sees |
| "нет go" (no go) | `brew install go` |
| the command name was rejected | capital Latin letter first, no spaces or underscores: `WordCount` (a notification on build tells you) |
| the command does nothing | put `c.Notify(…)` at the start to check it's called; bridge logs — `~/.local/state/ownvim/ownvimd.log` |
| you need something `c` doesn't have | `c.Nvim()` — the full Neovim API; or ask to add a method to `core/sdk` |

## How it works

- `core/sdk` — what you use: registration (`sdk.go`), the context and its methods (`ctx.go`), background execution with
  panic recovery (`run.go`).
- `core/extensions/all.go` — the list of extensions; ownvim writes it before every build (every `core/extensions/*` folder).
- At startup ownvim reads the **manifest** (what extensions declared) from a cache and creates commands, keys and
  events without starting Go. Triggering is a `vim.rpcnotify` into the bridge (`ownvimd serve`), which starts on the
  first call (~3 ms).
- The `c.…` methods call back small Lua functions in `lua/own/ext.lua` (`M.api`) — all the "Neovim magic" lives there,
  and the Go API stays simple.
- More on the core — [Architecture → Go core and bridge](architecture.md#go-core-and-bridge).
