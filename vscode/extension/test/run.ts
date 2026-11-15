import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as assert from "assert";
import * as schema from "../src/sql/schema";
import { downFor } from "../src/sql/migrations";
import { complete } from "../src/sql/complete";
import { check } from "../src/sql/checks";

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mig-")) + "/migrations";
fs.mkdirSync(dir);
fs.writeFileSync(dir + "/000001_create_users.up.sql", `CREATE TYPE role AS ENUM ('admin', 'user');
CREATE TABLE users (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, email text NOT NULL UNIQUE, role role NOT NULL DEFAULT 'user');`);
fs.writeFileSync(dir + "/000002_create_orders.up.sql", `-- заказы
CREATE TABLE orders (
  id bigint PRIMARY KEY,
  user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  total numeric(12,2)
);
CREATE INDEX orders_user_idx ON orders (user_id);`);
const s = schema.load(dir);
assert.deepEqual([...s.tables.keys()], ["users", "orders"]);
assert.equal(s.tables.get("orders")!.cols[1].ref!.table, "users");
assert.deepEqual(s.enums.get("role"), ["admin", "user"]);

assert.deepEqual(downFor(fs.readFileSync(dir + "/000002_create_orders.up.sql", "utf8")), ["DROP INDEX IF EXISTS orders_user_idx;", "DROP TABLE IF EXISTS orders;"]);
assert.deepEqual(downFor("ALTER TABLE users ADD COLUMN phone text, RENAME COLUMN email TO mail;"),
  ["ALTER TABLE users RENAME COLUMN mail TO email;", "ALTER TABLE users DROP COLUMN IF EXISTS phone;"]);
assert.deepEqual(downFor("-- +goose Up\nCREATE TABLE x (id int);\n-- +goose Down\n"), ["DROP TABLE IF EXISTS x;"]);

function doc(text: string, file = dir + "/q.sql") {
  const lines = text.split("\n");
  return {
    uri: { fsPath: file }, getText: () => text, lineCount: lines.length,
    lineAt: (i: number) => ({ text: lines[i], range: { end: { line: i, character: lines[i].length } } }),
    offsetAt: (p: any) => lines.slice(0, p.line).join("\n").length + (p.line ? 1 : 0) + p.character,
    positionAt: (o: number) => { const b = text.slice(0, o).split("\n"); return { line: b.length - 1, character: b[b.length - 1].length }; },
    getWordRangeAtPosition: () => undefined,
  } as any;
}
const at = (text: string) => { const d = doc(text.replace("|", "")); const b = text.slice(0, text.indexOf("|")).split("\n"); return complete(d, { line: b.length - 1, character: b[b.length - 1].length } as any).map((i: any) => i.label.label); };
// migrations dir: file in dir with number? q.sql isn't migration → migrations.dir falls to projectRoot → undefined. use numbered name
const q = (text: string) => { const d = doc(text.replace("|", ""), dir + "/000009_q.sql"); const b = text.slice(0, text.indexOf("|")).split("\n"); return complete(d, { line: b.length - 1, character: b[b.length - 1].length } as any).map((i: any) => i.label.label); };
assert.ok(q("SELECT * FROM |").includes("orders"));
assert.deepEqual(q("SELECT o.| FROM orders o").slice(0, 3), ["id", "user_id", "total"]);
assert.ok(q("SELECT * FROM users u JOIN orders o |").includes("ON o.user_id = u.id"), String(q("SELECT * FROM users u JOIN orders o |")));
assert.deepEqual(q("SELECT * FROM users WHERE role = '|"), ["admin", "user"]);
assert.ok(q("CREATE TABLE t (x |").includes("role"));
assert.ok(q("SELECT * FROM users u |").includes("WHERE"));

const bad = doc("ALTER TABLE users ADD COLUMN phone text NOT NULL;\nCREATE INDEX users_email ON users (email);", dir + "/000003_x.up.sql");
const msgs = check(bad).map((d: any) => d.message);
assert.equal(msgs.length, 2, msgs.join("\n"));
assert.equal(check(doc("CREATE TABLE z (id int);\nCREATE INDEX z_i ON z (id);", dir + "/000003_x.up.sql")).length, 0);
console.log("ok");

import { generate, goName, parse } from "../src/go/json2struct";
assert.equal(goName("user_id"), "UserID");
assert.equal(goName("createdAt"), "CreatedAt");
assert.equal(goName("avatar_url"), "AvatarURL");
const sample = parse(`{"id": 7, "user_id": "u1", "price": 9.5, "paid": true, "created_at": "2026-10-29T01:02:03Z",
  "items": [{"sku": "A", "qty": 2}, {"sku": "B", "qty": 1, "note": "gift"}], "coupon": null, "tags": ["x"], "meta": {"source": "web"},}`);
