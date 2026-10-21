package checks

import (
	"regexp"
	"testing"
)

func TestParse(t *testing.T) {
	out := "# calc\n./calc.go:4:2: fmt.Printf format %d has arg s of wrong type string\nmain.sh:3:5: warning: Quote this to prevent word splitting [SC2086]\nlib.go:10: error: something\nnot a finding\n"
	got := Parse(out, Default, "warn")
	if len(got) != 3 {
		t.Fatalf("находок %d: %+v", len(got), got)
	}
	if got[0] != (Finding{File: "./calc.go", Line: 4, Col: 2, Severity: "warn", Message: "fmt.Printf format %d has arg s of wrong type string"}) {
		t.Errorf("go vet: %+v", got[0])
	}
	if got[1].Severity != "warn" || got[1].Message != "Quote this to prevent word splitting [SC2086]" {
		t.Errorf("shellcheck: %+v", got[1])
	}
	if got[2].Severity != "error" || got[2].Col != 0 {
		t.Errorf("без столбца, с уровнем: %+v", got[2])
	}
	custom := regexp.MustCompile(`^(?P<file>[^:]+):(?P<line>\d+):(?P<message>.*)$`)
	if f := Parse("a.go:7:// TODO(bob): fix", custom, "info"); len(f) != 1 || f[0].Severity != "info" || f[0].Line != 7 {
		t.Errorf("свой формат: %+v", f)
	}
}
