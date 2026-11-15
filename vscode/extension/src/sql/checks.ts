// Проверки миграций — то, что ломает прод, а не синтаксис (синтаксис и типы — у Postgres Language Server):
//   NOT NULL без DEFAULT на существующей таблице, индекс без CONCURRENTLY, внешний ключ без NOT VALID,
//   смена типа колонки, SET NOT NULL, DROP / RENAME колонки и таблицы, ALTER неизвестной таблицы.
import * as path from "path";
import * as vscode from "vscode";
import * as schema from "./schema";
import * as migrations from "./migrations";

const W = vscode.DiagnosticSeverity.Warning, I = vscode.DiagnosticSeverity.Information, E = vscode.DiagnosticSeverity.Error;

/** Схема до этого файла: только миграции с именем раньше него */
function before(dir: string, file: string): schema.Schema {
  const base = path.basename(file);
  const s: schema.Schema = { tables: new Map(), enums: new Map() };
  const full = schema.load(dir);
  // таблица существует «до», если её файл раньше текущего
  for (const [n, t] of full.tables) if (t.file && t.file < base) s.tables.set(n, t);
  return s;
}

export function check(doc: vscode.TextDocument): vscode.Diagnostic[] {
  const file = doc.uri.fsPath;
  if (!migrations.isMigration(file) || file.endsWith(".down.sql")) return [];
  if (vscode.workspace.getConfiguration("ownvim.sql").get<boolean>("checks") === false) return [];
  const dir = path.dirname(file);
  const prior = before(dir, file);
  const created = new Set<string>();
  const text = doc.getText();
  const out: vscode.Diagnostic[] = [];
  const at = (st: schema.Statement, needle: string | undefined, msg: string, sev = W) => {
    let off = st.start;
    if (needle) {
      const i = text.slice(st.start, st.start + st.source.length + 200).toLowerCase().indexOf(needle.toLowerCase().split(/\s+/)[0]);
      if (i >= 0) off += i;
    }
    const p = doc.positionAt(off);
    const d = new vscode.Diagnostic(new vscode.Range(p, doc.lineAt(p.line).range.end), msg, sev);
    d.source = "ownvim";
    out.push(d);
  };
  const goose = text.includes("+goose");
  for (const st of schema.statements(schema.upPart(text))) {
    if (st.kind === "create_table") created.add(st.table);
    if (st.kind === "create_index" && !st.concurrently && st.table && prior.tables.has(st.table) && !created.has(st.table))
      at(st, undefined, `Индекс без CONCURRENTLY блокирует запись в ${st.table} на всё время построения. ` +
        (goose ? "CREATE INDEX CONCURRENTLY + «-- +goose NO TRANSACTION» в начале файла" : "CREATE INDEX CONCURRENTLY — отдельной миграцией (вне транзакции)"));
    if (st.kind === "drop_table") for (const n of st.names) at(st, undefined, `DROP TABLE ${n}: данные пропадут, а старый код может ещё читать таблицу`, I);
    if (st.kind !== "alter_table") continue;
    const existing = prior.tables.has(st.table) && !created.has(st.table);
    if (!prior.tables.has(st.table) && !created.has(st.table) && !schema.load(dir).tables.has(st.table))
      at(st, undefined, `Таблицы ${st.table} нет в миграциях до этой`, E);
    if (!existing) continue;
    for (const a of st.actions) {
      const l = a.text.toLowerCase();
      if (a.op === "add_column" && /not\s+null/.test(l) && !/default/.test(l) && !/generated/.test(l))
        at(st, a.text, `NOT NULL без DEFAULT: упадёт, если в ${st.table} уже есть строки. Добавь DEFAULT или сначала NULL → заполнить → SET NOT NULL`);
      else if (a.op === "add_constraint" && /foreign\s+key/.test(l) && !/not\s+valid/.test(l))
        at(st, a.text, "Внешний ключ проверяет всю таблицу под блокировкой: NOT VALID сейчас, VALIDATE CONSTRAINT — следующей миграцией");
      else if (a.op === "alter_type") at(st, a.text, `Смена типа ${a.col} переписывает всю таблицу ${st.table} под блокировкой`);
      else if (/alter\s+(column\s+)?\S+\s+set\s+not\s+null/.test(l))
        at(st, a.text, "SET NOT NULL читает всю таблицу под блокировкой. Быстрее: CHECK (col IS NOT NULL) NOT VALID → VALIDATE → SET NOT NULL");
      else if (a.op === "drop_column") at(st, a.text, `DROP COLUMN ${a.col}: работающий код, который читает колонку, сломается — сначала убери её из кода`, I);
      else if (a.op === "rename_column") at(st, a.text, `RENAME ${a.from} → ${a.to}: работающая версия приложения сломается до деплоя новой`, I);
      else if (a.op === "rename_table") at(st, a.text, "RENAME TABLE: работающая версия приложения сломается до деплоя новой", I);
    }
  }
  return out;
}
