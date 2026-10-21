package settings

import (
	"maps"
	"strings"
)

// isDict — объект; пустой список тоже: в Lua {} и [] — одна и та же пустая таблица,
// и "keys": {} иначе стёр бы все клавиши по умолчанию.
func isDict(v any) bool {
	switch t := v.(type) {
	case map[string]any:
		return true
	case []any:
		return len(t) == 0
	}
	return false
}

func asMap(v any) map[string]any {
	if m, ok := v.(map[string]any); ok {
		return m
	}
	return map[string]any{}
}

// merge — слияние слоёв: объекты — по ключам, остальное заменяется целиком.
// true поверх объекта оставляет объект: "modes": true значит «включён, с настройками по умолчанию».
// "ключ+": [ … ] — дописать к списку ключа, а не заменить его ("tasks": { "list+": [ своя задача ] }).
func merge(base, over any) any {
	if over == nil {
		return base
	}
	if b, ok := over.(bool); ok && b && isDict(base) {
		return base
	}
	if !isDict(base) || !isDict(over) {
		return over
	}
	bm, om := asMap(base), asMap(over)
	out := make(map[string]any, len(bm)+len(om))
	maps.Copy(out, bm)
	for k, v := range om {
		if !strings.HasSuffix(k, "+") {
			out[k] = merge(bm[k], v)
		}
	}
	for k, v := range om { // после обычных ключей: "list" и "list+" в одном слое — сначала замена, потом дописать
		name, ok := strings.CutSuffix(k, "+")
		add, isList := v.([]any)
		if !ok || !isList {
			continue
		}
		prev, _ := out[name].([]any)
		out[name] = append(append([]any{}, prev...), add...)
	}
	return out
}
