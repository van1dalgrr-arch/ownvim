package autotest

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseCargo(t *testing.T) {
	dir := t.TempDir()
	_ = os.MkdirAll(filepath.Join(dir, "src"), 0o755)
	_ = os.WriteFile(filepath.Join(dir, "src", "lib.rs"), []byte("#[cfg(test)]\nmod tests {\n    #[test]\n    fn adds() {}\n}\n"), 0o644)
	out := `running 3 tests
test tests::adds ... ok
test tests::fails ... FAILED
test tests::slow ... ignored

failures:

---- tests::fails stdout ----

thread 'tests::fails' panicked at src/lib.rs:4:9:
assertion ` + "`left == right`" + ` failed
  left: 1
 right: 2
note: run with ` + "`RUST_BACKTRACE=1`" + `

test result: FAILED. 1 passed; 1 failed; 1 ignored
`
	r := ParseCargo(out, 101, dir)
	if r.Passed != 1 || r.Failed != 1 || r.Build {
		t.Fatalf("passed %d failed %d build %v", r.Passed, r.Failed, r.Build)
	}
	if len(r.Fails) != 1 || r.Fails[0].Line != 4 || r.Fails[0].File != filepath.Join(dir, "src", "lib.rs") {
		t.Fatalf("fails %+v", r.Fails)
	}
	if r.Fails[0].Msg != "assertion `left == right` failed left: 1 right: 2" {
		t.Fatalf("msg %q", r.Fails[0].Msg)
	}
	if r.Tests[0].Name != "tests::fails" {
		t.Fatalf("упавший — первым: %+v", r.Tests)
	}
	if w := WhereRust(dir)["adds"]; w[1] != 4 {
		t.Fatalf("where %v", w)
	}
	// Rust 1.92+: id потока после имени
	if r2 := ParseCargo("test tests::fails ... FAILED\nthread 'tests::fails' (4264153) panicked at src/lib.rs:4:9:\nboom\n", 101, dir); len(r2.Fails) != 1 {
		t.Fatalf("с id потока: %+v", r2.Fails)
	}
	if b := ParseCargo("error[E0308]: mismatched types\nerror: could not compile", 101, dir); !b.Build {
		t.Fatal("сборка")
	}
}
