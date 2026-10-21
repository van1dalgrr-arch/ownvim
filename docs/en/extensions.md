# Script extensions

[← Documentation](README.md)

An extension is an ordinary script (Python or anything else): **it reads text from stdin and writes the result to
stdout**. ownvim passes it the selection / file / line and does with the answer what `settings.jsonc` says. No
Neovim or Lua knowledge needed.

## Quick start (3 steps)

1. In ownvim: `:ExtensionNew my_tool` — creates `extensions/my_tool.py` from a template and a line in `settings.jsonc`.
2. Write the logic in `extensions/my_tool.py`, save.
3. Select text → `space C` → pick `my_tool`. Or bind a key (see below).

## How it works

The files live in the ownvim folder (`~/dev/ownvim`):

```
extensions/my_tool.py     your script
settings.jsonc            the "commands" section — how to run it
```

A command in `settings.jsonc`:

```jsonc
"commands": {
  "My command": {
    "run": "python3 extensions/my_tool.py",  // any shell command; extensions/ is the ownvim folder
    "input": "selection",   // what the script receives on stdin
    "output": "replace",    // what to do with its stdout
    "key": "x <leader>xm",  // a key (optional): modes + key
    "ft": ["go", "python"]  // only for these file types (optional)
  }
}
```

| `input` | stdin gets | | `output` | what happens to stdout |
|---|---|---|---|---|
| `selection` | the selected lines | | `replace` | replaces whatever was the input |
| `file` | the whole file | | `insert` | inserted as lines below the cursor |
| `line` | the current line | | `window` | shown in a window below (`q` — close) |
| `word` | the word under the cursor | | `notify` | a pop-up notification |
| `none` | nothing | | `none` | nothing (the script does its own thing) |

Modes in `key`: `n` — normal, `x` — visual, `i` — insert (`nx` works too). `<leader>` is space.

Environment variables the script receives:

| variable | what |
|---|---|
| `OWN_FILE` | full path of the open file |
| `OWN_LINE` | cursor line number |
| `OWN_ROOT` | project root (the script runs there too) |
| `OWN_FILETYPE` | file type: `go`, `python`, `cpp`… |
| `OWN_WORD` | the word under the cursor |

Rules:
- the answer goes to `stdout`; a trailing newline is removed automatically;
- on error — `sys.exit(1)` and a message on `stderr`: ownvim shows it and leaves the text in the file untouched;
- `pip install` anything, use the network, a database, run programs;
- save the script and the new version works immediately; change `settings.jsonc` — save it, and keys update.

## Examples (already in `extensions/`)

```python
# extensions/sort_lines.py — sorts the selected lines (space x s in visual mode)
import sys
lines = sys.stdin.read().split("\n")
print("\n".join(sorted(lines, key=str.lower)), end="")
```

```python
# extensions/file_info.py — a notification: file name and line count (space x i)
import os, sys
text = sys.stdin.read()
print(f"{os.path.basename(os.environ['OWN_FILE'])}: {len(text.splitlines())} lines")
```

The script can be in any language, Go included: `"run": "go run ./extensions/mytool"` or a built binary.

## Asking an AI to write an extension

Paste this text and add your task:

```
Write an extension for my editor ownvim. Rules:
- It is a Python 3 script. Input text arrives on stdin; print the result to stdout (print(..., end="")).
- Report errors like this: print("message", file=sys.stderr); sys.exit(1).
- Environment variables available: OWN_FILE (file path), OWN_LINE (line number), OWN_ROOT (project root,
  also the current directory), OWN_FILETYPE (go, python, cpp…), OWN_WORD (word under the cursor).
- The script lives in extensions/<name>.py.
- Also give me a line for the "commands" section of settings.jsonc in this format:
  "Name": { "run": "python3 extensions/<name>.py", "input": "selection|file|line|word|none",
            "output": "replace|insert|window|notify|none", "key": "x <leader>x<letter>", "ft": ["go"] }
  input — what to put on stdin, output — what to do with the answer (replace — replace the input, insert — insert
  below, window — show in a window, notify — a notification).

Task: <describe what should happen>
```

Put the script in `~/dev/ownvim/extensions/<name>.py` and the line inside `"commands": { … }` in `settings.jsonc`, save
both. Check: `space C` → your command.

Not working — run `:messages` in ownvim (the error text) and `:OwnHealth`. Give the AI the script, the line from
`settings.jsonc` and the error text.

## Need more (later)

A script command can't react to events by itself (saving, opening a file) or draw its own windows. That needs plugins
on pynvim (or a Go RPC client) — ownvim doesn't have that yet.
