// Дополнение SQL из схемы миграций (как lua/own/sql/source.lua) — работает без базы и знает ещё не
// применённые миграции; нет миграций — по живой базе проекта:
//   FROM / JOIN / UPDATE / INTO / REFERENCES / ALTER TABLE …  → таблицы
//   u.  (таблица или её псевдоним)  → колонки этой таблицы
//   SELECT …, WHERE …, SET …  → колонки таблиц этого запроса и функции Postgres
//   INSERT INTO t (…), REFERENCES t(…), ON t (…)  → колонки t
//   CREATE TABLE (name |, ADD COLUMN name |, TYPE |, ::  → типы Postgres и свои enum; после типа — NOT NULL, DEFAULT…
//   status = '|  (колонка с enum-типом)  → значения enum
//   JOIN |  → сначала связанные внешним ключом; JOIN orders o |  → готовое ON o.user_id = u.id
//   FROM users u |  → WHERE, JOIN, GROUP BY, ORDER BY, LIMIT…
// Ещё: K (hover) — описание таблицы / колонки, gd — к миграции, где таблица создана.
import * as path from "path";
import * as vscode from "vscode";
import * as schema from "./schema";
import * as migrations from "./migrations";
import { liveSchema, projectRoot, projectUrl } from "./db";

type Entry = [string, string, string?]; // имя, описание, сниппет

const TYPES: Entry[] = [
  ["bigint", "целое 8 байт"], ["integer", "целое 4 байта"], ["smallint", "целое 2 байта"],
  ["bigserial", "bigint с автоувеличением (лучше GENERATED ALWAYS AS IDENTITY)"], ["serial", "integer с автоувеличением"],
  ["text", "строка любой длины"], ["varchar", "строка с пределом длины", "varchar(${1:255})"],
  ["citext", "строка без учёта регистра (расширение citext)"],
  ["boolean", "true / false"], ["uuid", "gen_random_uuid()"], ["timestamptz", "время с часовым поясом — почти всегда нужно оно"],
  ["timestamp", "время без пояса"], ["date", "дата"], ["time", "время дня"], ["interval", "промежуток времени"],
  ["numeric", "точное число — деньги", "numeric(${1:12}, ${2:2})"], ["double precision", "число с плавающей точкой 8 байт"],
  ["real", "4 байта"], ["jsonb", "JSON с индексами"], ["json", "JSON как текст"], ["bytea", "байты"],
  ["inet", "IP-адрес"], ["cidr", "сеть"], ["tsvector", "полнотекстовый поиск"], ["text[]", "массив строк"], ["bigint[]", "массив чисел"],
];

const CONSTRAINTS: Entry[] = [
  ["NOT NULL", "обязательное поле"], ["DEFAULT", "значение по умолчанию", "DEFAULT $1"], ["PRIMARY KEY", "первичный ключ"],
  ["UNIQUE", "уникальное"], ["REFERENCES", "внешний ключ", "REFERENCES ${1:users}(${2:id}) ON DELETE ${3:CASCADE}"],
  ["CHECK", "условие на значение", "CHECK ($1)"], ["GENERATED ALWAYS AS IDENTITY", "автоувеличение по стандарту SQL"],
  ["DEFAULT now()", "время вставки"], ["DEFAULT gen_random_uuid()", "новый uuid"],
];

const FROM_END = ["where", "join", "left", "right", "inner", "full", "cross", "group", "order", "limit", "having",
  "returning", "on", "union", "window", "for"];
const TABLE_KW = new Set(["from", "join", "update", "into", "table", "references", "truncate", "exists", "only"]);
const CLAUSES = ["select", "from", "where", "join", "on", "set", "values", "group", "order", "having", "returning", "using", "into", "update"];

