# Appearance

[← Documentation](README.md)

- [Themes](#themes) · [your own theme](#your-own-theme) · [from VS Code](#theme-from-vs-code) · [tweak colors](#tweak-colors-of-any-theme)
- [Icons](#icons)
- [Font](#font)
- [Interface](#interface): status line, tabs, breadcrumbs
- [Start screen](#start-screen)
- [Panels](#panels) ([workspace](workspace.md)) · [side image](#side-image)
- [Animations and VS Code details](#animations)

## Themes

**`alt-s`** (or `space uC`) — pick a theme with a preview: moving through the list recolors the whole editor, with
your own code shown on the right. `enter` applies it and writes it to `settings.jsonc`, `esc` restores the previous one.

```jsonc
"theme": "dev-night",                                  // one theme
"theme": { "dark": "dev-night", "light": "dev-day" },  // follow the system dark/light mode (the default)
"theme": "auto",                                       // whatever was picked in alt-s
```

### What's included

| | themes |
|---|---|
| ownvim's own (JSON, ownvim engine) | `dev-night`, `dev-day`, `sunset`, `aurora`, `midnight`, `nebula`, `forest`, `matcha`, `ember`, `mocha`, `ocean`, `arctic`, `dusk`, `graphite`, `mono`, `neon` |
| popular VS Code themes | One Dark Pro (`onedark`, `onedark_vivid`, `onedark_dark`, `onelight`), GitHub (`github_dark_default`, `github_dark_dimmed`, `github_light`…), Dark+ (`vscode`), Dracula (`dracula`, `dracula-soft`), Monokai Pro (`monokai-pro`, `-spectrum`, `-octagon`, `-machine`, `-ristretto`, `-classic`), Material (`material-darker`, `-oceanic`, `-palenight`, `-deep-ocean`, `-lighter`), Ayu (`ayu-dark`, `ayu-mirage`, `ayu-light`) |
| from the Neovim world | tokyonight, rose-pine (in terminal colors if the dotfiles are installed), kanagawa, catppuccin, nightfox, cyberdream, vesper, gruvbox-material, nordic, everforest, oxocarbon, gruvbox, nord, solarized-osaka, sonokai, edge, moonfly, nightfly, bamboo, flexoki, melange, poimandres, night-owl, vague, lackluster, modus, oldworld, fluoromachine, tokyodark, kanagawa-paper, kanso, jellybeans, evergarden, everblush |

Plugin themes load only when picked, so they don't affect startup time.

### Your own theme

`:ThemeNew my-theme sunset` creates a theme based on Sunset and opens `themes/my-theme.json`: change a color, save, and
the editor recolors. `:ThemeEdit` opens the current theme's file.

```jsonc
{
  "name": "Mine",
  "type": "dark",                          // or "light"
  "include": "sunset",                     // everything not set here comes from this theme
  "palette": { "accent": "#f472b6", "bg": "#0d0b12" },
  "syntax": { "keyword": { "fg": "purple", "italic": true }, "string": "#fbbf24" },
  "groups": { "LineNr": { "fg": "#3a3a3a" } },   // any highlight group as is
  "image": "~/Pictures/a.png"              // image for the side panel while this theme is active
}
```

- **Palette:** `bg`, `fg` (required), `accent`, `red`, `orange`, `yellow`, `green`, `cyan`, `blue`, `purple`, `pink`,
  `bg_alt`, `bg_highlight`, `bg_visual`, `border`, `fg_dim`, `fg_muted`, `diff_*`.
- **Syntax roles:** `comment`, `keyword`, `function`, `method`, `builtin`, `string`, `number`, `boolean`, `constant`,
  `type`, `interface`, `variable`, `parameter`, `property`, `namespace`, `operator`, `punctuation`, `tag`, `attribute`,
  `escape`, `regex`, `label`, `macro`.
- **A color** is a palette name or `"#rrggbb"`. Which group is under the cursor — `space ui`.

### Theme from VS Code

Any theme from Open VSX or the Marketplace, by extension id, as in VS Code (`publisher.name`):

```
:ThemeInstall dracula-theme.theme-dracula
:ThemeInstall GitHub.github-vscode-theme
:ThemeInstall https://…/theme.vsix          (or .json, or a file path)
```

The theme is converted to the ownvim format (`themes/<name>.json`) and activated. If the extension contains several
themes, ownvim asks which one.

### Tweak colors of any theme

Like `workbench.colorCustomizations` in VS Code, without touching the theme file (works for JSON themes):

```jsonc
"colors": {
  "syntax": { "comment": { "fg": "#6b7280", "italic": false } },  // for every theme
  "[dev-night]": { "palette": { "bg": "#000000" } }                // only for this one
},
"appearance": { "transparent": true },  // background from the terminal: Ghostty's blur shows through
```

More `appearance` switches:

```jsonc
"appearance": {
  "terminal_edges": true,   // Ghostty's window padding takes the editor color — no frame of terminal background
  "messages": "modern",     // long messages fold into [+3] instead of "Press ENTER" (g< — all); "classic" — the old way
  "italic": ["comment", "keyword"],  // italics on top of any theme, plugin ones too (tokyonight): also function, type,
                                     // string, parameter, builtin; [] — as the theme intends
  "frames": true,           // frames like the dotfiles prompt and Kali (below); false — the old way
},
```

Small things that come with any JSON theme: the inactive split is a couple of percent darker, a yanked text
flashes in the accent color and fades out, the matching bracket is accent-colored without a fill, float titles
are accent badges.

**Frames** (`"frames": true`) — the whole editor in the style of the `frame` status line and the dotfiles prompt:

```
─[ lua › own › frames.lua › M.on ]──────────────     file line above the code
❯ 10 function M.on() …                                current line number — an accent arrow
╭──────[ Find file ]──────╮                           picker, K, which-key, notifications, plugin windows
─[ PROJECT ]────────────                              side panels
╰─( NORMAL )─[  main ]─[ main.go ]──────[ 10:1 ]─╯   status line (style: frame)
```

Titles get brackets in every bordered window — ours and plugins', without configuring each one.
The frame follows the mode (`"frames_by_mode"`): in insert every line takes the mode color at once, visual and
terminal have their own; saving flashes it green when the file has no errors and red when it has (`"save_flash"`). The indent guide of the block under the
cursor is a half-tone of the accent.

More in the same style: `:` and `/` open in the middle in a frame `╭─[  command ]─╮` (`"cmdline": "bottom"` — at the
bottom, like vim); a closed fold is `╶─[ func main() · 24 lines ]────`; errors to the right of the line are
`──[  undefined: foo ]` (`modules.error_lens.preset`: `"frame"`, `"modern"` — a badge); the tree has `├─ └─ │` branches
like the `tree` command (`explorer.indent`: `"tree"`, `"│ "`, `"  "`). Line numbers near the cursor are brighter and
fade further away (`"number_fade"`); after a jump (`gd`, search, `ctrl-o`, another file) the line flashes in the accent
(`"jump_flash"`). The completion menu and the picker point with `❯`. Opening a project shows a toast for a couple
of seconds — `[  github-watcher ]  feature/bot · ↑2 unpushed · ● 3 files changed` (`"project_toast"`). A code
screenshot (`space P`) gets the same frame and the editor's own colors: `─[ config.go › defaultDBPath ]──` …
`( dev㉿host )──[ ownvim ]`.

## Icons

```jsonc
"icons": { "theme": "material" },
```

| theme | look |
|---|---|
| `material` (default) | like Material Icon Theme in VS Code: folders get an icon and color by meaning — `cmd`, `bin` ▶, `internal` — a lock, `migrations`, `db` — a table, `tests` — a check mark, `.github` — sync, `deploy`, `k8s` — upload, `docs`, `config`, `assets`… (157 names) |
| `default` | the mini.icons set (hundreds of file types) in theme colors |
| `backend` | Go, SQL, Docker, migrations and tests stand out more |
| `accent` · `mono` | all icons in the theme accent color · in one muted color |
| `ascii` | letters instead of icons — for terminals without a Nerd Font |

`:IconTheme` — pick from a list, `:IconThemeInstall <link to .json>` — install one. Icons appear in the file tree,
search, the completion menu and the status line.

Your own icons on top of any theme:

```jsonc
"icons": {
  "theme": "material",
  "overrides": {
    "extension": { "go": { "glyph": "", "color": "cyan" } },
    "file": { "Makefile": { "glyph": "", "color": "orange" } },
    "directory": { "handlers": { "glyph": "", "color": "green" } },
    "lsp": { "Function": { "glyph": "ƒ" } }
  }
},
```

A color is a theme color (`red`, `orange`, `yellow`, `green`, `cyan`, `azure`, `blue`, `purple`, `pink`, `grey`,
`accent`) or `"#rrggbb"`. Icons are any [Nerd Font](https://www.nerdfonts.com/cheat-sheet) glyphs. For your own icon
theme, copy any file from `icons/`; `"include"` uses another theme as the base. A terminal can't show VS Code's SVG
icons, so icon themes are ownvim's own, in JSON.

## Font

```jsonc
"font": { "family": "Geist Mono", "size": 15, "ligatures": false, "line_height": "10%", "features": ["ss01", "zero"] },
```

In a terminal the font belongs to the terminal, so ownvim writes it to `~/.config/ghostty/ownvim.ghostty` and asks
Ghostty to reload — it is the font of every Ghostty window. `:Font` — pick an installed font, `:FontInstall Geist Mono` —
install one (brew: Google Fonts and Nerd Fonts) and activate it.

## Interface

### Status line

```jsonc
"statusline": {
  "style": "frame",                            // a frame like the dotfiles prompt; also bubbles, arrows, slant, flat, plain
  "left": ["mode", "branch", "diagnostics", "file"],
  "right": ["search", "macro", "tests", "diff", "lsp", "position", "time"],
  "path": "relative",                          // name, full
  "custom": {
    "k8s": { "shell": "kubectl config current-context", "every_ms": 10000, "icon": "⎈", "color": "pink" },
    "env": { "text": "prod", "color": "red" }
  },
  "mode_names": { "n": "NORMAL", "i": "INSERT" }
},
```

Blocks: `mode`, `branch` (with `↑` unpushed, `↓` behind, `●` changed — `"git_status"`), `diagnostics`, `file`, `filetype`, `encoding`, `indent`, `lsp`, `diff`, `tests` (background
tests, `✓ 42` / `✗ 1`), `search`, `macro`, `position`, `progress`, `time`, `ram` (memory in use), `uptime` (how long the Mac has been up), `wpm` (typing speed over the last 30 s), plus your own from `custom` — text or the
output of a command (run in the background on a timer).

### Tabs and breadcrumbs

```jsonc
"tabline": { "show": "always", "style": "ide", "close_button": true },  // underline, bar, slant, plain; auto, never
"breadcrumbs": { "separator": " › ", "max_depth": 3 },
```

Tabs work like VS Code: icon, name, `●` when unsaved, a close button; click to switch, middle click to close,
`shift-h` / `shift-l` — the neighbor. Breadcrumbs: folder › file › type › function under the cursor, for any language.

## Start screen

```jsonc
"dashboard": {
  "header": ["MY EDITOR"],
  "buttons": [{ "key": "p", "icon": "", "desc": "Projects", "do": "projects" }],
  "sections": ["header", "info", "buttons", "project", "recent", "startup"]
},
```

Sections: `header`, `info` (a fastfetch-like frame: `dev㉿host`, nvim, startup time, theme, date), `buttons`, **`project`** (branch, how many and which files changed, status of the compose
services — for the folder ownvim was opened in), `recent` (recent files in this folder), `projects`, `startup`, or any
text. A button's `do` is an action (as in `keys`), a `:command` or raw keys.

"Power on" and "power off" (the `dashboard` section): `"intro": true` — launched without a file, a rain of glyphs in the
theme colors runs for a moment before the start screen; `"animate": true` — the logo shimmers while the screen is
visible; `"watermark": true` — a faint logo in the middle of an empty window (on screen only); `"outro": true` — on exit
a frame `see you · 2h 14m · 12 files` shows for a moment.

## Panels

The left and bottom panels, modes, run and search everywhere — [Workspace](workspace.md).

### Side image

```jsonc
"modules": {
  "image_panel": {
    "enabled": true,
    "image": "~/Pictures/girl.png",                       // or https://… (downloaded once)
    "themes": { "sunset": "~/Pictures/sunset-girl.png" }, // a different one per theme
    "side": "right", "width": 32,
  },
},
```

A real image in the terminal (kitty protocol: Ghostty, kitty, WezTerm; not inside tmux). PNG works right away;
jpg/webp/gif need ImageMagick. `space up` — show/hide.

## Animations

```jsonc
"animations": {
  "cursor": { "enabled": true, "stiffness": 0.8, "trailing_stiffness": 0.6, "insert_stiffness": 0.9, "min_distance": 2 },
  "scroll": { "enabled": true, "duration_ms": 100 },
  "indent_scope": { "enabled": false },
},
```

The cursor glides on jumps, but moves instantly with no trail when typing or stepping one character
(`min_distance`); in insert mode it is faster (`insert_stiffness`) so typing never drags. Scrolling takes 100 ms.
Want it even snappier — `"stiffness": 1` (instant), `"insert": false`, a smaller `duration_ms`; no animations at all —
`"cursor": { "enabled": false }`, `"scroll": { "enabled": false }`.

More VS Code details, each a separate module: colored bracket pairs (`brackets`), the function header sticking to the
top (`sticky_scroll`), errors to the right of the line (`error_lens`), a scrollbar with error and git marks
(`scrollbar`), a minimap (`minimap`, off; `space um`), the mode shown in the cursor and line color (`modes`).
