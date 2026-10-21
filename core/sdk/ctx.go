package sdk

import (
	"fmt"
	"os"
	"strings"

	"github.com/neovim/go-client/nvim"
)

// Ctx — где и что происходит, когда сработала команда или событие, и что можно сделать с редактором.
// Строки везде с 1 — как номера слева в редакторе.
type Ctx struct {
	Ext      string         `json:"ext"`       // имя расширения (папка в core/extensions)
	Buf      int            `json:"buf"`       // номер буфера
	File     string         `json:"file"`      // полный путь файла ("" — не файл)
	Root     string         `json:"root"`      // корень проекта
	Filetype string         `json:"filetype"`  // go, python, yaml…
	Word     string         `json:"word"`      // слово под курсором
	Line     int            `json:"line"`      // строка курсора (с 1)
	Col      int            `json:"col"`       // столбец курсора (с 1)
	SelStart int            `json:"sel_start"` // выделенные строки (с 1); 0 — выделения нет
	SelEnd   int            `json:"sel_end"`
	Event    string         `json:"event"` // для On: BufWritePost…
	Match    string         `json:"match"` // для On: файл или имя, на котором сработало
	Settings map[string]any `json:"settings"`
	Args     map[string]any `json:"args"` // для Func: что передал Lua
	Data     string         `json:"data"` // данные ownvim (stdpath data) — для Store

	nv *nvim.Nvim
}

// lua — вызвать функцию из lua/own/ext.lua (api.<name>) с аргументами.
// Не вышло — запись в ~/.local/state/ownvim/ownvimd.log (stderr моста): тихих сбоев не бывает.
func (c *Ctx) lua(name string, result any, args ...any) error {
	err := c.nv.ExecLua("return require('own.ext').api."+name+"(...)", result, args...)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: api.%s: %v\n", c.Ext, name, err)
	}
	return err
}

// Nvim — полный клиент Neovim для всего, чего нет ниже (буферы, окна, опции, любые вызовы API).
func (c *Ctx) Nvim() *nvim.Nvim { return c.nv }

// ── текст ────────────────────────────────────────────────────────────────────

// Lines — все строки буфера.
func (c *Ctx) Lines() []string {
	var out []string
	_ = c.lua("lines", &out, c.Buf, 1, -1)
	return out
}

// LinesRange — строки с from по to включительно (с 1).
func (c *Ctx) LinesRange(from, to int) []string {
	var out []string
	_ = c.lua("lines", &out, c.Buf, from, to)
	return out
}

// SetLines заменяет строки с from по to включительно (с 1) на lines. Весь файл — SetLines(1, -1, …).
func (c *Ctx) SetLines(from, to int, lines []string) error {
	return c.lua("set_lines", nil, c.Buf, from, to, lines)
}

// CurrentLine — строка под курсором.
func (c *Ctx) CurrentLine() string {
	if l := c.LinesRange(c.Line, c.Line); len(l) > 0 {
		return l[0]
	}
	return ""
}

// Selection — выделенные строки одним текстом ("" — выделения нет).
func (c *Ctx) Selection() string {
	if c.SelStart == 0 {
		return ""
	}
	return strings.Join(c.LinesRange(c.SelStart, c.SelEnd), "\n")
}

// ReplaceSelection заменяет выделенные строки текстом (переводы строк — новые строки).
func (c *Ctx) ReplaceSelection(text string) error {
	if c.SelStart == 0 {
		return fmt.Errorf("нет выделения")
	}
	return c.SetLines(c.SelStart, c.SelEnd, strings.Split(text, "\n"))
}

// InsertBelow вставляет текст строками ниже курсора.
func (c *Ctx) InsertBelow(text string) error {
	return c.SetLines(c.Line+1, c.Line, strings.Split(text, "\n"))
}

// ── показать ─────────────────────────────────────────────────────────────────

// Notify — уведомление (как fmt.Sprintf).
func (c *Ctx) Notify(format string, args ...any) {
	_ = c.lua("notify", nil, fmt.Sprintf(format, args...), "info", c.Ext)
}

// Warn — предупреждение.
func (c *Ctx) Warn(format string, args ...any) {
	_ = c.lua("notify", nil, fmt.Sprintf(format, args...), "warn", c.Ext)
}

// Window — показать текст в окне снизу (q — закрыть). ft — подсветка: "markdown", "json", "go" или "".
func (c *Ctx) Window(title, text, ft string) error {
	return c.lua("window", nil, title, strings.Split(text, "\n"), ft)
}

// Mark — надпись справа от строки, как статусы в compose.yaml.
type Mark struct {
	Line  int    // строка (с 1)
	Text  string // что написать
	Color string // red, orange, yellow, green, blue, purple, grey — или группа подсветки ("Comment")
	Right bool   // прижать к правому краю окна (а не сразу за текстом строки)
	Parts []Part // надпись из разноцветных кусков (вместо Text/Color): ● работает · здоров · :8080
}

// Part — кусок надписи своего цвета.
type Part struct {
	Text  string
	Color string
}

// Marks ставит надписи в текущем буфере; прошлые надписи этого расширения в нём — убираются.
// Marks(nil) — просто убрать.
func (c *Ctx) Marks(marks []Mark) error {
	list := make([]map[string]any, 0, len(marks))
	for _, m := range marks {
		parts := []map[string]any{}
		for _, p := range m.Parts {
			parts = append(parts, map[string]any{"text": p.Text, "color": p.Color})
		}
		list = append(list, map[string]any{"line": m.Line, "text": m.Text, "color": m.Color, "right": m.Right, "parts": parts})
	}
	return c.lua("marks", nil, c.Buf, c.Ext, list)
}

// Problem — замечание на строке, как ошибка линтера: подчёркивание, плашка, «Проблемы» в нижней панели.
type Problem struct {
	Line     int    // строка (с 1)
	Col      int    // столбец (с 1; 0 — вся строка с начала)
	Message  string // текст
	Severity string // error, warn, info, hint ("" — warn)
}

// Problems ставит замечания в текущем буфере; прошлые замечания этого расширения в нём — убираются.
func (c *Ctx) Problems(ps []Problem) error {
	list := make([]map[string]any, 0, len(ps))
	for _, p := range ps {
		list = append(list, map[string]any{"line": p.Line, "col": p.Col, "message": p.Message, "severity": p.Severity})
	}
	return c.lua("problems", nil, c.Buf, c.Ext, list)
}

// ── действовать ──────────────────────────────────────────────────────────────

// Open открывает файл на строке (line 0 — не двигать курсор).
func (c *Ctx) Open(file string, line int) error { return c.lua("open", nil, file, line) }

// Command выполняет команду Vim: "write", "split", "Lazy"…
func (c *Ctx) Command(cmd string) error { return c.nv.Command(cmd) }

// Setting — значение из settings.jsonc: "extensions": { "<имя>": { key: … } }; нет — def.
func (c *Ctx) Setting(key string, def any) any {
	if v, ok := c.Settings[key]; ok {
		return v
	}
	return def
}

// SettingInt — то же для чисел (JSON отдаёт числа как float64).
func (c *Ctx) SettingInt(key string, def int) int {
	switch v := c.Settings[key].(type) {
	case float64:
		return int(v)
	case int64:
		return int(v)
	case int:
		return v
	}
	return def
}
