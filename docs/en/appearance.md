# Appearance

[← Documentation](README.md)

- [Themes](#themes) · [your own theme](#your-own-theme) · [from VS Code](#theme-from-vs-code) · [tweak colors](#tweak-colors-of-any-theme)
- [Icons](#icons)
- [Font](#font)
- [Interface](#interface): status line, tabs, breadcrumbs
- [Start screen](#start-screen)
- [Panels](#panels) · [side image](#side-image)
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
| ownvim's own (JSON, ownvim engine) | `dev-night`, `dev-day`, `sunset` |
| popular VS Code themes | One Dark Pro (`onedark`, `onedark_vivid`, `onedark_dark`, `onelight`), GitHub (`github_dark_default`, `github_dark_dimmed`, `github_light`…), Dark+ (`vscode`), Dracula (`dracula`, `dracula-soft`), Monokai Pro (`monokai-pro`, `-spectrum`, `-octagon`, `-machine`, `-ristretto`, `-classic`), Material (`material-darker`, `-oceanic`, `-palenight`, `-deep-ocean`, `-lighter`), Ayu (`ayu-dark`, `ayu-mirage`, `ayu-light`) |
| from the Neovim world | tokyonight, rose-pine (in terminal colors if the dotfiles are installed), kanagawa, catppuccin, nightfox, cyberdream, vesper, gruvbox-material, nordic, everforest, oxocarbon |

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
},
```

Small things that come with any JSON theme: the inactive split is a couple of percent darker, a yanked text
flashes in the accent color and fades out, the matching bracket is accent-colored without a fill, float titles
are accent badges.

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
  "style": "bubbles",                          // arrows, slant, flat, plain
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

Blocks: `mode`, `branch`, `diagnostics`, `file`, `filetype`, `encoding`, `indent`, `lsp`, `diff`, `tests` (background
tests, `✓ 42` / `✗ 1`), `search`, `macro`, `position`, `progress`, `time`, plus your own from `custom` — text or the
output of a command (run in the background on a timer).

### Tabs and breadcrumbs

```jsonc
"tabline": { "show": "auto", "style": "underline", "close_button": true },  // bar, slant, plain; always, never
"breadcrumbs": { "separator": " › ", "max_depth": 3 },
```

Tabs work like VS Code: icon, name, `●` when unsaved, a close button; click to switch, middle click to close,
`shift-h` / `shift-l` — the neighbor. Breadcrumbs: folder › file › type › function under the cursor, for any language.

## Start screen

```jsonc
"dashboard": {
  "header": ["MY EDITOR"],
  "buttons": [{ "key": "p", "icon": "", "desc": "Projects", "do": "projects" }],
  "sections": ["header", "buttons", "project", "recent", "startup"]
},
```

Sections: `header`, `buttons`, **`project`** (branch, how many and which files changed, status of the compose
services — for the folder ownvim was opened in), `recent` (recent files in this folder), `projects`, `startup`, or any
text. A button's `do` is an action (as in `keys`), a `:command` or raw keys.

## Panels

```jsonc
"modules": {
  "panels": {
    "activity_bar": { "enabled": true, "items": ["files", "search", "git", "tests", "debug", "database", "claude", "settings"] },
    "bottom": { "height": 15, "tabs": ["terminal", "problems", "tasks"] },
  },
},
```

Like VS Code: an icon bar on the left (a click opens the view; `settings` is the gear at the bottom) and the bottom
panel "Terminal · Problems · Tasks" — `space j`, tabs — `space jt`, `jp` (every error in the project, `enter` jumps
to the line), `jo` (output of the last task).

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