const FUNCTIONS: Entry[] = [
  ["count(*)", "сколько строк"], ["count", "сколько не-NULL значений", "count(${1})"],
  ["sum", "сумма", "sum(${1})"], ["avg", "среднее", "avg(${1})"], ["min", "минимум", "min(${1})"], ["max", "максимум", "max(${1})"],
  ["coalesce", "первое не-NULL", "coalesce(${1}, ${2:0})"], ["nullif", "NULL, если равны", "nullif(${1}, ${2})"],
  ["now()", "текущее время (timestamptz)"], ["current_date", "сегодня"],
  ["date_trunc", "обрезать время до дня / месяца…", "date_trunc('${1|day,hour,week,month,year|}', ${2})"],
  ["extract", "часть даты: год, месяц…", "extract(${1|year,month,day,hour,epoch|} FROM ${2})"],
  ["to_char", "время / число → строка", "to_char(${1}, '${2:YYYY-MM-DD}')"],
  ["lower", "строчными", "lower(${1})"], ["upper", "ЗАГЛАВНЫМИ", "upper(${1})"], ["length", "длина строки", "length(${1})"],
  ["trim", "без пробелов по краям", "trim(${1})"], ["concat", "склеить строки", "concat(${1}, ${2})"],
  ["string_agg", "строки группы через разделитель", "string_agg(${1}, '${2:, }')"],
  ["array_agg", "значения группы → массив", "array_agg(${1})"], ["jsonb_agg", "строки группы → JSON-массив", "jsonb_agg(${1})"],
  ["jsonb_build_object", "собрать JSON-объект", "jsonb_build_object('${1:key}', ${2})"],
  ["row_number()", "номер строки в окне", "row_number() OVER (${1:PARTITION BY ${2} }ORDER BY ${3})"],
  ["rank()", "место с пропусками при равенстве", "rank() OVER (ORDER BY ${1})"],
  ["lag", "значение из прошлой строки окна", "lag(${1}) OVER (ORDER BY ${2})"],
  ["round", "округлить", "round(${1}, ${2:2})"], ["greatest", "наибольшее из", "greatest(${1}, ${2})"],
  ["gen_random_uuid()", "новый uuid"], ["exists", "есть ли строки в подзапросе", "EXISTS (SELECT 1 FROM ${1} WHERE ${2})"],
  ["CASE", "условие в выражении", "CASE WHEN ${1} THEN ${2} ELSE ${3} END"],
];

const AFTER_TABLE: Entry[] = [
  ["WHERE", "условие"], ["JOIN", "соединить", "JOIN "], ["LEFT JOIN", "соединить, строки слева остаются", "LEFT JOIN "],
  ["GROUP BY", "группировать", "GROUP BY "], ["ORDER BY", "сортировать", "ORDER BY "], ["LIMIT", "сколько строк", "LIMIT ${1:10}"],
  ["HAVING", "условие на группы"], ["RETURNING", "вернуть строки после изменения", "RETURNING ${1:*}"],
];

const K = vscode.CompletionItemKind;

/** Схема для документа: из папки миграций проекта (текст самого документа — несохранённый); иначе — живая база */
export function schemaFor(doc: vscode.TextDocument): schema.Schema | undefined {
  const file = doc.uri.fsPath;
  const d = migrations.dir(file);
  if (d) {
    const over = new Map<string, string>();
    for (const o of vscode.workspace.textDocuments) if (o.isDirty && path.dirname(o.uri.fsPath) === d) over.set(o.uri.fsPath, o.getText());
    const s = schema.load(d, over);
    if (s.tables.size) return s;
  }
  const u = projectUrl(projectRoot(file));
  const l = u && liveSchema(u.url);
  if (!l) return undefined;
  return { tables: new Map([...l.tables].map(([k, t]) => [k, { name: t.name, cols: t.cols.map((c) => ({ ...c })), file: "база " + u!.name }])), enums: l.enums };
}

// выражение вокруг курсора: текст до курсора и после (до «;»)
function around(doc: vscode.TextDocument, pos: vscode.Position): [string, string] {
  const text = doc.getText();
  const off = doc.offsetAt(pos);
  let before = text.slice(0, off).replace(/--[^\n]*\n/g, "\n");
  let after = text.slice(off);
  const semi = before.lastIndexOf(";");
  if (semi >= 0) before = before.slice(semi + 1);
  const e = after.indexOf(";");
  if (e >= 0) after = after.slice(0, e);
  return [before, after];
}

