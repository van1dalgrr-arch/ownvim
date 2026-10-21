package settings

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/van1dalgrr-arch/ownvim/core/jsonc"
)

// Set записывает ключ верхнего уровня в settings.jsonc, не трогая комментарии и остальной текст
// (как VS Code пишет settings.json). value — готовый JSON.
func Set(p Paths, key, value string) error {
	if !json.Valid([]byte(value)) {
		return fmt.Errorf("значение для %q — не JSON: %s", key, value)
	}
	data, err := os.ReadFile(p.User())
	text := string(data)
	if err != nil {
		text = "{\n}\n"
	}
	clean := jsonc.Strip(text) // без комментариев, позиции те же
	if start, ok := topValue(clean, key); ok {
		text = text[:start] + value + text[valueEnd(clean, start)+1:]
	} else {
		brace := strings.IndexByte(clean, '{')
		if brace < 0 {
			text, brace = "{\n}\n", 0
		}
		quoted, _ := json.Marshal(key)
		text = text[:brace+1] + fmt.Sprintf("\n  %s: %s,", quoted, value) + text[brace+1:]
	}
	return os.WriteFile(p.User(), []byte(text), 0o644)
}

// topValue — где начинается значение ключа key верхнего уровня (только на первом уровне вложенности:
// одноимённый ключ внутри другого раздела не трогаем).
func topValue(s, key string) (int, bool) {
	depth := 0
	for i := 0; i < len(s); i++ {
		switch c := s[i]; c {
		case '{', '[':
			depth++
		case '}', ']':
			depth--
		case '"':
			end := strEnd(s, i)
			if depth == 1 && s[i+1:end] == key {
				j := end + 1
				for j < len(s) && strings.ContainsRune(" \t\r\n", rune(s[j])) {
					j++
				}
				if j < len(s) && s[j] == ':' {
					j++
					for j < len(s) && strings.ContainsRune(" \t\r\n", rune(s[j])) {
						j++
					}
					return j, true
				}
			}
			i = end
		}
	}
	return 0, false
}

func strEnd(s string, i int) int {
	for j := i + 1; j < len(s); j++ {
		switch s[j] {
		case '\\':
			j++
		case '"':
			return j
		}
	}
	return len(s) - 1
}

// valueEnd — последний байт значения, которое начинается в i: объект и массив — до парной скобки,
// строка — до кавычки, остальное — до запятой, перевода строки или }.
func valueEnd(s string, i int) int {
	switch s[i] {
	case '"':
		return strEnd(s, i)
	case '{', '[':
		depth := 0
		for j := i; j < len(s); j++ {
			switch s[j] {
			case '"':
				j = strEnd(s, j)
			case '{', '[':
				depth++
			case '}', ']':
				depth--
				if depth == 0 {
					return j
				}
			}
		}
		return len(s) - 1
	}
	if j := strings.IndexAny(s[i:], ",\n}"); j >= 0 {
		return i + j - 1
	}
	return len(s) - 1
}
