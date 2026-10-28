# Внешний вид

[← Документация](README.md)

- [Темы](#темы) · [своя тема](#своя-тема) · [из VS Code](#тема-из-vs-code) · [поправить цвета](#поправить-цвета-любой-темы)
- [Иконки](#иконки)
- [Шрифт](#шрифт)
- [Интерфейс](#интерфейс): статусная строка, вкладки, хлебные крошки
- [Стартовый экран](#стартовый-экран)
- [Панели](#панели) ([рабочее место](workspace.md)) · [картинка сбоку](#картинка-сбоку)
- [Анимации и детали VS Code](#анимации)

## Темы

**`alt-s`** (или `пробел uC`) — выбор темы с предпросмотром: курсор по списку перекрашивает весь редактор,
справа — ваш же код в этой теме. `enter` — применить и записать в `settings.jsonc`, `esc` — вернуть как было.

```jsonc
"theme": "dev-night",                                  // одна тема
"theme": { "dark": "dev-night", "light": "dev-day" },  // по тёмной/светлой теме системы (по умолчанию)
"theme": "auto",                                       // та, что выбрана в alt-s
```

### Что есть

| | темы |
|---|---|
| свои (JSON, движок ownvim) | `dev-night`, `dev-day`, `sunset`, `aurora`, `midnight`, `nebula`, `forest`, `matcha`, `ember`, `mocha`, `ocean`, `arctic`, `dusk`, `graphite`, `mono`, `neon` |
| популярные темы VS Code | One Dark Pro (`onedark`, `onedark_vivid`, `onedark_dark`, `onelight`), GitHub (`github_dark_default`, `github_dark_dimmed`, `github_light`…), Dark+ (`vscode`), Dracula (`dracula`, `dracula-soft`), Monokai Pro (`monokai-pro`, `-spectrum`, `-octagon`, `-machine`, `-ristretto`, `-classic`), Material (`material-darker`, `-oceanic`, `-palenight`, `-deep-ocean`, `-lighter`), Ayu (`ayu-dark`, `ayu-mirage`, `ayu-light`) |
| из мира Neovim | tokyonight, rose-pine (в цветах терминала, если стоят dotfiles), kanagawa, catppuccin, nightfox, cyberdream, vesper, gruvbox-material, nordic, everforest, oxocarbon, gruvbox, nord, solarized-osaka, sonokai, edge, moonfly, nightfly, bamboo, flexoki, melange, poimandres, night-owl, vague, lackluster, modus, oldworld, fluoromachine, tokyodark, kanagawa-paper, kanso, jellybeans, evergarden, everblush |

Темы-плагины грузятся, только когда выбраны, — на скорость запуска они не влияют.

### Своя тема

`:ThemeNew моя-тема sunset` — создать тему на основе Sunset. Откроется файл `themes/моя-тема.json`: поменяли цвет,
сохранили — редактор перекрасился. `:ThemeEdit` — открыть файл текущей темы.

```jsonc
{
  "name": "Моя",
  "type": "dark",                          // или "light"
  "include": "sunset",                     // всё, что не задано, — отсюда
  "palette": { "accent": "#f472b6", "bg": "#0d0b12" },
  "syntax": { "keyword": { "fg": "purple", "italic": true }, "string": "#fbbf24" },
  "groups": { "LineNr": { "fg": "#3a3a3a" } },   // любая группа подсветки как есть
  "image": "~/Pictures/a.png"              // картинка для панели сбоку, пока стоит эта тема
}
```

- **Палитра:** `bg`, `fg` (обязательны), `accent`, `red`, `orange`, `yellow`, `green`, `cyan`, `blue`, `purple`,
  `pink`, `bg_alt`, `bg_highlight`, `bg_visual`, `border`, `fg_dim`, `fg_muted`, `diff_*`.
- **Роли синтаксиса:** `comment`, `keyword`, `function`, `method`, `builtin`, `string`, `number`, `boolean`,
  `constant`, `type`, `interface`, `variable`, `parameter`, `property`, `namespace`, `operator`, `punctuation`,
  `tag`, `attribute`, `escape`, `regex`, `label`, `macro`.
- **Цвет** — имя из палитры или `"#rrggbb"`. Какая группа под курсором — `пробел ui`.

### Тема из VS Code

Любая тема с Open VSX или Marketplace — по id расширения, как в VS Code (`издатель.имя`):

```
:ThemeInstall dracula-theme.theme-dracula
:ThemeInstall GitHub.github-vscode-theme
:ThemeInstall https://…/theme.vsix          (или .json, или путь к файлу)
```

Тема конвертируется в формат ownvim (`themes/<имя>.json`) и включается. Если в расширении несколько тем, ownvim
спросит, какую взять.

### Поправить цвета любой темы

Как `workbench.colorCustomizations` в VS Code — не трогая файл темы (работает для JSON-тем):

```jsonc
"colors": {
  "syntax": { "comment": { "fg": "#6b7280", "italic": false } },  // для всех тем
  "[dev-night]": { "palette": { "bg": "#000000" } }                // только для этой
},
"appearance": { "transparent": true },  // фон из терминала: размытие Ghostty видно сквозь редактор
```

Ещё переключатели `appearance`:

```jsonc
"appearance": {
  "terminal_edges": true,   // поля окна Ghostty — цветом редактора, без рамки фона терминала по краям
  "messages": "modern",     // длинные сообщения сворачиваются в [+3] вместо «Press ENTER» (g< — все); "classic" — как было
  "italic": ["comment", "keyword"],  // курсив поверх любой темы, и плагинной (tokyonight): ещё function, type,
                                     // string, parameter, builtin; [] — как задумано темой
  "frames": true,           // рамки, как промпт dotfiles и Kali (ниже); false — как было
},
```

Мелочи, которые есть в любой JSON-теме: неактивное окно на пару процентов темнее, скопированное вспыхивает
цветом акцента и плавно гаснет, парная скобка — цветом акцента без заливки, заголовки всплывающих окон — плашками.

**Рамки** (`"frames": true`) — весь редактор в стиле статусной строки `frame` и промпта dotfiles:

```
─[ lua › own › frames.lua › M.on ]──────────────     строка файла над кодом
❯ 10 function M.on() …                                номер текущей строки — стрелкой акцента
╭──────[ Найти файл ]──────╮                          поиск, K, which-key, уведомления, окна плагинов
─[ ПРОЕКТ ]────────────                               панели слева
╰─( ОБЫЧНЫЙ )─[  main ]─[ main.go ]──────[ 10:1 ]─╯  статусная строка (style: frame)
```

Заголовки в скобки берутся у любого окна с рамкой — своих и плагинов, без настройки каждого.
Рамка живёт режимом (`"frames_by_mode"`): во вставке все линии разом — цветом режима, в выделении — своим, в
терминале — своим; сохранил — на миг вспыхивает: зелёным — ошибок нет, красным — есть (`"save_flash"`). Линия отступа блока под курсором — полутоном
акцента.

Курсор живёт тем же цветом (`"cursor_by_mode"`): в обычном режиме — акцент темы, во вставке — зелёный, в выделении —
фиолетовый, и шлейф плавного курсора — тоже. `false` — в обычном режиме курсор цветом текста.

Ещё в том же стиле: `:` и `/` — по центру в рамке `╭─[  команда ]─╮` (`"cmdline": "bottom"` — внизу, как в vim);
свёрнутый блок — `╶─[ func main() · 24 строки ]────`; ошибки справа от строки — `──[  undefined: foo ]`
(`modules.error_lens.preset`: `"frame"`, `"modern"` — плашкой); дерево — ветками `├─ └─ │`, как у команды `tree`
(`explorer.indent`: `"tree"`, `"│ "`, `"  "`). Номера строк у курсора ярче, дальше — бледнее (`"number_fade"`);
прыгнул (`gd`, поиск, `ctrl-o`, другой файл) — строка на миг подсвечена акцентом (`"jump_flash"`). В меню
дополнения и в поиске — стрелка `❯`. Открыл проект — на пару секунд тост `[  github-watcher ]  feature/bot · ↑2 не
запушено · ● 3 файла изменено` (`"project_toast"`). Скриншот кода (`пробел P`) — в той же рамке и цветах самого
редактора: `─[ config.go › defaultDBPath ]──` … `( dev㉿host )──[ ownvim ]`.

## Иконки

```jsonc
"icons": { "theme": "material" },
```

| тема | вид |
|---|---|
| `material` (по умолчанию) | как Material Icon Theme в VS Code: у папок свой значок и цвет по смыслу — `cmd`, `bin` ▶, `internal` — замок, `migrations`, `db` — таблица, `tests` — галочка, `.github` — синхронизация, `deploy`, `k8s` — выгрузка, `docs`, `config`, `assets`… (157 имён) |
| `default` | набор mini.icons (сотни типов файлов) в цветах темы |
| `backend` | Go, SQL, Docker, миграции и тесты различаются сильнее |
| `accent` · `mono` | все значки цветом акцента темы · одним приглушённым цветом |
| `ascii` | буквы вместо значков — для терминала без Nerd Font |

`:IconTheme` — выбрать из списка, `:IconThemeInstall <ссылка на .json>` — поставить. Значки видны в дереве файлов,
поиске, меню дополнения и статусной строке.

Свои значки поверх любой темы:

```jsonc
"icons": {
  "theme": "material",
  "overrides": {
    "extension": { "go": { "glyph": "", "color": "cyan" } },
    "file": { "Makefile": { "glyph": "", "color": "orange" } },
    "directory": { "handlers": { "glyph": "\uf0e8", "color": "green" } },
    "lsp": { "Function": { "glyph": "ƒ" } }
  }
},
```

Цвет — из темы (`red`, `orange`, `yellow`, `green`, `cyan`, `azure`, `blue`, `purple`, `pink`, `grey`, `accent`)
или `"#rrggbb"`. Значки — любые символы [Nerd Font](https://www.nerdfonts.com/cheat-sheet). Своя тема иконок —
скопируйте любой файл из `icons/`; `"include"` берёт другую тему за основу. SVG-иконки VS Code терминал показать не
может, поэтому темы иконок — свои, в JSON.

## Шрифт

```jsonc
"font": { "family": "Geist Mono", "size": 15, "ligatures": false, "line_height": "10%", "features": ["ss01", "zero"] },
```

Шрифт в терминале задаёт сам терминал, поэтому ownvim пишет его в `~/.config/ghostty/ownvim.ghostty` и просит Ghostty
перечитать конфиг — это общий шрифт всех окон Ghostty. `:Font` — выбрать из установленных, `:FontInstall Geist Mono` —
поставить (brew: Google Fonts и Nerd Fonts) и включить.

## Интерфейс

### Статусная строка

```jsonc
"statusline": {
  "style": "frame",                            // рамкой, как промпт dotfiles; ещё bubbles, arrows, slant, flat, plain
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

Блоки: `mode`, `branch` (с `↑` не запушено, `↓` не подтянуто, `●` изменено — `"git_status"`), `diagnostics`, `file`, `filetype`, `encoding`, `indent`, `lsp`, `diff`, `tests`
(тесты в фоне, `✓ 42` / `✗ 1`), `search`, `macro`, `position`, `progress`, `time`, `ram` (занято памяти),
`uptime` (сколько работает Mac), `wpm` (скорость печати за последние 30 с), `music` (что играет в Яндекс Музыке,
Apple Music, Spotify; клик — пауза, правый клик — следующий трек, средний — предыдущий) и свои из `custom` — текст или
вывод команды (выполняется в фоне по таймеру).

Музыку читает `media-control` (`brew install media-control`) из «Сейчас играет» macOS — приложение Яндекс Музыки и
music.yandex.ru в браузере туда пишут сами. Только Яндекс Музыка:
`"statusline": { "music": { "apps": ["ru.yandex.desktop.music"] } }`; `"max": 40` — длиннее обрезать, `"paused": false` —
не показывать на паузе.

### Вкладки и хлебные крошки

```jsonc
"tabline": { "show": "always", "style": "ide", "close_button": true },  // underline, bar, slant, plain; auto, never
"breadcrumbs": { "separator": " › ", "max_depth": 3 },
```

Вкладки — как в VS Code: значок, имя, `●` у несохранённого, крестик; клик — перейти, средняя кнопка — закрыть,
`shift-h` / `shift-l` — соседняя. Хлебные крошки — папка › файл › тип › функция под курсором, для любого языка.

## Стартовый экран

```jsonc
"dashboard": {
  "header": ["МОЙ РЕДАКТОР"],
  "buttons": [{ "key": "p", "icon": "", "desc": "Проекты", "do": "projects" }],
  "sections": ["header", "info", "buttons", "project", "recent", "startup"]
},
```

Секции: `header`, `info` (рамка, как у fastfetch: `dev㉿host`, nvim, время старта, тема, дата), `buttons`, **`project`** (ветка, сколько файлов изменено и какие, статус сервисов compose — для
папки, где открыт ownvim), `recent` (недавние файлы этой папки), `projects`, `startup` или любой текст.
`do` у кнопки — действие (как в `keys`), `:команда` или клавиши.

«Включение» и «выключение» (раздел `dashboard`): `"intro": true` — при запуске без файла на миг идёт дождь знаков
цветами темы, потом стартовый экран; `"animate": true` — логотип переливается, пока экран на виду; `"watermark": true` —
в пустом окне бледный логотип по центру (только на экране); `"outro": true` — при выходе на миг рамка
`до встречи · 2ч 14м · 12 файлов`.

## Панели

Панели слева и снизу, режимы, запуск и «поиск везде» — [Рабочее место](workspace.md).

### Картинка сбоку

```jsonc
"modules": {
  "image_panel": {
    "enabled": true,
    "image": "~/Pictures/girl.png",                       // или https://… (скачается один раз)
    "themes": { "sunset": "~/Pictures/sunset-girl.png" }, // своя у каждой темы
    "side": "right", "width": 32,
  },
},
```

Настоящая картинка в терминале (протокол kitty: Ghostty, kitty, WezTerm; в tmux — нет). PNG — сразу, jpg/webp/gif —
с ImageMagick. `пробел up` — показать/спрятать.

## Анимации

```jsonc
"animations": {
  "cursor": { "enabled": true, "stiffness": 0.8, "trailing_stiffness": 0.6, "insert_stiffness": 0.9, "min_distance": 2 },
  "scroll": { "enabled": true, "duration_ms": 100 },
  "indent_scope": { "enabled": false },
  "terminal": true,
},
```

Курсор плавно перелетает при прыжках, а при наборе и сдвиге на один символ двигается сразу, без шлейфа
(`min_distance`); во вставке он быстрее (`insert_stiffness`), чтобы набор не тянулся. Прокрутка — 100 мс.
Хочется ещё резче — `"stiffness": 1` (мгновенно), `"insert": false`, меньше `duration_ms`; совсем без анимаций —
`"cursor": { "enabled": false }`, `"scroll": { "enabled": false }`.

Ещё детали из VS Code, каждая — отдельный модуль: цветные пары скобок (`brackets`), шапка функции сверху
(`sticky_scroll`), ошибки справа от строки (`error_lens`), полоса прокрутки с метками ошибок и git (`scrollbar`),
миникарта (`minimap`, выключена; `пробел um`), режим цветом курсора и строки (`modes`).

`"terminal": false` — шейдеры Ghostty (плавный курсор, шлейф, искры из `fx`) не работают в окне ownvim, а в остальных вкладках терминала остаются. ownvim помечает свою вкладку 255-м цветом палитры, шейдеры dotfiles эту метку видят.
