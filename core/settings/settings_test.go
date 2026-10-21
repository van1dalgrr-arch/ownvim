package settings

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestMerge(t *testing.T) {
	cases := []struct {
		name             string
		base, over, want any
	}{
		{"объекты — по ключам", map[string]any{"a": 1.0, "b": 2.0}, map[string]any{"b": 3.0},
			map[string]any{"a": 1.0, "b": 3.0}},
		{"вложенные объекты", map[string]any{"s": map[string]any{"x": 1.0, "y": 2.0}}, map[string]any{"s": map[string]any{"y": 9.0}},
			map[string]any{"s": map[string]any{"x": 1.0, "y": 9.0}}},
		{"список заменяется целиком", []any{"a", "b"}, []any{"c"}, []any{"c"}},
		{"true поверх объекта оставляет объект", map[string]any{"x": 1.0}, true, map[string]any{"x": 1.0}},
		{"false поверх объекта — false", map[string]any{"x": 1.0}, false, false},
		{"{} поверх объекта ничего не стирает", map[string]any{"x": 1.0}, map[string]any{}, map[string]any{"x": 1.0}},
		{"нет значения — остаётся база", 5.0, nil, 5.0},
		{"list+ дописывает", map[string]any{"list": []any{"a"}}, map[string]any{"list+": []any{"b"}},
			map[string]any{"list": []any{"a", "b"}}},
		{"list и list+ в одном слое", map[string]any{"list": []any{"a"}}, map[string]any{"list": []any{"x"}, "list+": []any{"y"}},
			map[string]any{"list": []any{"x", "y"}}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := merge(c.base, c.over); !reflect.DeepEqual(got, c.want) {
				t.Fatalf("получил %#v, ждал %#v", got, c.want)
			}
		})
	}
}