/** Таблицы запроса: имя/псевдоним → таблица, и список по порядку */
export function tablesIn(text: string, known: Map<string, schema.Table>): [Map<string, string>, string[]] {
  const l = " " + text.toLowerCase().replace(/--[^\n]*/g, "").replace(/\s+/g, " ") + " ";
  const map = new Map<string, string>(), list: string[] = [];
  const add = (n: string, alias?: string) => {
    const name = schema.ident(n);
    if (!name || !known.has(name)) return;
    if (!map.has(name)) list.push(name);
    map.set(name, name);
    if (alias && !schema.KEYWORDS.has(alias)) map.set(alias, name);
  };
  for (const kw of ["join", "update", "into", "table", "references"])
    for (const m of l.matchAll(new RegExp(`\\s${kw}\\s+([\\w".]+)\\s*(\\w*)\\s*(\\w*)`, "g"))) add(m[1], m[2] === "as" ? m[3] : m[2]);
  for (const m of l.matchAll(/\sfrom\s+/g)) {
    let rest = l.slice(m.index! + m[0].length);
    let stop = rest.length;
    for (const kw of FROM_END) { const p = rest.search(new RegExp(`\\s${kw}\\s`)); if (p >= 0 && p < stop) stop = p; }
    rest = rest.slice(0, stop).replace(/[;)].*$/, "");
    for (const item of rest.split(",")) {
      const im = item.trim().match(/^([\w".]+)\s*(\w*)\s*(\w*)$/);
      if (im) add(im[1], im[2] === "as" ? im[3] : im[2]);
    }
  }
  return [map, list];
}

export function columnDoc(t: schema.Table, c: schema.Column): vscode.MarkdownString {
  let s = `**${t.name}.${c.name}** \`${c.type || "?"}\``;
  if (c.notes) s += "\n\n" + c.notes;
  return new vscode.MarkdownString(s + `\n\n_${c.file || t.file || ""}_`);
}

export function tableDoc(t: schema.Table): vscode.MarkdownString {
  const rows = t.cols.map((c) => `  ${c.name.padEnd(16)} ${c.type}${c.notes ? "  -- " + c.notes : ""}`);
  return new vscode.MarkdownString(`**${t.name}**${t.view ? " (view)" : ""}\n\`\`\`sql\n${rows.join("\n")}\n\`\`\`\n_${t.file || ""}_`);
}

function item(label: string, kind: vscode.CompletionItemKind, description?: string, detail?: string) {
  const it = new vscode.CompletionItem({ label, description, detail }, kind);
  return it;
}

function columns(items: vscode.CompletionItem[], t: schema.Table, score = 1) {
  t.cols.forEach((c, i) => {
    const it = item(c.name, K.Field, t.name, " " + c.type);
    it.documentation = columnDoc(t, c);
    it.sortText = `${score}${String(i).padStart(4, "0")}`;
    items.push(it);
  });
}

function tables(items: vscode.CompletionItem[], s: schema.Schema) {
  for (const [name, t] of s.tables) {
    const it = item(name, K.Class, `${t.cols.length} кол.`);
    it.documentation = tableDoc(t);
    it.sortText = "2" + name;
    items.push(it);
  }
}

function keywords(items: vscode.CompletionItem[], list: Entry[], kind: vscode.CompletionItemKind, prefix = "") {
  list.forEach(([label, desc, snip], i) => {
    const it = item(label, kind, desc);
    if (snip) it.insertText = new vscode.SnippetString(snip);
    it.sortText = prefix + String(i).padStart(4, "0");
    items.push(it);
  });
}

function types(items: vscode.CompletionItem[], s?: schema.Schema) {
  keywords(items, TYPES, K.TypeParameter, "1");
  for (const [name, vals] of s?.enums || []) {
    const it = item(name, K.Enum, "enum: " + vals.join(", "));
    it.sortText = "0" + name;
    items.push(it);
  }
}

export function complete(doc: vscode.TextDocument, pos: vscode.Position): vscode.CompletionItem[] {
  const s = schemaFor(doc);
  const [before, after] = around(doc, pos);
  const lb = before.toLowerCase();
  const prev = lb.replace(/\w*$/, "");
  const last = prev.match(/(\w+)\s*$/)?.[1];
  const items: vscode.CompletionItem[] = [];
  const [tmap, tlist] = tablesIn(before + " " + after, s?.tables || new Map());

  // значение enum: status = 'w|
  const colEq = lb.match(/([\w.]+)\s*=\s*'[^']*$/)?.[1] || lb.match(/([\w.]+)\s+in\s*\(\s*'[^']*$/)?.[1];
  if (colEq && s) {
    const qm = colEq.match(/^(\w+)\.(\w+)$/);
    const cname = qm ? qm[2] : colEq;
    for (const tname of qm ? [tmap.get(qm[1])] : tlist)
      for (const c of s.tables.get(tname || "")?.cols || [])
        if (c.name === cname && s.enums.has(c.type)) for (const v of s.enums.get(c.type)!) items.push(item(v, K.EnumMember, c.type));
    return items;
  }
  if (/'[^']*$/.test(lb) && (lb.match(/'/g)?.length || 0) % 2 === 1) return items; // внутри строки

  if (/::\s*$/.test(prev)) { types(items, s); return items; }

  // u.| — колонки таблицы или псевдонима
  const q = lb.match(/([\w"]+)\.\w*$/)?.[1];
  if (q && s) {
    const t = s.tables.get(tmap.get(schema.ident(q)) || schema.ident(q));
    if (t) columns(items, t);
    return items;
  }

  // внутри скобок: CREATE TABLE (…), INSERT INTO t (…), REFERENCES t(…), ON t (…)
  let depth = 0, open = -1;
  for (let i = lb.length - 1; i >= 0; i--) {
    if (lb[i] === ")") depth++;
    else if (lb[i] === "(") { if (depth === 0) { open = i; break; } depth--; }
  }
  if (open >= 0) {
    const head = lb.slice(0, open), inside = lb.slice(open + 1);
    const ref = head.match(/references\s+([\w".]+)\s*$/)?.[1] || head.match(/insert\s+into\s+([\w".]+)\s*$/)?.[1]
      || head.match(/\son\s+(?:only\s+)?([\w".]+)\s*$/)?.[1];
    if (ref) {
      const t = s?.tables.get(schema.ident(ref));
      if (t) columns(items, t);
      return items;
    }
    if (/create\s+[\w\s]*?table\s+[\w\s".]*$/.test(head)) {
      const it = inside.match(/[^,]*$/)![0];
      const words = it.match(/\S+/g)?.length || 0;
      const sp = /\s$/.test(it);
      if (sp && words === 1 && !/^\s*constraint/.test(it)) { types(items, s); return items; }
      if (sp && words >= 2) { keywords(items, CONSTRAINTS, K.Keyword); return items; }
      if (words === 0 || (words === 1 && !sp)) return items; // имя новой колонки — придумываешь сам
    }
  }

  if (/add\s+column\s+(?:if\s+not\s+exists\s+)?[\w"]+\s+$/.test(lb) || /\stype\s+$/.test(lb) || /set\s+data\s+type\s+$/.test(lb)) {
    types(items, s);
    return items;
  }
  if (/add\s+column\s+[\w"]+\s+[\w[\]()]+[^,]*\s$/.test(lb)) { keywords(items, CONSTRAINTS, K.Keyword); return items; }

  if (!s || !last) return items; // начало выражения — тут слова SQL, не колонки

  let clause: string | undefined, best = -1;
  for (const kw of CLAUSES) {
    for (const m of prev.matchAll(new RegExp(`\\b${kw}\\b`, "g"))) if (m.index! > best) { best = m.index!; clause = kw; }
  }

  if (TABLE_KW.has(last) || (clause === "from" && /,\s*$/.test(prev))) {
    tables(items, s);
    if (last === "join") {
      const related = new Set<string>();
      for (const name of tlist) for (const c of s.tables.get(name)!.cols) if (c.ref) related.add(c.ref.table);
      for (const [tname, t] of s.tables) for (const c of t.cols) if (c.ref && tlist.includes(c.ref.table)) related.add(tname);
      for (const it of items) {
        const l = (it.label as vscode.CompletionItemLabel).label;
        if (related.has(l)) { it.sortText = "0" + l; (it.label as vscode.CompletionItemLabel).detail = " связана"; }
        else it.sortText = "1" + l;
      }
    }
    return items;
  }

  // JOIN orders o |  или  JOIN orders o ON |  — условие по внешнему ключу
  const jm = prev.match(/join\s+([\w".]+)\s*(\w*)\s*(\w*)\s*(o?n?)\s*$/);
  if (jm && (jm[4] === "on" || jm[4] === "") && /\s$/.test(prev)) {
    const [, jname, ja1, ja2] = jm;
    let on = jm[4];
    const joined = schema.ident(jname);
    const jalias = (ja1 === "as" && ja2) || (ja1 && ja1 !== "as" && ja1 !== "on" && ja1) || joined;
    if (ja1 === "on" || ja2 === "on") on = "on";
    const jt = s.tables.get(joined);
    if (jt) {
      const aliasOf = new Map<string, string>();
      for (const [a, t] of tmap) if (a !== t) aliasOf.set(t, a);
      const conds: string[] = [];
      for (const other of tlist) {
        if (other === joined) continue;
        const oa = aliasOf.get(other) || other;
        for (const c of jt.cols) if (c.ref?.table === other) conds.push(`${jalias}.${c.name} = ${oa}.${c.ref.col}`);
        for (const c of s.tables.get(other)!.cols) if (c.ref?.table === joined) conds.push(`${jalias}.${c.ref.col} = ${oa}.${c.name}`);
      }
      conds.forEach((cond, i) => {
        const it = item(on === "on" ? cond : "ON " + cond, K.Reference, "внешний ключ");
        it.sortText = "0" + String(i).padStart(3, "0");
        items.push(it);
      });
      if (on === "" && (ja1 || ja2)) keywords(items, [["ON", "условие соединения"], ["USING", "по одноимённой колонке", "USING (${1:id})"]], K.Keyword, "1");
      if (items.length) return items;
    }
  }

  // FROM users u |  — дальше WHERE, JOIN, GROUP BY…
  if ((clause === "from" || clause === "join") && /\s$/.test(prev) && /[\w"]+\s+\w*\s*$/.test(prev)
    && !/[=<>!,(]\s*$/.test(prev) && !/\son\s+.*$/.test(prev)) {
    const tail = prev.match(new RegExp(clause + "\\s+(.*?)\\s*$"))?.[1] || "";
    const words = tail.match(/[^\s,]+/g)?.length || 0;
    if (tail && !/\sas$/.test(tail) && words <= 2) { keywords(items, AFTER_TABLE, K.Keyword); return items; }
  }
  if (last === "drop" || last === "alter" || last === "create") return items;

  if (tlist.length) for (const name of tlist) columns(items, s.tables.get(name)!, 1);
  else { for (const t of s.tables.values()) columns(items, t, 2); tables(items, s); }
  if (clause !== "into" && clause !== "update") keywords(items, FUNCTIONS, K.Function, "3");
  return items;
}

/** K: описание таблицы или колонки под курсором */
export function hover(doc: vscode.TextDocument, pos: vscode.Position): vscode.Hover | undefined {
  const s = schemaFor(doc);
  const r = doc.getWordRangeAtPosition(pos, /[\w.]+/);
  if (!s || !r) return undefined;
  const word = doc.getText(r).toLowerCase();
  const [before, after] = around(doc, pos);
  const [tmap, tlist] = tablesIn(before + " " + after, s.tables);
  const [a, b] = word.includes(".") ? word.split(".") : [undefined, word];
  const tb = !a && s.tables.get(tmap.get(b) || b);
  if (tb) return new vscode.Hover(tableDoc(tb), r);
  const where = a ? [tmap.get(a) || a] : tlist.length ? tlist : [...s.tables.keys()];
  for (const tn of where) {
    const t = s.tables.get(tn);
    const c = t?.cols.find((x) => x.name === b);
    if (t && c) return new vscode.Hover(columnDoc(t, c), r);
  }
  return undefined;
}

/** gd на таблице — к миграции, где её создали */
export function definition(doc: vscode.TextDocument, pos: vscode.Position): vscode.Location | undefined {
  const r = doc.getWordRangeAtPosition(pos, /\w+/);
  const d = migrations.dir(doc.uri.fsPath);
  if (!r || !d) return undefined;
  const s = schema.load(d);
  const [before, after] = around(doc, pos);
  const name = doc.getText(r).toLowerCase();
  const tname = tablesIn(before + " " + after, s.tables)[0].get(name) || name;
  const t = s.tables.get(tname);
  let file = t?.file;
  if (!t) for (const tb of s.tables.values()) { const c = tb.cols.find((x) => x.name === name); if (c) { file = c.file; break; } }
  if (!file) return undefined;
  const full = path.join(d, file);
  const text = require("fs").readFileSync(full, "utf8") as string;
  const idx = text.toLowerCase().search(new RegExp(`\\b${t ? "table\\s+(if\\s+not\\s+exists\\s+)?" : ""}"?${tname}\\b`));
  const line = idx < 0 ? 0 : text.slice(0, idx).split("\n").length - 1;
  return new vscode.Location(vscode.Uri.file(full), new vscode.Position(line, 0));
}
