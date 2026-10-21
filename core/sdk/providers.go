package sdk

import (
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"

	"github.com/neovim/go-client/nvim"
)

// Провайдеры — расширение как встроенный языковой сервер: его подсказки появляются в обычном меню дополнения,
// описание — по K, исправления — в пробел ca, рядом с gopls и rust-analyzer. ownvim подключает «сервер» ownvim
// к файлам тех типов, для которых есть провайдеры.

// CompletionItem — подсказка дополнения.
type CompletionItem struct {
	Label  string // что видно в меню
	Insert string // что вставить ("" — Label); со Snippet: true — сниппет: ${1:имя}, $0
	Detail string // серым справа
	Doc    string // описание (markdown) — рядом с меню
	Kind   string // function, method, variable, field, constant, keyword, snippet, file, module, value, text
	Snipp  bool   // Insert — сниппет
}

// Action — исправление или действие с кодом для пробел ca.
type Action struct {
	Title string
	Kind  string  // quickfix (по умолчанию), refactor, source
	Run   Handler // что сделать, когда выбрали
}

type provider struct {
	Kind      string   `json:"kind"` // completion, hover, actions
	ID        string   `json:"id"`
	Ext       string   `json:"ext"`
	Filetypes []string `json:"filetypes"`
	Triggers  []string `json:"triggers,omitempty"` // символы, после которых показывать дополнение
	complete  func(c *Ctx, prefix string) []CompletionItem
	hover     func(c *Ctx) string
	actions   func(c *Ctx) []Action
}

var providers []*provider

func splitList(s string) []string {
	var out []string
	for p := range strings.SplitSeq(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

func addProvider(p *provider) {
	mu.Lock()
	defer mu.Unlock()
	p.ID = fmt.Sprintf("%s:%s:%d", p.Ext, p.Kind, len(providers))
	providers = append(providers, p)
}

// Completion — свои подсказки дополнения для файлов filetypes ("go", "yaml,json", "*" — для всех).
// prefix — слово перед курсором; triggers — символы, после которых подсказывать сразу ("$", "{", ".").
//
//	sdk.Completion("yaml", "$,{", func(c *sdk.Ctx, prefix string) []sdk.CompletionItem {
//		return []sdk.CompletionItem{{Label: "API_TOKEN", Detail: ".env", Kind: "variable"}}
//	})
func Completion(filetypes, triggers string, fn func(c *Ctx, prefix string) []CompletionItem) {
	var tr []string
	for _, ch := range triggers {
		if ch != ',' && ch != ' ' {
			tr = append(tr, string(ch))
		}
	}
	addProvider(&provider{Kind: "completion", Ext: extOf(), Filetypes: splitList(filetypes), Triggers: tr, complete: fn})
}

// Hover — описание по K для файлов filetypes: вернуть markdown ("" — нечего сказать, пусть говорят другие).
func Hover(filetypes string, fn func(c *Ctx) string) {
	addProvider(&provider{Kind: "hover", Ext: extOf(), Filetypes: splitList(filetypes), hover: fn})
}

// CodeActions — исправления для пробел ca: что предложить для строки курсора (или выделения).
func CodeActions(filetypes string, fn func(c *Ctx) []Action) {
	addProvider(&provider{Kind: "actions", Ext: extOf(), Filetypes: splitList(filetypes), actions: fn})
}

func providerByID(id string) *provider {
	mu.Lock()
	defer mu.Unlock()
	for _, p := range providers {
		if p.ID == id {
			return p
		}
	}
	return nil
}

func ctxFrom(v *nvim.Nvim, data map[string]any) *Ctx {
	c := &Ctx{nv: v}
	if raw, err := json.Marshal(data); err == nil {
		_ = json.Unmarshal(raw, c)
	}
	return c
}

// провайдер упал — не ронять ни ядро, ни запрос редактора: пустой ответ и запись в лог моста
func guard(c *Ctx, what string) {
	if r := recover(); r != nil {
		c.Warn("%s: паника — %v\n%s", what, r, where())
	}
}

var kinds = map[string]int{"text": 1, "method": 2, "function": 3, "constructor": 4, "field": 5, "variable": 6,
	"class": 7, "interface": 8, "module": 9, "property": 10, "unit": 11, "value": 12, "enum": 13, "keyword": 14,
	"snippet": 15, "color": 16, "file": 17, "reference": 18, "folder": 19, "constant": 21, "struct": 22}

// Complete — метод моста ext.complete: подсказки провайдера id (в формате LSP CompletionItem).
func Complete(v *nvim.Nvim, id string, data map[string]any, prefix string) ([]map[string]any, error) {
	p := providerByID(id)
	c := ctxFrom(v, data)
	out := []map[string]any{}
	if p == nil || p.complete == nil {
		return out, nil
	}
	defer guard(c, "дополнение "+p.Ext)
	for _, it := range p.complete(c, prefix) {
		item := map[string]any{"label": it.Label, "kind": kinds[it.Kind]}
		if item["kind"] == 0 {
			item["kind"] = 1
		}
		if it.Insert != "" {
			item["insertText"] = it.Insert
		}
		if it.Snipp {
			item["insertTextFormat"] = 2
		}
		if it.Detail != "" {
			item["detail"] = it.Detail
		}
		if it.Doc != "" {
			item["documentation"] = map[string]any{"kind": "markdown", "value": it.Doc}
		}
		out = append(out, item)
	}
	return out, nil
}

// HoverText — метод моста ext.hover.
func HoverText(v *nvim.Nvim, id string, data map[string]any) (text string, err error) {
	p := providerByID(id)
	c := ctxFrom(v, data)
	if p == nil || p.hover == nil {
		return "", nil
	}
	defer guard(c, "описание "+p.Ext)
	return p.hover(c), nil
}

var actionSeq atomic.Int64
var actionMu sync.Mutex
var pending = map[string]*command{} // выбранное в пробел ca выполнит ext.run

// Actions — метод моста ext.actions: исправления провайдера id ({title, kind, id}); id — для ext.run.
func Actions(v *nvim.Nvim, id string, data map[string]any) ([]map[string]any, error) {
	p := providerByID(id)
	c := ctxFrom(v, data)
	out := []map[string]any{}
	if p == nil || p.actions == nil {
		return out, nil
	}
	defer guard(c, "исправления "+p.Ext)
	actionMu.Lock()
	defer actionMu.Unlock()
	if len(pending) > 500 { // старые предложения больше не выберут
		pending = map[string]*command{}
	}
	for _, a := range p.actions(c) {
		aid := fmt.Sprintf("action:%d", actionSeq.Add(1))
		pending[aid] = &command{Name: a.Title, Ext: p.Ext, run: a.Run}
		kind := a.Kind
		if kind == "" {
			kind = "quickfix"
		}
		out = append(out, map[string]any{"title": a.Title, "kind": kind, "id": aid})
	}
	return out, nil
}

func pendingAction(id string) *command {
	actionMu.Lock()
	defer actionMu.Unlock()
	return pending[id]
}