// проект в папке теста: defaults.jsonc, settings.jsonc, модуль, список опций
func fixture(t *testing.T, defaults, user string) Paths {
	t.Helper()
	p := Paths{Config: t.TempDir(), Data: t.TempDir()}
	write := func(path, text string) {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write(p.Defaults(), defaults)
	if user != "" {
		write(p.User(), user)
	}
	write(filepath.Join(p.Modules(), "lsp.lua"), "return {}")
	write(p.Options(), `{"names": ["number", "nu", "wrap"]}`)
	return p
}

func TestLoad(t *testing.T) {
	p := fixture(t,
		`{ "theme": "dev-night", "modules": { "lsp": true }, "options": { "number": true } }`,
		`{
  "theme": "sunset", // своя тема
  "options": { "wrapp": true },
  "modules": { "nope": true },
  "themee": 1,
}`)
	r := Load(p)
	if r.Error != "" {
		t.Fatalf("ошибка: %s", r.Error)
	}
	if r.Settings["theme"] != "sunset" {
		t.Fatalf("тема %v, ждал sunset", r.Settings["theme"])
	}
	if opts := r.Settings["options"].(map[string]any); opts["number"] != true {
		t.Fatalf("умолчание number потерялось: %#v", opts)
	}
	msgs := []string{}
	for _, pr := range r.Problems[p.User()] {
		msgs = append(msgs, pr.Message)
	}
	all := strings.Join(msgs, "\n")
	for _, want := range []string{`неизвестный раздел "themee"`, `нет модуля "nope"`, `у nvim нет опции "wrapp"`} {
		if !strings.Contains(all, want) {
			t.Errorf("нет замечания %q среди:\n%s", want, all)
		}
	}
}

func TestLoadBrokenUser(t *testing.T) {
	p := fixture(t, `{ "theme": "dev-night" }`, "{\n  \"theme\": \"x\"\n  \"a\": 1\n}")
	r := Load(p)
	if r.Settings != nil || !strings.HasPrefix(r.Error, "settings.jsonc:") {
		t.Fatalf("ждал ошибку settings.jsonc, получил %q", r.Error)
	}
	if r.Fallback["theme"] != "dev-night" {
		t.Fatalf("на сломанном settings.jsonc нужны умолчания, получил %#v", r.Fallback)
	}
	if pr := r.Problems[p.User()]; len(pr) != 1 || pr[0].Severity != SeverityError || pr[0].Lnum != 2 {
		t.Fatalf("ждал одну ошибку на 3-й строке, получил %#v", pr)
	}
}

func TestAutoLayer(t *testing.T) {
	p := fixture(t, `{ "auto": { "languages": { "lua": { "lsp": ["lua_ls"], "format": ["stylua"] }, "php": false } } }`,
		`{ "lsp": { "servers": { "zls": false } } }`)
	if err := os.WriteFile(p.Auto(), []byte(`{"lua": true, "php": true, "zig": {"lsp": ["zls"]}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	s := Load(p).Settings
	servers := s["lsp"].(map[string]any)["servers"].(map[string]any)
	if servers["lua_ls"] != true {
		t.Errorf("lua_ls из набора не включился: %#v", servers)
	}
	if servers["zls"] != false {
		t.Errorf("settings.jsonc должен быть сильнее слоя: zls = %#v", servers["zls"])
	}
	if f := s["format"].(map[string]any)["languages"].(map[string]any)["lua"]; !reflect.DeepEqual(f, []any{"stylua"}) {
		t.Errorf("форматтер lua: %#v", f)
	}
	if _, ok := s["format"].(map[string]any)["languages"].(map[string]any)["php"]; ok {
		t.Errorf("php: false в наборе — ничего не включать")
	}
}

func TestPlugins(t *testing.T) {
	p := fixture(t, `{ "theme": "dev-night", "tasks": { "list": [{ "name": "a" }] }, "keys": { "n x": "y" } }`,
		`{ "keys": { "n z": "w" } }`)
	write := func(name, text string) {
		if err := os.MkdirAll(p.Plugins(), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(p.Plugins(), name), []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("b-go.jsonc", `{ "name": "Go", "tasks": { "list+": [{ "name": "vet" }] }, "keys": { "n v": "vet" }, "checks": { "vet": { "run": "go vet" } } }`)
	write("a-off.jsonc", `{ "enabled": false, "theme": "sunset" }`)
	write("c-broken.jsonc", `{ "theme": `)
	r := Load(p)
	if r.Error != "" {
		t.Fatalf("сломанный набор не должен ломать всё: %s", r.Error)
	}
	s := r.Settings
	if s["theme"] != "dev-night" {
		t.Errorf("выключенный набор применился: тема %v", s["theme"])
	}
	tasks := s["tasks"].(map[string]any)["list"].([]any)
	if len(tasks) != 2 {
		t.Errorf("list+ из набора должен дописать задачу: %v", tasks)
	}
	keys := s["keys"].(map[string]any)
	if keys["n x"] != "y" || keys["n v"] != "vet" || keys["n z"] != "w" {
		t.Errorf("клавиши трёх слоёв: %v", keys)
	}
	if s["checks"] == nil {
		t.Error("раздел checks из набора потерялся")
	}
	broken := r.Problems[filepath.Join(p.Plugins(), "c-broken.jsonc")]
	if len(broken) != 1 || broken[0].Severity != SeverityError {
		t.Errorf("ошибка сломанного набора — на его строке: %+v", broken)
	}
	if len(r.Problems[filepath.Join(p.Plugins(), "b-go.jsonc")]) != 0 {
		t.Errorf("name — служебное поле набора, не ошибка: %+v", r.Problems[filepath.Join(p.Plugins(), "b-go.jsonc")])
	}
	if !strings.Contains(r.Stamp["plugins"], "b-go.jsonc=") {
		t.Errorf("отпечаток наборов: %q", r.Stamp["plugins"])
	}
}

func TestSet(t *testing.T) {
	p := fixture(t, `{}`, `{
  // моя тема
  "theme": "sunset",
  "statusline": { "theme": "nested" },
  "keys": { "n x": "y" },
}`)
	if err := Set(p, "theme", `"dracula"`); err != nil {
		t.Fatal(err)
	}
	if err := Set(p, "keys", `{"n a":"b"}`); err != nil {
		t.Fatal(err)
	}
	if err := Set(p, "plugins", `{}`); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(p.User())
	text := string(data)
	for _, want := range []string{`// моя тема`, `"theme": "dracula"`, `"statusline": { "theme": "nested" }`, `"keys": {"n a":"b"}`, `"plugins": {},`} {
		if !strings.Contains(text, want) {
			t.Errorf("нет %q в:\n%s", want, text)
		}
	}
	r := Load(p)
	if r.Error != "" || r.Settings["theme"] != "dracula" {
		t.Fatalf("после записи файл не читается: %q %#v", r.Error, r.Settings["theme"])
	}
}
