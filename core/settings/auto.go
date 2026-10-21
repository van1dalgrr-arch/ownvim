package settings

import (
	"encoding/json"
	"os"
)

// autoLayer — языки, для которых ownvim сам включил инструменты (own-auto.json пишет lua/own/auto.lua).
// Значение языка: true — взять из набора auto.languages; объект { lsp, format, lint } — найдено в mason;
// false — ничего не нужно. nil — автоустановка выключена.
func autoLayer(p Paths, s map[string]any) map[string]any {
	auto := asMap(s["auto"])
	if enabled, ok := auto["enabled"].(bool); ok && !enabled {
		return nil
	}
	langs := asMap(auto["languages"])
	servers, formats, lints := map[string]any{}, map[string]any{}, map[string]any{}
	layer := map[string]any{
		"lsp":    map[string]any{"servers": servers},
		"format": map[string]any{"languages": formats},
		"lint":   map[string]any{"languages": lints},
	}
	seen := map[string]any{}
	if data, err := os.ReadFile(p.Auto()); err == nil {
		_ = json.Unmarshal(data, &seen)
	}
	for ft, v := range seen {
		rec := recOf(langs, ft, v)
		if rec == nil {
			continue
		}
		if list, ok := rec["lsp"].([]any); ok {
			for _, name := range list {
				if n, ok := name.(string); ok {
					servers[n] = true
				}
			}
		}
		if f, ok := rec["format"]; ok {
			formats[ft] = f
		}
		if l, ok := rec["lint"]; ok {
			lints[ft] = l
		}
	}
	return layer
}

func recOf(langs map[string]any, ft string, v any) map[string]any {
	if off, ok := langs[ft].(bool); ok && !off {
		return nil
	}
	switch t := v.(type) {
	case bool:
		if t {
			if m, ok := langs[ft].(map[string]any); ok {
				return m
			}
		}
	case map[string]any:
		return t
	}
	return nil
}
