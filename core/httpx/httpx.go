// Package httpx — HTTP-запросы для эндпоинтов и .http-файлов: отправить, показать ответ, запомнить токен, curl.
package httpx

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// Header — заголовок запроса.
type Header struct{ Name, Value string }

// Response — ответ: код, время, тело (и разобранный JSON, если это JSON).
type Response struct {
	Status   int
	Duration time.Duration
	Body     []byte
	JSON     any // nil — не JSON
}

var client = &http.Client{Timeout: 30 * time.Second}

// Do отправляет запрос. Ошибка — только если ответа нет совсем (сервер не запущен, таймаут).
func Do(method, url string, headers []Header, body string) (Response, error) {
	var rd io.Reader
	if body != "" {
		rd = strings.NewReader(body)
	}
	req, err := http.NewRequest(method, url, rd)
	if err != nil {
		return Response{}, err
	}
	for _, h := range headers {
		req.Header.Add(h.Name, h.Value)
	}
	start := time.Now()
	resp, err := client.Do(req)
	if err != nil {
		return Response{}, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	r := Response{Status: resp.StatusCode, Duration: time.Since(start), Body: data}
	var v any
	if json.Unmarshal(data, &v) == nil {
		r.JSON = v
	}
	return r, err
}

// Pretty — тело для показа: JSON с отступами, остальное как есть.
func (r Response) Pretty() string {
	if r.JSON != nil {
		var b bytes.Buffer
		if json.Indent(&b, r.Body, "", "  ") == nil {
			return b.String()
		}
	}
	return string(r.Body)
}

// Head — первая строка ответа: // GET /x → 200 · 12 мс
func Head(method, url string, r Response) string {
	ms := r.Duration.Milliseconds()
	took := fmt.Sprintf("%d мс", ms)
	if ms < 1 {
		took = "<1 мс"
	}
	return fmt.Sprintf("// %s %s → %d · %s", method, url, r.Status, took)
}

// Token — access_token / accessToken / token из ответа (и из data.*): запомнить для следующих запросов.
func Token(v any) string {
	m, ok := v.(map[string]any)
	if !ok {
		return ""
	}
	for _, k := range []string{"access_token", "accessToken", "token"} {
		if s, ok := m[k].(string); ok && s != "" {
			return s
		}
	}
	return Token(m["data"])
}

// Curl — та же команда для терминала (аргументы в одинарных кавычках).
func Curl(method, url string, headers []Header, body string) string {
	parts := []string{"curl", "-s", "-X", method}
	for _, h := range headers {
		parts = append(parts, "-H", quote(h.Name+": "+h.Value))
	}
	if body != "" {
		parts = append(parts, "--data-binary", quote(body))
	}
	parts = append(parts, quote(url))
	return strings.Join(parts, " ")
}

func quote(s string) string { return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'" }

var portLine = regexp.MustCompile(`^\s*PORT\s*=\s*(\d+)`)

// Port — порт API проекта: PORT из .env в корне, иначе из окружения, иначе 8080.
func Port(root string) string {
	if data, err := os.ReadFile(filepath.Join(root, ".env")); err == nil {
		for line := range strings.SplitSeq(string(data), "\n") {
			if m := portLine.FindStringSubmatch(line); m != nil {
				return m[1]
			}
		}
	}
	if p := os.Getenv("PORT"); p != "" {
		return p
	}
	return "8080"
}
