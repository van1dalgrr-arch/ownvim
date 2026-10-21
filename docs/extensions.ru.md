# Свои расширения для ownvim на Python

[← Документация](README.md)

Расширение — обычный Python-скрипт: **читает текст из stdin, пишет результат в stdout**. ownvim передаёт ему
выделение/файл/строку и делает с ответом то, что указано в `settings.jsonc`. Neovim и Lua знать не нужно.

## Быстрый старт (3 шага)

1. В ownvim: `:ExtensionNew my_tool` — создаст `extensions/my_tool.py` с заготовкой и строку в `settings.jsonc`.
2. Напиши логику в `extensions/my_tool.py`, сохрани.
3. Выдели текст → `пробел C` → выбери `my_tool`. Или повесь клавишу (см. ниже).

## Как устроено

Файлы — в папке ownvim (`~/dev/ownvim`):

```
extensions/my_tool.py     твой скрипт
settings.jsonc            раздел "commands" — как его запускать
```

Описание команды в `settings.jsonc`:

```jsonc
"commands": {
  "Моя команда": {
    "run": "python3 extensions/my_tool.py",  // любая команда shell; extensions/ — папка ownvim
    "input": "selection",   // что получит скрипт в stdin
    "output": "replace",    // что сделать с его stdout
    "key": "x <leader>xm",  // клавиша (необязательно): режимы + клавиша
    "ft": ["go", "python"]  // только для этих типов файлов (необязательно)
  }
}
```

| `input` | что в stdin | | `output` | что делает с stdout |
|---|---|---|---|---|
| `selection` | выделенные строки | | `replace` | заменяет то, что было на входе |
| `file` | весь файл | | `insert` | вставляет строками ниже курсора |
| `line` | текущая строка | | `window` | показывает в окне снизу (`q` — закрыть) |
| `word` | слово под курсором | | `notify` | всплывающее уведомление |
| `none` | пусто | | `none` | ничего (скрипт делает своё сам) |

Режимы в `key`: `n` — обычный, `x` — выделение, `i` — вставка (можно `nx`). `<leader>` — пробел.

Переменные окружения, которые получает скрипт:

| переменная | что |
|---|---|
| `OWN_FILE` | полный путь к открытому файлу |
| `OWN_LINE` | номер строки курсора |
| `OWN_ROOT` | корень проекта (там же скрипт и запускается) |
| `OWN_FILETYPE` | тип файла: `go`, `python`, `cpp`… |
| `OWN_WORD` | слово под курсором |

Правила:
- ответ — в `stdout`; лишний перевод строки в конце убирается сам;
- ошибка — `sys.exit(1)` и текст в `stderr`: ownvim покажет его, текст в файле не тронет;
- можно `pip install` что угодно, можно ходить в сеть, базу, запускать программы;
- сохранил скрипт — новая версия работает сразу; поменял `settings.jsonc` — сохрани его, клавиши обновятся.

## Примеры (уже лежат в `extensions/`)

```python
# extensions/sort_lines.py — сортирует выделенные строки (пробел x s в выделении)
import sys
lines = sys.stdin.read().split("\n")
print("\n".join(sorted(lines, key=str.lower)), end="")
```

```python
# extensions/file_info.py — уведомление: имя файла и число строк (пробел x i)
import os, sys
text = sys.stdin.read()
print(f"{os.path.basename(os.environ['OWN_FILE'])}: {len(text.splitlines())} строк")
```

## Как попросить ChatGPT написать расширение

Скопируй ему этот текст целиком и допиши свою задачу:

```
Напиши расширение для моего редактора ownvim. Правила:
- Это Python 3 скрипт. Входной текст приходит в stdin, результат печатай в stdout (print(..., end="")).
- Ошибку сообщай так: print("текст", file=sys.stderr); sys.exit(1).
- Доступны переменные окружения: OWN_FILE (путь к файлу), OWN_LINE (номер строки), OWN_ROOT (корень проекта,
  он же текущая папка), OWN_FILETYPE (go, python, cpp…), OWN_WORD (слово под курсором).
- Скрипт лежит в extensions/<имя>.py.
- Ещё дай строку для settings.jsonc в разделе "commands" в формате:
  "Название": { "run": "python3 extensions/<имя>.py", "input": "selection|file|line|word|none",
                "output": "replace|insert|window|notify|none", "key": "x <leader>x<буква>", "ft": ["go"] }
  input — что подать в stdin, output — что сделать с ответом (replace — заменить вход, insert — вставить ниже,
  window — показать в окне, notify — уведомление).

Задача: <опиши, что должно происходить>
```

Ответ ChatGPT: скрипт положи в `~/dev/ownvim/extensions/<имя>.py`, строку — в `settings.jsonc` внутрь `"commands": { … }`,
сохрани оба файла. Проверка: `пробел C` → твоя команда.

Если не работает — в ownvim `:messages` (текст ошибки) и `:OwnHealth`. Отдай ChatGPT скрипт, строку из
`settings.jsonc` и текст ошибки.

## Если нужно больше (позже)

Скрипт-команда не умеет сам реагировать на события (сохранение файла, открытие) и рисовать свои окна. Для этого
нужны плагины на pynvim — в ownvim этого пока нет, скажи, когда понадобится.