const code = generate(sample, { name: "Order" });
const has = (re: RegExp) => assert.ok(re.test(code), String(re));
has(/ID\s+int64\s+`json:"id"`/);
has(/UserID\s+string\s+`json:"user_id"`/);
has(/Price\s+float64\s+`json:"price"`/);
has(/CreatedAt\s+time\.Time\s+`json:"created_at"`/);
has(/Items\s+\[\]OrderItem\s+`json:"items"`/);
has(/Note\s+string\s+`json:"note,omitempty"`/);
has(/Coupon\s+any\s+`json:"coupon,omitempty"`/);
has(/type OrderMeta struct/);
assert.ok(code.indexOf("type Order struct") < code.indexOf("type OrderItem struct"));
console.log("json2struct ok");

// ▶ у main и тестов: Python, JS/TS
import { kindOf, current } from "../src/run";
assert.deepEqual(kindOf("python", 'if __name__ == "__main__":', "/p/app.py"), ["main", "main"]);
assert.deepEqual(kindOf("python", "    def test_sum(self):", "/p/test_calc.py"), ["test", "test_sum"]);
assert.equal(kindOf("python", "def test_sum():", "/p/calc.py"), undefined);
assert.deepEqual(kindOf("typescript", '  it("складывает", () => {', "/p/sum.test.ts"), ["test", "складывает"]);
assert.deepEqual(kindOf("javascript", "#!/usr/bin/env node", "/p/cli.js"), ["main", "main"]);
const lines = ["import x", "", "def test_a():", "    x = 1", "    assert x"];
const pyDoc = { languageId: "python", uri: { fsPath: "/p/test_a.py" }, lineAt: (i: number) => ({ text: lines[i] }) };
assert.deepEqual(current(pyDoc, 4), ["test", "test_a", 2]);
assert.equal(current(pyDoc, 0), undefined);

// тест ↔ код
import { codeFor, testsFor } from "../src/alternate";
assert.deepEqual(testsFor("/p/pkg", "calc", "go"), ["/p/pkg/calc_test.go"]);
assert.equal(testsFor("/p/src", "api", "ts")[0], "/p/src/api.test.ts");
assert.equal(testsFor("/p/app", "calc", "py")[0], "/p/app/test_calc.py");
assert.equal(testsFor("/p/crate/src", "lib", "rs")[0], "/p/crate/tests/lib.rs");
assert.deepEqual(codeFor("/p/pkg", "calc_test", "go"), ["/p/pkg/calc.go"]);
assert.deepEqual(codeFor("/p/tests", "test_calc", "py"), ["/p/calc.py", "/p/src/calc.py", "/p/p/calc.py"]);
assert.equal(codeFor("/p/src", "api.spec", "ts")![0], "/p/src/api.ts");
assert.equal(codeFor("/p/src", "api", "ts"), undefined);

// задачи из settings.jsonc
import { expand } from "../src/tasks";
assert.equal(expand("go test ${file_dir}", { file_dir: "/a b" }), "go test '/a b'");
assert.equal(expand("echo ${input:Имя} ${input:Имя} ${nope}", {}), `printf '%s: ' 'Имя'; read -r OWN_IN_0; echo "$OWN_IN_0" "$OWN_IN_0" \${nope}`);

// тесты Go в фоне
import { parse as goParse } from "../src/go/autotest";
const ev = (o: any) => JSON.stringify(o);
const gr = goParse([
  ev({ Action: "run", Test: "TestA" }), ev({ Action: "pass", Test: "TestA" }),
  ev({ Action: "output", Test: "TestB/sub", Output: "    calc_test.go:12: got 1, want 2\n" }),
  ev({ Action: "fail", Test: "TestB/sub" }), ev({ Action: "fail", Test: "TestB" }),
].join("\n"), 1);
assert.equal(gr.passed, 1); assert.equal(gr.failed, 1); assert.equal(gr.build, false);
assert.deepEqual(gr.fails, [{ test: "TestB/sub", file: "calc_test.go", line: 12, msg: "got 1, want 2" }]);
assert.equal(gr.tests[0].name, "TestB");
assert.equal(goParse("# x\nundefined: foo", 1).build, true);

// ревью Claude, эндпоинты, отдых
import { parse as reviewParse } from "../src/review";
assert.deepEqual(reviewParse("internal/a.go:10: error: утечка\nчто-то ещё\n`b.go:3: warn: x`", "/r").map((x) => [x.file, x.line, x.level]), [["/r/internal/a.go", 10, "error"], ["/r/b.go", 3, "warn"]]);
import { examplePath } from "../src/endpoints";
assert.equal(examplePath("/users/:id/files/*path"), "/users/1/files");
import { minutes } from "../src/status";
assert.deepEqual([1, 2, 5, 11, 21, 22].map(minutes), ["1 минута", "2 минуты", "5 минут", "11 минут", "21 минута", "22 минуты"]);
console.log("ok: run, alternate, tasks, autotest, review, endpoints, rest");
