# Working with code

[← Documentation](README.md)

- [Search](#search) · [File tree](#file-tree) · [Windows, tabs, buffers](#windows-tabs-buffers)
- [Editing](#editing) · [Moving without the mouse](#moving-without-the-mouse) · [Russian layout](#russian-layout)
- [Git](#git)
- [Claude](#claude)
- [Sessions](#sessions) · [Autosave](#autosave)
- [Quiet mode and rest](#quiet-mode-and-rest) — so you don't get tired
- [Friction notes](#friction-notes)
- [Terminal](#terminal)

The essentials; every key — [Keys](../keys.ru.md) or `space sk` inside ownvim.

## Search

| key | what |
|---|---|
| `space space` / `cmd-p` | find a file in the project |
| `space /` | text in the project (`space sw` — the word under the cursor) |
| `space ,` | open buffers |
| `space fr` / `fR` | recent files / recent in this folder |
| `space fp` | projects |
| `space ss` / `sS` | symbols in the file / project |
| `space sd` / `sD` | errors in the project / file |
| `space sr` | find and replace in the project (grug-far) |
| `space sA` | structural replace in code (ast-grep) |
| `space sR` | resume the last search |

In the search window `alt-c` switches the scope: project ↔ the folder ownvim was started in.

## File tree

`space e` (or the icon on the left). ownvim's own tree: git status by color and letter (`M`, `U`, `A`, `D`), `●` on
files and folders with errors, the open file highlighted, a folder containing a single folder shown on one line
(`internal/user/repo`), folder icons from the [icon theme](appearance.md#icons).

| in the tree | |
|---|---|
| `enter` / `l` · `h` | open · collapse |
| `a` | create (trailing `/` — a folder) |
| `r` · `d` | rename · delete (to the bin when `trash` is installed) |
| `c` / `x` / `p` | copy / cut / paste |
| `y` · `s` | copy path · open on the right |
| `H` · `-` · `.` | hidden files · parent folder · make it the root |
| `?` · `q` | help · close |

```jsonc
"explorer": { "side": "left", "width": 32, "hidden": false, "compact": true, "indent": "│ ", "git": true },
```

`"engine": "snacks"` — use the snacks tree instead. The yazi file manager — `space fy` (at the file) / `space fY` (at the root).

## Windows, tabs, buffers

| key | what |
|---|---|
| `ctrl-h/j/k/l` | to the neighboring window |
| `space -` / `space \|` | split down / right |
| `space wd` · `space wm` | close window · maximize |
| `space uz` | zen: just the code |
| `shift-h` / `shift-l` | neighboring file tab |
| `space bd` / `bo` | close buffer / the others |

## Editing

- Auto-paired brackets and quotes, comments with `gcc` / `gc`.
- Text objects: `af`/`if` — function, `ac`/`ic` — type, `ao`/`io` — block.
- Surround: `gsa` — add, `gsd` — delete, `gsr` — replace.
- Selected lines: `J` / `K` — move, `<` / `>` — indent (the selection stays).
- Multiple cursors: `ctrl-n` — a cursor on the next occurrence, `space m` — menu, `alt`+click — place one.
- Yank history: `space p` — paste anything you've copied.
- `ctrl-a` / `ctrl-x` — not just numbers: `true` ↔ `false`, dates, and for Go — `:=` ↔ `=`, `Error` ↔ `Fatal`,
  HTTP methods and statuses (your own cycles — in the `dial` module settings).
- TODO / FIXME are highlighted and searchable (`space st`).
- File edit history without git — `space U`.

## Moving without the mouse

- **`enter`** — letters appear next to every line on screen; press one and you're there.
- **`s`** — jump by characters, **`S`** — by code nodes (flash).
- **Motion hints** in the line — `space uP`. **The habit coach** (hardtime) suggests shorter ways and blocks nothing;
  `space uH` — toggle, `space uR` — your most frequent habits.

### Leaving insert mode

A quick `jk` (or `ол` in the Russian layout) leaves insert mode: if `k` arrives within 200 ms after `j`, ownvim deletes
the `j` and exits. Unlike a plain `"i jk"` mapping, `j` doesn't hang "pending" — it becomes text right away, so
completion doesn't wait; and `ол` can't be done with a plain mapping at all. After 5 seconds without typing, insert
mode ends by itself.

```jsonc
"modules": { "modes": { "escape": ["jk", "ол"], "escape_ms": 200, "auto_normal_ms": 5000 } },  // [] / 0 — off
```

## Russian layout

Commands work without switching the layout: `о` = `j`, `л` = `k`, `вв` = `dd`, `Ж` = `:`. In insert mode letters are
typed as is. Alt combinations are duplicated automatically (`alt-щ` = `alt-o`).

```jsonc
"modules": { "russian": { "langmap": true, "alt_keys": true } },
```

## Git

| key | what |
|---|---|
| `alt-g` / `space gg` | lazygit |
| `]h` / `[h` | next / previous change |
| `space ghs` / `ghr` / `ghp` | stage / reset / preview the hunk |
| `space uB` | blame for the line in grey on the right (`space ghb` — the full commit) |
| `space gv` | all changes and conflicts (diffview, three-way merge) |
| `space gm` | branch vs main — like a PR |
| `space gH` | file history |
| `space gs` / `gl` / `gc` | changed files / commits / branches |
| `space gB` | open the line on GitHub |

```jsonc
"git": {
  "blame": false,
  "blame_format": "<author>, <author_time:%d.%m.%Y> · <summary>",
  "base_branch": "auto",   // what to compare the branch with: origin/HEAD, or "main", "develop"
},
```

## Claude

Claude Code inside ownvim (the `ai` module):

| key | what |
|---|---|
| `alt-c` | show / hide the Claude panel (from anywhere, terminal included) |
| `space ax` | "fix the error under the cursor" |
| `space as` | send the selection |
| `space ab` | add the file to the context |
| `space ay` / `an` | accept / reject an edit |
| `space aR` | branch review: Claude reads the diff against main; findings appear on the lines, like errors, and as a list in "Problems" |
| `space aX` | clear review findings |

```jsonc
"ai": { "side": "right", "width": 0.4 },
```

Files Claude changed are reloaded in open buffers automatically.

## Sessions

Close ownvim in a project, open it there again without files, and your tabs, splits and cursor positions are back.

| key | what |
|---|---|
| `space qs` | restore this folder's session |
| `space qS` | pick from all sessions |
| `space qd` | don't save this session |

```jsonc
"sessions": { "auto_save": true, "auto_restore": true, "ignore": ["~", "/tmp", "/"] },
```

## Autosave

Files save themselves: leave insert mode, edit in normal mode, switch to another window. Saving triggers formatting.
Files changed outside (git, Claude, `go generate`) are reloaded automatically. Turn it off for now —
`:let g:autosave = v:false`.

## Quiet mode and rest

**Quiet mode — `space uq`** (`:Quiet`): when you just need to think and write, it hides everything distracting — type
hints, error badges, labels above code, blame, "implements", animations, indent guides, the sticky header, breadcrumbs,
the scrollbar. Errors don't disappear: gutter signs and underlines stay. The status line shows "тихо" (quiet) so you
don't forget. `space uq` again — everything back exactly as it was.

```jsonc
"modules": { "quiet": { "hide": ["inlay_hints", "error_lens", "animations", "breadcrumbs"] } },  // hide only these
```

**Rest.** ownvim counts continuous work time: after 50 minutes — one gentle notification and "⏱ пора отдохнуть"
(time for a break) in the status line, with no ticking clock pushing you. A pause longer than 5 minutes counts as a
break and the count restarts. `:Rest` — start a break (☕ and a countdown in the status line), `:RestLater` — remind me
in 10 minutes.

```jsonc
"modules": { "rest": { "work_min": 50, "break_min": 5, "show": "always" } },  // always — always show work time
"modules": { "rest": false },                                                // no reminders
```

## Friction notes

So that ownvim grows from real work rather than "this would be cool":

- **`space ?`** — "what's inconvenient?": a few words, and ownvim records the place itself — project, file, line,
  mode, file type, the last command and the selected text (if pressed in visual mode).
- **`space N`** (`:Notes`) — the list, newest first, with the file at the right line on the side. `enter` — go there,
  `ctrl-x` — resolved (remove), `ctrl-y` — every note to the clipboard as markdown.

Notes are stored in the editor's data (`~/.local/share/ownvim/own-notes.json`), not in the project.

## Terminal

| key | what |
|---|---|
| `ctrl-/` | terminal below |
| `space ft` / `fT` | terminal at the project root / at the launch folder |
| `space j` | bottom panel: terminal, problems, tasks |
| `space P` | code screenshot → PNG to the clipboard (freeze, in theme colors) |
