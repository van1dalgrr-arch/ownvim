package sdk

import (
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
)

// ErrPass — вернуть из обработчика клавиши (MapKey), если клавиша «не ваша»: ownvim выполнит то, что на ней
// висит обычно. Так enter на сервисе compose открывает меню, а на других строках работает как всегда.
var ErrPass = errors.New("клавиша — дальше")

// ── ответы от Lua: выбор из списка, ввод ─────────────────────────────────────

var (
	replyID atomic.Int64
	replies sync.Map // id → chan any
)

// ask — вызвать Lua-диалог и дождаться ответа (Lua зовёт ext.reply). Ждёт столько, сколько думает человек.
func (c *Ctx) ask(fn string, args ...any) any {
	id := replyID.Add(1)
	ch := make(chan any, 1)
	replies.Store(id, ch)
	defer replies.Delete(id)
	if err := c.lua(fn, nil, append([]any{id}, args...)...); err != nil {
		return nil
	}
	return <-ch
}

// Reply — ответ диалога из Lua (метод моста ext.reply).
func Reply(id int64, value any) {
	if ch, ok := replies.Load(id); ok {
		select {
		case ch.(chan any) <- value:
		default:
		}
	}
}

func toInt(v any) int {
	switch t := v.(type) {
	case int64:
		return int(t)
	case uint64:
		return int(t)
	case int:
		return t
	case float64:
		return int(t)
	}
	return 0
}

// Select — выбрать из списка (как vim.ui.select). Возвращает номер (с 0) и true; закрыли — -1 и false.
//
//	i, ok := c.Select("Что сделать с api", []string{"▶ up", "⟳ restart", "■ stop"})
func (c *Ctx) Select(prompt string, items []string) (int, bool) {
	n := toInt(c.ask("select", prompt, items))
	return n - 1, n > 0
}

// Input — спросить строку (как vim.ui.input); закрыли — "", false.
func (c *Ctx) Input(prompt, def string) (string, bool) {
	v := c.ask("input", prompt, def)
	s, ok := v.(string)
	return s, ok
}

// PickItem — строка списка Pick. File и Line — превью справа и куда перейти по enter.
type PickItem struct {
	Text  string // главный текст (по нему ищут)
	Hint  string // серым после текста
	Tag   string // слева, цветом TagColor (например, метод HTTP)
	Color string // цвет Tag: red, green, yellow, blue, purple, grey или группа подсветки
	File  string // файл для превью и перехода
	Line  int    // строка (с 1)
	Col   int    // столбец (с 1)
	Copy  string // ctrl-y — скопировать это в буфер обмена
}

// PickOpts — настройки списка.
type PickOpts struct {
	Definition bool              // enter: после перехода — к определению символа под курсором (через LSP)
	Keys       map[string]string // свои клавиши: {"<c-r>": "send"} — Pick вернёт "send" и выбранный пункт
}

// Pick — список с поиском и превью файла (как пробел пробел). enter — перейти к File:Line (и вернуть "open"),
// свои клавиши из opts.Keys — вернуть их имя; закрыли — -1, "".
//
//	i, action := c.Pick("Эндпоинты", items, sdk.PickOpts{Keys: map[string]string{"<c-r>": "send"}})
func (c *Ctx) Pick(title string, items []PickItem, opts PickOpts) (int, string) {
	list := make([]map[string]any, 0, len(items))
	for _, it := range items {
		list = append(list, map[string]any{"text": it.Text, "hint": it.Hint, "tag": it.Tag, "color": it.Color,
			"file": it.File, "line": it.Line, "col": it.Col, "copy": it.Copy})
	}
	keys := opts.Keys
	if keys == nil {
		keys = map[string]string{}
	}
	v, _ := c.ask("pick", title, list, map[string]any{"definition": opts.Definition, "keys": keys}).([]any)
	if len(v) != 2 {
		return -1, ""
	}
	action, _ := v[1].(string)
	return toInt(v[0]) - 1, action
}

// Terminal — запустить команду в терминале снизу (логи, shell, сборка — всё, что живёт и печатает).
func (c *Ctx) Terminal(cmd []string, cwd string) error {
	if cwd == "" {
		cwd = c.Root
	}
	return c.lua("terminal", nil, cmd, cwd)
}

// MapKey вешает клавишу только в текущем буфере (c.Buf). Обработчик вернул ErrPass — клавиша работает как обычно.
// mode — "n", "x" или "i".
func (c *Ctx) MapKey(mode, lhs, desc string, run Handler) error {
	id := fmt.Sprintf("%s|%s|%s", c.Ext, mode, lhs)
	mu.Lock()
	dynamic[id] = &command{Name: id, Ext: c.Ext, run: run}
	mu.Unlock()
	return c.lua("map", nil, c.Buf, mode, lhs, desc, id, c.Ext)
}

// SidePanel — панель справа с текстом; у расширения одна: открыта — перерисовывается (ответы HTTP и т.п.).
func (c *Ctx) SidePanel(title, text, ft string) error {
	return c.lua("side_panel", nil, c.Ext, title, splitLines(text), ft)
}

// CloseSidePanel — закрыть панель расширения.
func (c *Ctx) CloseSidePanel() error { return c.lua("close_side_panel", nil, c.Ext) }

// Clipboard — положить текст в системный буфер обмена.
func (c *Ctx) Clipboard(text string) error { return c.lua("clipboard", nil, text) }

// Feed — «нажать» клавиши после всего, что уже запрошено (например, "A" — во вставку в конце строки
// после c.Open). Как vim.api.nvim_feedkeys.
func (c *Ctx) Feed(keys string) error { return c.lua("feed", nil, keys) }

// SetCursor — поставить курсор (строка и столбец с 1) в текущем окне.
func (c *Ctx) SetCursor(line, col int) error { return c.lua("cursor", nil, line, col) }
