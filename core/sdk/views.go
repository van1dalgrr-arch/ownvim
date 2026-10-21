package sdk

import (
	"fmt"
	"sync"
)

// ── панели ───────────────────────────────────────────────────────────────────

// Row — строка панели.
type Row struct {
	Text  string // текст строки
	Parts []Part // или разноцветные куски вместо Text
	Depth int    // отступ (дерево)
	File  string // enter — открыть этот файл…
	Line  int    // …на этой строке (с 1)
	Key   string // свой ключ строки — для своих клавиш (RowKey)
}

// RowKey — своя клавиша панели: что сделать со строкой под курсором.
type RowKey struct {
	Desc string
	Run  func(c *Ctx, row Row) error
}

// ViewSpec — панель, как «Тесты» или «Структура» в IDE: окно сбоку или снизу со строками.
type ViewSpec struct {
	Title string                              // в заголовке окна
	Side  string                              // left, right (по умолчанию), bottom
	Size  int                                 // ширина (или высота снизу); 0 — 40 / 12
	Rows  func(c *Ctx) []Row                  // что показать (зовётся при открытии и c.RefreshView)
	Keys  map[string]RowKey                   // свои клавиши: {"r": {"перезапустить", func…}}
	Open  func(c *Ctx, row Row) (bool, error) // свой enter (false — сделать обычное: открыть File:Line)
}

type view struct {
	name string
	ext  string
	spec ViewSpec
	mu   sync.Mutex
	rows []Row
}

var (
	viewsMu sync.Mutex
	views   = map[string]*view{}
)

// View регистрирует панель name. Открыть — c.ShowView(name) / c.ToggleView(name) или :View name;
// обновить, если открыта, — c.RefreshView(name). В панели: enter — к File:Line, q — закрыть, R — обновить.
func View(name string, spec ViewSpec) {
	ext := extOf()
	viewsMu.Lock()
	views[name] = &view{name: name, ext: ext, spec: spec}
	viewsMu.Unlock() // не держать две блокировки сразу: GetManifest берёт их в обратном порядке
	// показать панель из Lua (:View name) — как функции моста
	mu.Lock()
	funcs["view:"+name] = &command{Name: "view:" + name, Ext: ext, run: func(c *Ctx) error { return c.ToggleView(name) }}
	funcs["view.show:"+name] = &command{Name: "view.show:" + name, Ext: ext, run: func(c *Ctx) error { return c.ShowView(name) }}
	mu.Unlock()
}

func viewNames() []string {
	viewsMu.Lock()
	defer viewsMu.Unlock()
	var out []string
	for n := range views {
		out = append(out, n)
	}
	return out
}

func getView(name string) *view {
	viewsMu.Lock()
	defer viewsMu.Unlock()
	return views[name]
}

func (c *Ctx) renderView(name string, mode string) error {
	v := getView(name)
	if v == nil {
		return fmt.Errorf("нет панели %q", name)
	}
	cc := *c
	cc.Ext = v.ext
	rows := v.spec.Rows(&cc)
	v.mu.Lock()
	v.rows = rows
	v.mu.Unlock()
	list := make([]map[string]any, 0, len(rows))
	for _, r := range rows {
		parts := []map[string]any{}
		for _, p := range r.Parts {
			parts = append(parts, map[string]any{"text": p.Text, "color": p.Color})
		}
		list = append(list, map[string]any{"text": r.Text, "parts": parts, "depth": r.Depth, "file": r.File, "line": r.Line})
	}
	keys := map[string]string{}
	for lhs, k := range v.spec.Keys {
		keys[lhs] = k.Desc
		key := k
		mu.Lock()
		dynamic[viewKeyID(name, lhs)] = &command{Name: name + " " + lhs, Ext: v.ext, run: func(c *Ctx) error {
			row, ok := v.rowAt(c)
			if !ok {
				return nil
			}
			return key.Run(c, row)
		}}
		mu.Unlock()
	}
	custom := v.spec.Open != nil
	if custom {
		mu.Lock()
		dynamic[viewKeyID(name, "<cr>")] = &command{Name: name + " enter", Ext: v.ext, run: func(c *Ctx) error {
			row, ok := v.rowAt(c)
			if !ok {
				return nil
			}
			handled, err := v.spec.Open(c, row)
			if err == nil && !handled && row.File != "" {
				return c.Open(row.File, row.Line)
			}
			return err
		}}
		mu.Unlock()
	}
	side, size := v.spec.Side, v.spec.Size
	if side == "" {
		side = "right"
	}
	return c.lua("view", nil, v.ext, name, v.spec.Title, side, size, list, keys, custom, mode)
}

func viewKeyID(name, lhs string) string { return "view|" + name + "|" + lhs }

// rowAt — строка панели, на которой нажали клавишу (Lua передаёт её номер в c.Args["row"])
func (v *view) rowAt(c *Ctx) (Row, bool) {
	i := toInt(c.Args["row"]) - 1
	v.mu.Lock()
	defer v.mu.Unlock()
	if i < 0 || i >= len(v.rows) {
		return Row{}, false
	}
	return v.rows[i], true
}

// ShowView — открыть панель (или перерисовать, если открыта).
func (c *Ctx) ShowView(name string) error { return c.renderView(name, "show") }

// ToggleView — открыть или закрыть.
func (c *Ctx) ToggleView(name string) error { return c.renderView(name, "toggle") }

// RefreshView — перерисовать, если панель открыта (закрытую не трогает).
func (c *Ctx) RefreshView(name string) error { return c.renderView(name, "refresh") }

// ── статусная строка ─────────────────────────────────────────────────────────

// SetStatus — надпись расширения в статусной строке (блок ext): text "" — убрать. color — red, green, yellow…
// filetypes — показывать, только когда открыт файл этих типов ("go"), "" — всегда.
func (c *Ctx) SetStatus(text, color, filetypes string) error {
	return c.lua("status", nil, c.Ext, text, color, splitList(filetypes))
}

// ── замечания в любом файле ──────────────────────────────────────────────────

// ProblemsFor — замечания расширения в файле path (если он открыт); прошлые замечания расширения в нём — убираются.
func (c *Ctx) ProblemsFor(path string, ps []Problem) error {
	list := make([]map[string]any, 0, len(ps))
	for _, p := range ps {
		list = append(list, map[string]any{"line": p.Line, "col": p.Col, "message": p.Message, "severity": p.Severity})
	}
	return c.lua("problems_file", nil, path, c.Ext, list)
}
