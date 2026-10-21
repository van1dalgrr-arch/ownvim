// Package httpfile — Postman в файле: .http-запросы (формат VS Code REST Client / JetBrains HTTP Client).
// enter на запросе — отправить, ответ — в панели справа; esc — закрыть. пробел R: s — отправить, r — повторить
// последний, c — скопировать как curl, n / p — к следующему / предыдущему запросу.
// Ответы запросов с # @name запоминаются (и переживают перезапуск): {{login.response.body.$.access_token}}.
// Написано на sdk; запросы — net/http (без curl). Папка — http, чтобы модуль включался как раньше: "modules": { "http": … }.
package httpfile

import (
	"fmt"
	"maps"
	"strings"
	"sync"

	"github.com/van1dalgrr-arch/ownvim/core/httpx"
	"github.com/van1dalgrr-arch/ownvim/core/sdk"
)

var (
	mu        sync.Mutex
	responses = map[string]any{} // имя запроса → JSON ответа
	loaded    bool
	last      *sent // последний отправленный — для повтора
)

type sent struct {
	req  Request
	vars map[string]string
}

func init() {
	sdk.On("FileType", "http", func(c *sdk.Ctx) error {
		keys := []struct {
			lhs, desc string
			run       sdk.Handler
		}{
			{"<cr>", "HTTP: отправить запрос под курсором", send},
			{"<esc>", "HTTP: закрыть ответ", closePanel},
			{"<leader>Rs", "HTTP: отправить", send},
			{"<leader>Rr", "HTTP: повторить последний", replay},
			{"<leader>Rc", "HTTP: скопировать как curl", copyCurl},
			{"<leader>Rn", "HTTP: следующий запрос", func(c *sdk.Ctx) error { return jump(c, 1) }},
			{"<leader>Rp", "HTTP: предыдущий запрос", func(c *sdk.Ctx) error { return jump(c, -1) }},
		}
		for _, k := range keys {
			if err := c.MapKey("n", k.lhs, k.desc, k.run); err != nil {
				return err
			}
		}
		return nil
	})
}

// ответы с @name — из хранилища расширения (один раз за запуск ядра)
func loadResponses(c *sdk.Ctx) {
	mu.Lock()
	defer mu.Unlock()
	if loaded {
		return
	}
	loaded = true
	var saved map[string]any
	if c.Store().Get("responses", &saved) {
		maps.Copy(responses, saved)
	}
}

func current(c *sdk.Ctx) (Request, map[string]string, []Request, bool) {
	reqs, vars := Parse(c.Lines())
	r, ok := At(reqs, c.Line)
	return r, vars, reqs, ok
}

func send(c *sdk.Ctx) error {
	r, vars, _, ok := current(c)
	if !ok {
		c.Warn("курсор не на запросе")
		return nil
	}
	return run(c, r, vars)
}

func replay(c *sdk.Ctx) error {
	mu.Lock()
	l := last
	mu.Unlock()
	if l == nil {
		c.Warn("ещё ничего не отправлялось")
		return nil
	}
	return run(c, l.req, l.vars)
}

func expanded(r Request, vars map[string]string) (string, []httpx.Header, string) {
	mu.Lock()
	defer mu.Unlock()
	url := Expand(r.URL, vars, responses)
	var hs []httpx.Header
	for _, h := range r.Headers {
		hs = append(hs, httpx.Header{Name: h.Name, Value: Expand(h.Value, vars, responses)})
	}
	return url, hs, Expand(r.Body, vars, responses)
}

func run(c *sdk.Ctx, r Request, vars map[string]string) error {
	loadResponses(c)
	mu.Lock()
	last = &sent{req: r, vars: vars}
	mu.Unlock()
	url, headers, body := expanded(r, vars)
	parts := []string{url, body}
	for _, h := range headers {
		parts = append(parts, h.Value)
	}
	warn := ""
	if left := Unresolved(parts...); len(left) > 0 {
		warn = "// не подставлено: " + strings.Join(left, " ") + " — нет переменной или ответа (сначала отправьте запрос с этим @name)\n"
	}
	resp, err := httpx.Do(r.Method, url, headers, body)
	var text string
	if err != nil {
		text = fmt.Sprintf("// %s %s → нет ответа\n// %v\n// API запущен? пробел r r → go run / up", r.Method, url, err)
	} else {
		if r.Name != "" && resp.JSON != nil {
			mu.Lock()
			responses[r.Name] = resp.JSON
			snapshot := maps.Clone(responses)
			mu.Unlock()
			_ = c.Store().Set("responses", snapshot)
		}
		text = httpx.Head(r.Method, url, resp) + "\n" + resp.Pretty()
	}
	return c.SidePanel(r.Method+" "+url, warn+text, "json")
}

func closePanel(c *sdk.Ctx) error {
	_ = c.CloseSidePanel()
	return c.Command("nohlsearch")
}

func copyCurl(c *sdk.Ctx) error {
	r, vars, _, ok := current(c)
	if !ok {
		return nil
	}
	loadResponses(c)
	url, headers, body := expanded(r, vars)
	return c.Clipboard(httpx.Curl(r.Method, url, headers, body))
}

func jump(c *sdk.Ctx, dir int) error {
	_, _, reqs, _ := current(c)
	var lines []int
	for _, r := range reqs {
		if r.Line > 0 {
			lines = append(lines, r.Line)
		}
	}
	if dir < 0 {
		for i := len(lines) - 1; i >= 0; i-- {
			if lines[i] < c.Line {
				return c.SetCursor(lines[i], 1)
			}
		}
		return nil
	}
	for _, l := range lines {
		if l > c.Line {
			return c.SetCursor(l, 1)
		}
	}
	return nil
}
