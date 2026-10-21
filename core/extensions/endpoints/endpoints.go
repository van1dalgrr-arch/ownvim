// Package endpoints — эндпоинты Gin, как окно Endpoints в GoLand: все маршруты проекта с полным путём.
//
//	:Endpoints (пробел r e, alt-a) — список с поиском и превью: enter — к хендлеру (и к его определению через gopls),
//	  ctrl-r — отправить запрос на запущенный API (ответ справа), ctrl-y — скопировать curl.
//	:ApiHttp (пробел r h, alt-p) — api.http проекта из маршрутов (Postman в файле; готовый не перезаписывается).
//
// Маршруты — настоящим разбором Go-кода (go/ast): группы по цепочке и группы, переданные в другие функции.
package endpoints

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/van1dalgrr-arch/ownvim/core/httpx"
	"github.com/van1dalgrr-arch/ownvim/core/sdk"
)

var (
	mu       sync.Mutex
	apiToken string // access_token из последнего ответа — в Authorization следующих запросов
)

var colors = map[string]string{"GET": "green", "POST": "yellow", "PUT": "blue", "PATCH": "blue", "DELETE": "red"}

func method(r Route) string {
	if r.Method == "ANY" {
		return "GET"
	}
	return r.Method
}

func init() {
	sdk.Command("Endpoints", "Эндпоинты API (Gin): enter — хендлер, ctrl-r — запрос, ctrl-y — curl", pick)
	sdk.Command("ApiHttp", "api.http — запросы ко всем маршрутам проекта", apiHTTP)
}

func pick(c *sdk.Ctx) error {
	routes := Collect(c.Root)
	if len(routes) == 0 {
		c.Warn("маршрутов Gin не нашёл в %s", c.Root)
		return nil
	}
	port := httpx.Port(c.Root)
	items := make([]sdk.PickItem, len(routes))
	for i, r := range routes {
		items[i] = sdk.PickItem{Tag: r.Method, Color: colors[r.Method], Text: r.Path, Hint: "→ " + r.Handler,
			File: r.File, Line: r.Line, Col: r.Col,
			Copy: fmt.Sprintf("curl -s -X %s localhost:%s%s | jq .", method(r), port, ExamplePath(r.Path))}
	}
	i, action := c.Pick("Эндпоинты · enter — хендлер · ctrl-r — запрос · ctrl-y — curl", items,
		sdk.PickOpts{Definition: true, Keys: map[string]string{"<c-r>": "send"}})
	if i < 0 || action != "send" {
		return nil
	}
	return send(c, routes[i], port)
}

func send(c *sdk.Ctx, r Route, port string) error {
	m := method(r)
	body := ""
	if m == "POST" || m == "PUT" || m == "PATCH" {
		var last string
		if !c.Store().Get("body:"+m+r.Path, &last) {
			last = "{}"
		}
		b, ok := c.Input(m+" "+r.Path+" · тело JSON:", last)
		if !ok {
			return nil
		}
		body = b
		_ = c.Store().Set("body:"+m+r.Path, body)
	}
	url := "http://localhost:" + port + ExamplePath(r.Path)
	var headers []httpx.Header
	mu.Lock()
	if apiToken != "" {
		headers = append(headers, httpx.Header{Name: "Authorization", Value: "Bearer " + apiToken})
	}
	mu.Unlock()
	if body != "" {
		headers = append(headers, httpx.Header{Name: "Content-Type", Value: "application/json"})
	}
	resp, err := httpx.Do(m, url, headers, body)
	if err != nil {
		return fmt.Errorf("%v\nAPI запущен? пробел r r → go run / up", err)
	}
	if t := httpx.Token(resp.JSON); t != "" {
		mu.Lock()
		apiToken = t
		mu.Unlock()
		c.Notify("токен запомнен для следующих запросов")
	}
	return c.SidePanel(m+" "+r.Path, httpx.Head(m, ExamplePath(r.Path), resp)+"\n"+resp.Pretty(), "json")
}

// apiHTTP — api.http: логин получает имя login, остальные берут его access_token в Authorization
func apiHTTP(c *sdk.Ctx) error {
	dest := filepath.Join(c.Root, "api.http")
	if _, err := os.Stat(dest); err == nil {
		c.Notify("api.http уже есть — открываю (новый: удалите файл и :ApiHttp)")
		return c.Open(dest, 0)
	}
	routes := Collect(c.Root)
	if len(routes) == 0 {
		c.Warn("маршрутов Gin не нашёл в %s", c.Root)
		return nil
	}
	var login *Route
	for i, r := range routes {
		if r.Method == "POST" && strings.HasSuffix(r.Path, "login") {
			login = &routes[i]
		}
	}
	lines := []string{
		"# Как пользоваться: курсор на запрос → enter — ответ справа, esc — закрыть.",
		"# Сгенерировано из маршрутов (:ApiHttp); дальше файл ваш — правьте тела и параметры.",
		"@host = http://localhost:" + httpx.Port(c.Root),
	}
	add := func(r Route) {
		lines = append(lines, "", fmt.Sprintf("### %s %s → %s", r.Method, r.Path, r.Handler))
		if login != nil && r == *login {
			lines = append(lines, "# @name login")
		}
		lines = append(lines, method(r)+" {{host}}"+ExamplePath(r.Path))
		if login != nil && r != *login && !strings.HasSuffix(r.Path, "register") && !strings.HasSuffix(r.Path, "refresh") {
			lines = append(lines, "Authorization: Bearer {{login.response.body.$.access_token}}")
		}
		if r.Method == "POST" || r.Method == "PUT" || r.Method == "PATCH" {
			lines = append(lines, "Content-Type: application/json", "", "{}")
		}
	}
	if login != nil {
		add(*login)
	}
	for _, r := range routes {
		if login == nil || r != *login {
			add(r)
		}
	}
	if err := os.WriteFile(dest, []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
		return err
	}
	c.Notify("api.http: %d запросов", len(routes))
	return c.Open(dest, 0)
}
