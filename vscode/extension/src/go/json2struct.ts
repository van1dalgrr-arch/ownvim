// JSON → Go struct с тегами: пробел G p (или alt-enter на выделенном JSON в .go).
//   Откуда: выделение, если это JSON (заменится на struct), иначе буфер обмена.
//   Вложенные объекты — отдельными типами (Order → OrderItem), массивы объектов — поля всех элементов
//   вместе: нет в части элементов или бывает null — ,omitempty и указатель; целые — int64, дробные — float64,
//   строки времени RFC 3339 — time.Time; ID, URL, API… — как принято в Go.
import * as vscode from "vscode";

const INITIALISMS = new Set(["ACL", "API", "ASCII", "CPU", "CSS", "DB", "DNS", "EOF", "GUID", "HTML", "HTTP", "HTTPS", "ID", "IDS", "IP", "JSON",
  "JWT", "LHS", "OK", "QPS", "RAM", "RHS", "RPC", "SKU", "SLA", "SMTP", "SQL", "SSH", "TCP", "TLS", "TTL", "UDP", "UI", "UID", "URI", "URL", "UTF8",
  "UUID", "VM", "XML", "XSRF", "XSS"]);
const RFC3339 = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$/;

/** created_at / createdAt / created-at → CreatedAt; user_id → UserID */
export function goName(key: string): string {
  const words = key.replace(/([a-z0-9])([A-Z])/g, "$1 $2").split(/[^A-Za-z0-9]+/).filter(Boolean);
  let name = words.map((w) => {
    const up = w.toUpperCase();
    if (INITIALISMS.has(up)) return up === "IDS" ? "IDs" : up;
    return w[0].toUpperCase() + w.slice(1);
  }).join("");
  if (!name) name = "Field";
  if (/^\d/.test(name)) name = "N" + name;
  return name;
}

// Тип значения: объединяем все встреченные образцы (элементы массива, одно поле в разных объектах)
interface Shape {
  kinds: Set<"string" | "time" | "int" | "float" | "bool" | "object" | "array" | "null">;
  fields?: Map<string, { shape: Shape; count: number }>; // для объектов: ключ → форма и в скольких объектах есть
  objects?: number;                                         // сколько объектов слилось
  elem?: Shape;                                             // для массивов
}

const empty = (): Shape => ({ kinds: new Set() });

function add(shape: Shape, v: unknown): Shape {
  if (v === null) shape.kinds.add("null");
  else if (typeof v === "string") shape.kinds.add(RFC3339.test(v) ? "time" : "string");
  else if (typeof v === "number") shape.kinds.add(Number.isInteger(v) ? "int" : "float");
  else if (typeof v === "boolean") shape.kinds.add("bool");
  else if (Array.isArray(v)) {
    shape.kinds.add("array");
    shape.elem ??= empty();
    for (const x of v) add(shape.elem, x);
  } else if (typeof v === "object") {
    shape.kinds.add("object");
    shape.fields ??= new Map();
    shape.objects = (shape.objects || 0) + 1;
    for (const [k, x] of Object.entries(v as Record<string, unknown>)) {
      const f = shape.fields.get(k) || { shape: empty(), count: 0 };
      f.count++;
      add(f.shape, x);
      shape.fields.set(k, f);
    }
  }
  return shape;
}

export interface Options { name: string; inline?: boolean; omitempty?: boolean }

