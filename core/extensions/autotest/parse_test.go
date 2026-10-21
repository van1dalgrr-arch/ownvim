package autotest

import (
	"os"
	"path/filepath"
	"testing"
)

const goTestJSON = `{"Action":"run","Test":"TestAdd"}
{"Action":"output","Test":"TestAdd","Output":"=== RUN   TestAdd\n"}
{"Action":"pass","Test":"TestAdd"}
{"Action":"run","Test":"TestDiv"}
{"Action":"run","Test":"TestDiv/zero"}
{"Action":"output","Test":"TestDiv/zero","Output":"    calc_test.go:23: got 1, want 2\n"}
{"Action":"fail","Test":"TestDiv/zero"}
{"Action":"fail","Test":"TestDiv"}
{"Action":"skip","Test":"TestSlow"}
{"Action":"fail"}`

func TestParse(t *testing.T) {
	r := Parse(goTestJSON, 1)
	if r.Passed != 1 || r.Failed != 1 || r.Build {
		t.Fatalf("итог: %+v", r)
	}
	if r.Tests[0].Name != "TestDiv" || r.Tests[0].Pass {
		t.Fatalf("упавшие — первыми: %+v", r.Tests)
	}
	if len(r.Fails) != 1 || r.Fails[0] != (Fail{Test: "TestDiv/zero", File: "calc_test.go", Line: 23, Msg: "got 1, want 2"}) {
		t.Fatalf("проверки: %+v", r.Fails)
	}
	if b := Parse("# pkg\n./calc.go:3:1: syntax error", 1); !b.Build {
		t.Fatal("ни одного теста и код 1 — не собрался")
	}
}

func TestWhere(t *testing.T) {
	dir := t.TempDir()
	src := "package calc\n\nimport \"testing\"\n\nfunc TestAdd(t *testing.T) {}\n"
	if err := os.WriteFile(filepath.Join(dir, "calc_test.go"), []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	w := Where(dir)["TestAdd"]
	if w[1] != 5 {
		t.Fatalf("TestAdd на строке 5, получил %v", w)
	}
}
