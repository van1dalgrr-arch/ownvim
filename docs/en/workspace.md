# Workspace

[← Documentation](README.md)

ownvim lays out the screen like an IDE: every window has its place, and the layout doesn't fall apart however many
panels you open. Open a project and everything is where you left it.

- [The screen](#the-screen)
- [Modes](#modes)
- [Run and debug](#run-and-debug)
- [Search everywhere](#search-everywhere)
- [Settings](#settings)

## The screen

```
┌─ 󰉋 󰙅 󰙨  ──────┬─ main.go  user.go ──────────────────────── 󰙨 Tests │  api ▾  ▶  󰃤 ─┐
│ PROJECT         │ cmd › api › main.go                                                    │
│ ▾ cmd           │   1  package main                                                      │
│   ▾ api         │   …                                                                    │
│      main.go    ├────────────────────────────────────────────────────────────────────────┤
│ ▸ internal      │  Terminal   api   Problems 2   Tasks   Test output                     │
│                 │ listening on :9090                                                     │
└─────────────────┴────────────────────────────────────────────────────────────────────────┘
```

- **Left** — one view at a time: **Project** (file tree), **Structure** (the file's symbols), **Tests**, **Database**.
  The switcher is the icons above the panel, in the tab line: click to open, click the open one to hide it.
- **Bottom** — also one view at a time: **Terminal**, **Run** (output of the running configuration), **Problems**
  (errors in the whole project, `enter` jumps to the line), **Tasks**, **Test output**. The tabs are in the panel
  header and are clickable.
- **Top right** — what is being run, and the mode if it isn't "Code".

Side panels are a shade darker than the code so your eye doesn't snag on them. Sizes are fixed: help, a list or a
terminal never push the tree around or land in the middle. Close the last file and ownvim closes instead of staying
open with just the tree.

| key | what |
|---|---|
| `space e` | project tree (again — hide) |
| `space co` | file structure |
| `space ts` | test tree |
| `space D` | database |
| `space 0` | hide / bring back the whole left panel |
| `space j` | hide / bring back the whole bottom panel |
| `space jt` · `jr` · `jp` · `jo` · `jT` | terminal · run · problems · tasks · test output |
| `space cu` / `alt-F7` | **usages** of the symbol under the cursor — a list by file at the bottom, like Find Usages in GoLand |
| `space cU` · `space cM` | who calls the function · interface implementations (same place) |
| `ctrl-/` | terminal at the bottom (again — hide; the process keeps running) |
| `q` | in any panel — close it |

**The layout is remembered per project:** which view was on the left, which at the bottom, which mode you were in. A
new project opens with the tree on the left (configurable).

## Modes

One key — a screen for the job:

| key | mode | what's on screen |
|---|---|---|
| `space 1` | **Code** | whatever was open before the other mode |
| `space 2` | **Tests** | the test tree on the left (`space tr` — test under the cursor, `space tt` — the file) |
| `space 3` | **Debug** | variables, stack, breakpoints, console; other panels are put away |
| `space 4` | **Git** | every change on the branch: file list and diff (diffview) |
| `space 5` | **Database** | connections and tables on the left |

The same key again goes back to "Code" and everything returns as it was. `:Mode test` does the same as a command.

## Run and debug

Top right in the tab line is the **run configuration**, as in GoLand: `  api ▾  ▶  󰃤`. ownvim finds them itself:

- **Go** — every `package main` (`./cmd/api`, `./cmd/worker`, the root); the project's `.env` is picked up automatically;
- **Rust** — `cargo run`; **compose** — `docker compose up`; **package.json** — `npm run dev` / `start`;
- **tasks** from the `tasks` section that don't ask anything when they start;
- **your own** — the `run` section (below).

| key | what |
|---|---|
| `space rr` | ▶ run (already running — restart) |
| `space rd` | run under the debugger (Go — delve, Rust — codelldb); the screen switches to "Debug" mode |
| `space rs` | ■ stop |
| `space rc` | choose a configuration (or click its name at the top right) |
| `space rx` / `rX` | run / debug the **function under the cursor** (`main`, `TestX`) — like ▶ in the gutter |
| `space rt` | tasks (the whole list, with prompts) |

Output goes to the "Run" tab of the bottom panel; the cursor stays in the code. The chosen configuration is remembered
per project.

Your own configurations go in `settings.jsonc`:

```jsonc
"run": {
  "configs": [
    { "name": "api :8080", "cmd": "go run ./cmd/api -port 8080", "env": ".env" },
    { "name": "web", "cmd": "npm run dev", "cwd": "web" },
    { "name": "api (debug with flags)", "cmd": "go run ./cmd/api",
      "debug": { "type": "go", "request": "launch", "program": "${workspaceFolder}/cmd/api", "args": ["-port", "8080"] } },
  ],
},
```

> **macOS: debugging hangs on "Building…"?** delve starts the program through the system `debugserver`, which, without
> developer mode, asks for a password in a separate window every time. Turn it on once: `sudo DevToolsSecurity -enable`.
> `:OwnHealth` shows whether it is on.

## Search everywhere

**`space space`** — one window for everything, like Search Everywhere (double shift) in GoLand: type what you need
instead of remembering which key searches for it.

- project files;
- ownvim **actions** — with their key on the right so it sticks (`format`, `blame`, `coverage`…);
- run configurations (`run worker`), modes, themes.

`#` as the first character searches project symbols (types, functions) via the language server. Files only —
`cmd-p` or `space ff`.

## Settings

```jsonc
"modules": {
  "workspace": {
    "restore": true,                                // open the project as you left it
    "default": { "left": "tree", "bottom": false }, // a new project: tree on the left, nothing at the bottom
    "left_width": 32,
    "bottom_height": 12,
  },
},
```

`left` — `tree`, `outline`, `tests`, `db` or `false`; `bottom` — `terminal`, `problems`, `tasks`, `test_output` or
`false`. The module turns off like any other: `"workspace": false` — panels open wherever they happen to, as in plain
Neovim.
