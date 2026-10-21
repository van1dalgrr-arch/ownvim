package endpoints

import (
	"os"
	"path/filepath"
	"testing"
)

const mainGo = `package main

import "github.com/gin-gonic/gin"

func main() {
	r := gin.Default()
	r.GET("/health", handler.Health(db))
	api := r.Group("/api")
	v1 := api.Group("/v1")
	v1.POST("/auth/login", auth.Login)
	registerUsers(v1.Group("/users"))
	r.Group("/admin").DELETE("/cache", func(c *gin.Context) {})
}
`

const usersGo = `package main

import "github.com/gin-gonic/gin"

func registerUsers(g *gin.RouterGroup) {
	g.GET("", users.List)
	g.GET("/:id", users.Get)
	registerAvatars(g.Group("/:id/avatar"))
}

func registerAvatars(a *gin.RouterGroup) {
	a.PUT("", avatars.Upload)
}
`

func TestCollect(t *testing.T) {
	root := t.TempDir()
	for name, src := range map[string]string{"main.go": mainGo, "users.go": usersGo, "x_test.go": `package main`} {
		if err := os.WriteFile(filepath.Join(root, name), []byte(src), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	got := map[string]Route{}
	for _, r := range Collect(root) {
		got[r.Method+" "+r.Path] = r
	}
	want := map[string]string{
		"GET /health":                  "handler.Health",
		"POST /api/v1/auth/login":      "auth.Login",
		"GET /api/v1/users":            "users.List",
		"GET /api/v1/users/:id":        "users.Get",
		"PUT /api/v1/users/:id/avatar": "avatars.Upload",
		"DELETE /admin/cache":          "func",
	}
	for route, handler := range want {
		r, ok := got[route]
		if !ok {
			t.Errorf("нет маршрута %s (есть: %v)", route, keys(got))
			continue
		}
		if r.Handler != handler {
			t.Errorf("%s: хендлер %q, ждал %q", route, r.Handler, handler)
		}
	}
	if len(got) != len(want) {
		t.Errorf("маршрутов %d, ждал %d: %v", len(got), len(want), keys(got))
	}
	// курсор — на имени хендлера: users.Get → на Get
	if r := got["GET /api/v1/users/:id"]; r.Line != 7 || r.Col != 22 {
		t.Errorf("место хендлера: %d:%d, ждал 7:22", r.Line, r.Col)
	}
}

func keys(m map[string]Route) []string {
	var out []string
	for k := range m {
		out = append(out, k)
	}
	return out
}

func TestExamplePath(t *testing.T) {
	if got := ExamplePath("/users/:id/files/*rest"); got != "/users/1/files/" {
		t.Fatalf("%q", got)
	}
}
