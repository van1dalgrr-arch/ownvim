package httpfile

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"

	"github.com/van1dalgrr-arch/ownvim/core/httpx"
)

// Request — запрос из .http-файла.
type Request struct {
	Name    string // # @name login
	Method  string
	URL     string
	Line    int // строка с методом (с 1)
	First   int // первая строка блока (с 1)
	Headers []httpx.Header
	Body    string
}

var (
	varLine    = regexp.MustCompile(`^@([\w\-]+)\s*=\s*(.*?)\s*$`)
	nameLine   = regexp.MustCompile(`^#\s*@name\s+([\w\-]+)`)
	methodLine = regexp.MustCompile(`^([A-Z]+)\s+(\S+)`)
	headerLine = regexp.MustCompile(`^([\w\-]+):\s*(.*)$`)
)

// Parse — запросы и переменные файла, как в VS Code REST Client / JetBrains HTTP Client:
//
//	@host = http://localhost:8080      переменная → {{host}}
//	### Заголовок                      разделитель запросов
//	# @name login                      ответ — {{login.response.body.$.access_token}}
//	POST {{host}}/auth/login           метод и адрес
//	Content-Type: application/json     заголовки до пустой строки, дальше — тело
func Parse(lines []string) ([]Request, map[string]string) {
	vars := map[string]string{}
	var reqs []Request
	var cur *Request
	var body []string
	stage := "" // "" — до запроса, "headers", "body"
	closeReq := func() {
		if cur != nil {
			for len(body) > 0 && strings.TrimSpace(body[len(body)-1]) == "" {
				body = body[:len(body)-1]
			}
			cur.Body = strings.Join(body, "\n")
			reqs = append(reqs, *cur)
		}
		cur, body, stage = nil, nil, ""
	}
	for i, line := range lines {
		n := i + 1
		switch {
		case strings.HasPrefix(line, "###"):
			closeReq()
		case stage == "":
			if m := varLine.FindStringSubmatch(line); m != nil {
				vars[m[1]] = m[2]
			} else if m := nameLine.FindStringSubmatch(line); m != nil {
				if cur == nil {
					cur = &Request{First: n}
				}
				cur.Name = m[1]
			} else if m := methodLine.FindStringSubmatch(line); m != nil {
				if cur == nil {
					cur = &Request{First: n}
				}
				cur.Method, cur.URL, cur.Line, stage = m[1], m[2], n, "headers"
			}
		case stage == "headers":
			if strings.TrimSpace(line) == "" {
				stage = "body"
			} else if !strings.HasPrefix(strings.TrimSpace(line), "#") {
				if m := headerLine.FindStringSubmatch(line); m != nil {
					cur.Headers = append(cur.Headers, httpx.Header{Name: m[1], Value: m[2]})
				}
			}
		default:
			body = append(body, line)
		}
	}
	closeReq()
	return reqs, vars
}

var placeholder = regexp.MustCompile(`\{\{\s*(.*?)\s*\}\}`)
var responseRef = regexp.MustCompile(`^([\w\-]+)\.response\.body\.\$\.?(.*)$`)

// Expand подставляет {{host}}, {{$env.HOME}}, {{login.response.body.$.data.token}} (ответы — responses).
// Неизвестное остаётся как есть.
func Expand(s string, vars map[string]string, responses map[string]any) string {
	for range 5 { // переменные могут ссылаться друг на друга
		before := s
		s = placeholder.ReplaceAllStringFunc(s, func(m string) string {
			key := placeholder.FindStringSubmatch(m)[1]
			if v, ok := vars[key]; ok {
				return v
			}
			if env, ok := strings.CutPrefix(key, "$env."); ok {
				return os.Getenv(env)
			}
			if r := responseRef.FindStringSubmatch(key); r != nil {
				if v, ok := lookup(responses[r[1]], r[2]); ok {
					return v
				}
				// многие API заворачивают ответ в data: {{login…$.access_token}} найдётся и в data.access_token
				if v, ok := lookup(responses[r[1]], strings.TrimPrefix("data."+r[2], ".")); ok && !strings.HasPrefix(r[2], "data") {
					return v
				}
			}
			return m
		})
		if s == before {
			break
		}
	}
	return s
}

// Unresolved — что осталось неподставленным ({{…}}): показать, а не отправить молча.
func Unresolved(parts ...string) []string {
	var out []string
	seen := map[string]bool{}
	for _, p := range parts {
		for _, m := range placeholder.FindAllString(p, -1) {
			if !seen[m] {
				seen[m] = true
				out = append(out, m)
			}
		}
	}
	return out
}

// lookup — значение по пути a.b.0.c в разобранном JSON
func lookup(v any, path string) (string, bool) {
	if v == nil {
		return "", false
	}
	if path != "" {
		for part := range strings.SplitSeq(path, ".") {
			switch t := v.(type) {
			case map[string]any:
				v = t[part]
			case []any:
				i, err := strconv.Atoi(part)
				if err != nil || i < 0 || i >= len(t) {
					return "", false
				}
				v = t[i]
			default:
				return "", false
			}
		}
	}
	switch t := v.(type) {
	case nil:
		return "", false
	case string:
		return t, true
	case float64:
		return strconv.FormatFloat(t, 'f', -1, 64), true
	default:
		return fmt.Sprint(t), true
	}
}

// At — запрос под курсором (или ближайший выше): строка line (с 1). Строка «### …» над запросом тоже считается.
func At(reqs []Request, line int) (Request, bool) {
	for i := len(reqs) - 1; i >= 0; i-- {
		if reqs[i].Method != "" && reqs[i].First <= line+1 {
			return reqs[i], true
		}
	}
	return Request{}, false
}
