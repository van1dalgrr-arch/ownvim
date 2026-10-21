// Package jsonc — JSON с комментариями (// и /* */) и запятыми в конце, как settings.json в VS Code и Zed.
//
// Комментарии и лишние запятые заменяются пробелами той же длины: позиции не съезжают, и ошибка разбора
// указывает на ту же строку и столбец, что в исходном файле.
package jsonc

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
)

// Error — ошибка разбора с местом в файле: строка с 1, столбец с 0 (в байтах).
type Error struct {
	Lnum    int
	Col     int
	Message string
}

func (e *Error) Error() string { return fmt.Sprintf("%d:%d: %s", e.Lnum, e.Col, e.Message) }

// blank заменяет всё, кроме переводов строк, пробелами — длина и строки те же.
func blank(b []byte) []byte {
	out := make([]byte, len(b))
	for i, c := range b {
		if c == '\n' {
			out[i] = '\n'
		} else {
			out[i] = ' '
		}
	}
	return out
}

// stringEnd — индекс закрывающей кавычки строки, открытой в i (с учётом \"); перевод строки тоже закрывает.
func stringEnd(s []byte, i int) int {
	for j := i + 1; j < len(s); j++ {
		switch s[j] {
		case '\\':
			j++
		case '"', '\n':
			return j
		}
	}
	return len(s) - 1
}

// Strip убирает комментарии, не трогая строки; позиции остаются прежними.
func Strip(text string) string {
	s := []byte(text)
	var out bytes.Buffer
	out.Grow(len(s))
	for i := 0; i < len(s); {
		c := s[i]
		switch {
		case c == '"':
			e := stringEnd(s, i)
			out.Write(s[i : e+1])
			i = e + 1
		case c == '/' && i+1 < len(s) && s[i+1] == '/':
			e := bytes.IndexByte(s[i:], '\n')
			if e < 0 {
				e = len(s) - i
			}
			out.Write(blank(s[i : i+e]))
			i += e
		case c == '/' && i+1 < len(s) && s[i+1] == '*':
			e := bytes.Index(s[i+2:], []byte("*/"))
			end := len(s)
			if e >= 0 {
				end = i + 2 + e + 2
			}
			out.Write(blank(s[i:end]))
			i = end
		default:
			out.WriteByte(c)
			i++
		}
	}
	return out.String()
}

var closing = regexp.MustCompile(`^\s*[\]}]`)

// stripTrailingCommas убирает запятую перед } или ] (комментариев уже нет).
func stripTrailingCommas(text string) string {
	s := []byte(text)
	out := make([]byte, 0, len(s))
	for i := 0; i < len(s); {
		c := s[i]
		switch {
		case c == '"':
			e := stringEnd(s, i)
			out = append(out, s[i:e+1]...)
			i = e + 1
		case c == ',' && closing.Match(s[i+1:]):
			out = append(out, ' ')
			i++
		default:
			out = append(out, c)
			i++
		}
	}
	return string(out)
}

// position — строка (с 1) и столбец (с 0) для смещения off (с 0) в тексте.
func position(text string, off int) (int, int) {
	if off > len(text) {
		off = len(text)
	}
	if off < 0 {
		off = 0
	}
	before := text[:off]
	lnum := strings.Count(before, "\n") + 1
	return lnum, len(before) - (strings.LastIndexByte(before, '\n') + 1)
}

// dropNulls убирает null: как luanil в Lua — ключ с null равен отсутствующему.
func dropNulls(v any) any {
	switch t := v.(type) {
	case map[string]any:
		for k, x := range t {
			if x == nil {
				delete(t, k)
			} else {
				t[k] = dropNulls(x)
			}
		}
	case []any:
		out := t[:0]
		for _, x := range t {
			if x != nil {
				out = append(out, dropNulls(x))
			}
		}
		return out
	}
	return v
}

// понятные слова для частых ошибок encoding/json; исходный текст — в скобках
var hints = []struct{ part, say string }{
	{"after object key:value pair", "пропущена запятая перед этим местом"},
	{"after array element", "пропущена запятая между элементами списка"},
	{"after object key", "после ключа нужно двоеточие"},
	{"looking for beginning of object key string", "ждал ключ в кавычках"},
	{"looking for beginning of value", "ждал значение: строку, число, true/false, объект или список"},
	{"in string literal", "недопустимый символ внутри строки (перевод строки или управляющий символ)"},
	{"in string escape code", "неверная \\-последовательность в строке"},
	{"unexpected end of JSON input", "файл кончился раньше времени — не хватает } или ]"},
}

func human(msg string) string {
	for _, h := range hints {
		if strings.Contains(msg, h.part) {
			return h.say + " (" + msg + ")"
		}
	}
	return msg
}

// Decode разбирает JSONC. Верхний уровень — объект; пустой файл — пустой объект.
func Decode(text string) (map[string]any, *Error) {
	clean := stripTrailingCommas(Strip(text))
	if strings.TrimSpace(clean) == "" {
		return map[string]any{}, nil
	}
	var v any
	if err := json.Unmarshal([]byte(clean), &v); err != nil {
		off := 0
		if syn, ok := errors.AsType[*json.SyntaxError](err); ok {
			off = int(syn.Offset) - 1
		}
		lnum, col := position(clean, off)
		return nil, &Error{Lnum: lnum, Col: col, Message: "JSON: " + human(err.Error())}
	}
	obj, ok := dropNulls(v).(map[string]any)
	if !ok {
		return nil, &Error{Lnum: 1, Col: 0, Message: "ждал объект { … } на верхнем уровне"}
	}
	return obj, nil
}

// FindKey — где в тексте ключ "name": строка с 1 и столбец с 0. Комментарии не в счёт.
func FindKey(text, name string) (int, int, bool) {
	re := regexp.MustCompile(`"` + regexp.QuoteMeta(name) + `"\s*:`)
	for i, line := range strings.Split(Strip(text), "\n") {
		if loc := re.FindStringIndex(line); loc != nil {
			return i + 1, loc[0], true
		}
	}
	return 0, 0, false
}