export function generate(json: unknown, opts: Options): string {
  const types: string[] = [];
  const used = new Set<string>();
  const unique = (n: string) => { let x = n, i = 2; while (used.has(x)) x = n + i++; used.add(x); return x; };

  const typeOf = (s: Shape, name: string): string => {
    const k = new Set([...s.kinds].filter((x) => x !== "null"));
    if (k.has("int") && k.has("float")) k.delete("int");
    if (k.has("time") && k.has("string")) k.delete("time");
    if (k.size === 0) return "any";
    if (k.size > 1) return "any";
    const [one] = k;
    switch (one) {
      case "string": return "string";
      case "time": return "time.Time";
      case "int": return "int64";
      case "float": return "float64";
      case "bool": return "bool";
      case "array": {
        const e = s.elem!;
        // элемент массива объектов — единственное число: items → Item
        return "[]" + typeOf(e, singular(name));
      }
      case "object": return struct(s, name);
    }
    return "any";
  };

  const struct = (s: Shape, name: string): string => {
    const tname = unique(name);
    const lines: [string, string, string][] = [];
    const names = new Set<string>();
    for (const [key, f] of s.fields || []) {
      let fname = goName(key);
      while (names.has(fname)) fname += "_";
      names.add(fname);
      const optional = f.count < (s.objects || 1) || f.shape.kinds.has("null");
      let t = typeOf(f.shape, tname + fname);
      if (optional && f.shape.kinds.has("null") && !/^(\[\]|map|any)/.test(t)) t = "*" + t;
      const omit = optional || opts.omitempty ? ",omitempty" : "";
      lines.push([fname, t, `\`json:"${key}${omit}"\``]);
    }
    // выровнять колонки, как gofmt
    const w1 = Math.max(0, ...lines.map((l) => l[0].length)), w2 = Math.max(0, ...lines.map((l) => l[1].length));
    const body = lines.map(([a, b, c]) => `\t${a.padEnd(w1)} ${b.padEnd(w2)} ${c}`).join("\n");
    types.push(`type ${tname} struct {\n${body}${body ? "\n" : ""}}`);
    return tname;
  };

  const root = add(empty(), json);
  // массив объектов — сразу тип элемента ([]Event пишется уже в коде), без обёртки
  if (root.kinds.has("array") && root.elem?.kinds.has("object")) typeOf(root.elem, opts.name);
  else {
    const top = typeOf(root, opts.name);
    if (!root.kinds.has("object")) types.push(`type ${unique(opts.name)} ${top}`);
  }
  // корневой тип первым, вложенные — за ним
  return types.reverse().join("\n\n") + "\n";
}

function singular(name: string): string {
  if (/ies$/.test(name)) return name.replace(/ies$/, "y");
  if (/(ss|us|is)$/.test(name)) return name;
  if (/(ses|xes|ches|shes)$/.test(name)) return name.replace(/es$/, "");
  if (/s$/.test(name)) return name.slice(0, -1);
  return name + "Item";
}

/** JSON из текста: строгий, а если не вышло — терпимый (хвостовые запятые, ключи без кавычек, одинарные кавычки) */
export function parse(text: string): unknown | undefined {
  const t = text.trim();
  if (!/^[[{]/.test(t)) return undefined;
  try { return JSON.parse(t); } catch { /* терпимый разбор ниже */ }
  try {
    const loose = t.replace(/,\s*([}\]])/g, "$1").replace(/([{,]\s*)([A-Za-z_$][\w$]*)\s*:/g, '$1"$2":').replace(/'([^'\\]*)'/g, '"$1"');
    return JSON.parse(loose);
  } catch { return undefined; }
}

async function run(range?: vscode.Range) {
  const ed = vscode.window.activeTextEditor;
  if (!ed) return;
  let target: vscode.Range | undefined = range ?? (ed.selection.isEmpty ? undefined : ed.selection);
  let json = target ? parse(ed.document.getText(target)) : undefined;
  if (json === undefined) {
    target = undefined;
    json = parse(await vscode.env.clipboard.readText());
  }
  if (json === undefined) return vscode.window.showWarningMessage("JSON не нашёлся: выдели его в файле или скопируй в буфер обмена");
  const guess = Array.isArray(json) ? "Item" : "Response";
  const name = await vscode.window.showInputBox({ title: "JSON → struct", prompt: "Имя типа", value: guess, valueSelection: [0, guess.length] });
  if (!name) return;
  const code = generate(json, { name: goName(name) });
  const at = target ?? new vscode.Range(ed.selection.active.with(undefined, 0), ed.selection.active.with(undefined, 0));
  await ed.edit((e) => e.replace(at, code));
  // time.Time → импорт добавится сам при сохранении (organizeImports)
}

class Action implements vscode.CodeActionProvider {
  provideCodeActions(doc: vscode.TextDocument, range: vscode.Range): vscode.CodeAction[] {
    if (range.isEmpty || parse(doc.getText(range)) === undefined) return [];
    const a = new vscode.CodeAction("JSON → struct с тегами", vscode.CodeActionKind.RefactorRewrite);
    a.command = { title: a.title, command: "ownvim.go.json2struct", arguments: [range] };
    return [a];
  }
}

export function activate(ctx: vscode.ExtensionContext) {
  ctx.subscriptions.push(
    vscode.commands.registerCommand("ownvim.go.json2struct", (r?: vscode.Range) => run(r instanceof vscode.Range ? r : undefined)),
    vscode.languages.registerCodeActionsProvider({ language: "go" }, new Action(), { providedCodeActionKinds: [vscode.CodeActionKind.RefactorRewrite] }),
  );
}
