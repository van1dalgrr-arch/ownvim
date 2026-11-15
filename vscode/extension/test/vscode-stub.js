class Position { constructor(l, c) { this.line = l; this.character = c; } }
class Range { constructor(a, b, c, d) { this.start = a instanceof Position ? a : new Position(a, b); this.end = a instanceof Position ? b : new Position(c, d); } }
class CompletionItem { constructor(label, kind) { this.label = label; this.kind = kind; } }
class SnippetString { constructor(v) { this.value = v; } }
class MarkdownString { constructor(v) { this.value = v; } }
class Hover { constructor(c, r) { this.contents = c; this.range = r; } }
class Diagnostic { constructor(r, m, s) { this.range = r; this.message = m; this.severity = s; } }
class EventEmitter { constructor() { this.event = () => ({ dispose() {} }); } fire() {} }
module.exports = {
  Position, Range, CompletionItem, SnippetString, MarkdownString, Hover, Diagnostic, EventEmitter,
  CompletionItemKind: new Proxy({}, { get: (_, k) => k }), DiagnosticSeverity: { Error: 0, Warning: 1, Information: 2 },
  workspace: { getConfiguration: () => ({ get: () => undefined }), textDocuments: [], workspaceFolders: [], getWorkspaceFolder: () => undefined },
  window: {}, Uri: { file: (p) => ({ fsPath: p }) },
};
