package httpfile

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/van1dalgrr-arch/ownvim/core/httpx"
)

const file = `@host = http://localhost:8080
@api = {{host}}/api

### Вход
# @name login
POST {{api}}/auth/login
Content-Type: application/json

{ "email": "a@b.c" }


### Профиль
GET {{api}}/me
Authorization: Bearer {{login.response.body.$.data.access_token}}
# комментарий в заголовках
X-Env: {{$env.OWN_TEST_ENV}}
`

func TestParse(t *testing.T) {
	reqs, vars := Parse(strings.Split(file, "\n"))
	if len(reqs) != 2 || vars["host"] != "http://localhost:8080" {
		t.Fatalf("запросы %d, переменные %v", len(reqs), vars)
	}
	login, me := reqs[0], reqs[1]
	if login.Name != "login" || login.Method != "POST" || login.Line != 6 || login.Body != `{ "email": "a@b.c" }` {
		t.Fatalf("login: %+v", login)
	}
	if me.Method != "GET" || len(me.Headers) != 2 {
		t.Fatalf("me: %+v", me)
	}
	if r, ok := At(reqs, 12); !ok || r.Method != "GET" {
		t.Fatalf("строка «### Профиль» (12) — это уже запрос GET, получил %+v", r)
	}
	if r, ok := At(reqs, 8); !ok || r.Name != "login" {
		t.Fatalf("строка 8 — внутри login, получил %+v", r)
	}
}

func TestExpand(t *testing.T) {
	t.Setenv("OWN_TEST_ENV", "dev")
	_, vars := Parse(strings.Split(file, "\n"))
	responses := map[string]any{"login": map[string]any{"data": map[string]any{"access_token": "T0K", "ids": []any{7.0, 8.0}}}}
	cases := map[string]string{
		"{{api}}/me": "http://localhost:8080/api/me",
		"Bearer {{login.response.body.$.data.access_token}}": "Bearer T0K",
		"{{login.response.body.$.data.ids.1}}":               "8",
		"{{$env.OWN_TEST_ENV}}":                              "dev",
		"{{unknown}}":                                        "{{unknown}}",
		"{{login.response.body.$.access_token}}":             "T0K", // нет в корне — найдено в data
	}
	for in, want := range cases {
		if got := Expand(in, vars, responses); got != want {
			t.Errorf("%s → %q, ждал %q", in, got, want)
		}
	}
}

func TestUnresolved(t *testing.T) {
	got := Unresolved("Bearer {{x.response.body.$.t}}", "{{x.response.body.$.t}}/a", "ok")
	if len(got) != 1 || got[0] != "{{x.response.body.$.t}}" {
		t.Fatalf("%v", got)
	}
}

func TestDoAndToken(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Content-Type") != "application/json" {
			w.WriteHeader(400)
			return
		}
		w.Write([]byte(`{"data":{"access_token":"abc"},"ok":true}`))
	}))
	defer srv.Close()
	resp, err := httpx.Do("POST", srv.URL+"/login", []httpx.Header{{Name: "Content-Type", Value: "application/json"}}, `{}`)
	if err != nil || resp.Status != 200 {
		t.Fatalf("ответ %d, %v", resp.Status, err)
	}
	if httpx.Token(resp.JSON) != "abc" {
		t.Fatalf("токен из data.access_token не найден")
	}
	if !strings.Contains(resp.Pretty(), "\n  \"data\": {") {
		t.Fatalf("JSON не отформатирован:\n%s", resp.Pretty())
	}
	if c := httpx.Curl("POST", "http://x/a", []httpx.Header{{Name: "A", Value: "it's"}}, `{"a":1}`); c != `curl -s -X POST -H 'A: it'\''s' --data-binary '{"a":1}' 'http://x/a'` {
		t.Fatalf("curl: %s", c)
	}
}
