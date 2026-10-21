package jsonc

import (
	"reflect"
	"strings"
	"testing"
)

func TestDecode(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want map[string]any
	}{
		{"пустой файл", "  \n", map[string]any{}},
		{"комментарии и запятые", `{
  // строка
  "a": 1, /* блок */
  "b": ["x", "y",],
}`, map[string]any{"a": 1.0, "b": []any{"x", "y"}}},
		{"// и /* внутри строки — не комментарий", `{ "url": "http://x/*y*/", "c": "a,}" }`,
			map[string]any{"url": "http://x/*y*/", "c": "a,}"}},
		{"экранированная кавычка", `{ "q": "say \"hi\" // no" }`, map[string]any{"q": `say "hi" // no`}},
		{"null — как отсутствующий ключ", `{ "a": null, "b": { "c": null, "d": 1 } }`,
			map[string]any{"b": map[string]any{"d": 1.0}}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := Decode(c.in)
			if err != nil {
				t.Fatalf("ошибка: %v", err)
			}
			if !reflect.DeepEqual(got, c.want) {
				t.Fatalf("получил %#v, ждал %#v", got, c.want)
			}
		})
	}
}

func TestDecodeErrorPosition(t *testing.T) {
	// ошибка на 3-й строке: после комментария позиция не должна съехать
	_, err := Decode("{\n  // комментарий\n  \"a\": 1 \"b\": 2\n}")
	if err == nil {
		t.Fatal("ждал ошибку")
	}
	if err.Lnum != 3 {
		t.Fatalf("строка %d, ждал 3 (%s)", err.Lnum, err.Message)
	}
}

func TestDecodeHumanMessage(t *testing.T) {
	_, err := Decode("{\n  \"a\": 1\n  \"b\": 2\n}")
	if err == nil || !strings.Contains(err.Message, "пропущена запятая") {
		t.Fatalf("ждал понятное сообщение про запятую, получил %v", err)
	}
	_, err = Decode("{ \"a\": [1, 2 ")
	if err == nil || !strings.Contains(err.Message, "не хватает } или ]") {
		t.Fatalf("ждал сообщение про незакрытую скобку, получил %v", err)
	}
}

func TestDecodeNotObject(t *testing.T) {
	if _, err := Decode("[1, 2]"); err == nil || err.Message != "ждал объект { … } на верхнем уровне" {
		t.Fatalf("ждал ошибку про объект, получил %v", err)
	}
}

func TestFindKey(t *testing.T) {
	text := "{\n  // \"theme\": \"old\"\n  \"theme\": \"new\",\n}"
	lnum, col, ok := FindKey(text, "theme")
	if !ok || lnum != 3 || col != 2 {
		t.Fatalf("получил %d:%d %v, ждал 3:2 — ключ в комментарии не считается", lnum, col, ok)
	}
}
