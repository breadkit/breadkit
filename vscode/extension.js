"use strict";

const vscode = require("vscode");
const { execFile, spawn } = require("node:child_process");
const { promisify } = require("node:util");

const execFileAsync = promisify(execFile);
const selector = ["**/*.bk.yml", "**/*.bk.yaml", "**/*.bk.toml", "**/*.bk.rb"]
  .map(pattern => ({ scheme: "file", pattern }));
let server;

function isCircuit(document) {
  return document.uri.scheme === "file" && /\.bk\.(?:ya?ml|toml|rb)$/.test(document.uri.fsPath);
}

class LanguageServer {
  constructor(output, diagnostics) {
    this.output = output;
    this.diagnostics = diagnostics;
    this.buffer = Buffer.alloc(0);
    this.pending = new Map();
    this.opened = new Set();
    this.nextId = 1;
    this.ready = false;
    const config = vscode.workspace.getConfiguration("breadkit");
    const folders = vscode.workspace.workspaceFolders || [];
    const root = folders.length === 1 ? folders[0].uri.fsPath : undefined;
    const args = root ? ["--root", root] : [];
    if (root && vscode.workspace.isTrusted && config.get("evaluateRubyDsl", false)) args.push("--trusted-ruby");
    this.process = spawn(config.get("serverCommand", "breadkit-lsp"), args,
      { cwd: root, stdio: ["pipe", "pipe", "pipe"] });
    this.process.stdout.on("data", chunk => this.receive(chunk));
    this.process.stderr.on("data", chunk => output.append(chunk.toString()));
    this.process.on("error", error => output.appendLine(`Language server failed: ${error.message}`));
    this.process.on("exit", () => {
      for (const callback of this.pending.values()) callback({ error: { message: "Language server exited" } });
      this.pending.clear();
      this.ready = false;
    });
  }

  send(message) {
    const body = Buffer.from(JSON.stringify({ jsonrpc: "2.0", ...message }), "utf8");
    this.process.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
    this.process.stdin.write(body);
  }

  request(method, params) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, result => result.error ? reject(new Error(result.error.message)) : resolve(result.result));
      this.send({ id, method, params });
    });
  }

  notify(method, params) {
    this.send({ method, params });
  }

  async start() {
    await this.request("initialize", { processId: process.pid, capabilities: {} });
    this.notify("initialized", {});
    this.ready = true;
    for (const document of vscode.workspace.textDocuments) this.open(document);
  }

  receive(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    while (true) {
      const headerEnd = this.buffer.indexOf("\r\n\r\n");
      if (headerEnd < 0) return;
      const match = /(?:^|\r\n)Content-Length: (\d+)/i.exec(this.buffer.subarray(0, headerEnd).toString("ascii"));
      if (!match) return;
      const length = Number(match[1]);
      if (this.buffer.length < headerEnd + 4 + length) return;
      const body = this.buffer.subarray(headerEnd + 4, headerEnd + 4 + length);
      this.buffer = this.buffer.subarray(headerEnd + 4 + length);
      this.handle(JSON.parse(body.toString("utf8")));
    }
  }

  handle(message) {
    if (message.id !== undefined) {
      const callback = this.pending.get(message.id);
      this.pending.delete(message.id);
      callback?.(message);
      return;
    }
    if (message.method !== "textDocument/publishDiagnostics") return;
    const uri = vscode.Uri.parse(message.params.uri);
    const items = message.params.diagnostics.map(item => {
      const start = item.range.start, end = item.range.end;
      const range = new vscode.Range(start.line, start.character, end.line, end.character);
      const severity = [undefined, vscode.DiagnosticSeverity.Error, vscode.DiagnosticSeverity.Warning,
        vscode.DiagnosticSeverity.Information, vscode.DiagnosticSeverity.Hint][item.severity] || vscode.DiagnosticSeverity.Error;
      const diagnostic = new vscode.Diagnostic(range, item.message, severity);
      diagnostic.code = item.code;
      diagnostic.source = item.source;
      return diagnostic;
    });
    this.diagnostics.set(uri, items);
  }

  open(document) {
    if (!this.ready || !isCircuit(document) || this.opened.has(document.uri.toString())) return;
    this.opened.add(document.uri.toString());
    this.notify("textDocument/didOpen", { textDocument: { uri: document.uri.toString(), languageId: document.languageId,
      version: document.version, text: document.getText() } });
  }

  change(document) {
    if (!this.ready || !isCircuit(document)) return;
    if (!this.opened.has(document.uri.toString())) return this.open(document);
    this.notify("textDocument/didChange", { textDocument: { uri: document.uri.toString(), version: document.version },
      contentChanges: [{ text: document.getText() }] });
  }

  close(document) {
    if (!this.opened.delete(document.uri.toString())) return;
    this.notify("textDocument/didClose", { textDocument: { uri: document.uri.toString() } });
    this.diagnostics.delete(document.uri);
  }

  stop() {
    if (this.process.exitCode !== null) return;
    if (!this.ready) return this.process.kill();
    this.request("shutdown", null).then(() => this.notify("exit", null)).catch(() => this.process.kill());
    setTimeout(() => this.process.kill(), 1000).unref();
  }
}

async function preview() {
  const document = vscode.window.activeTextEditor?.document;
  if (!document || !isCircuit(document)) {
    vscode.window.showInformationMessage("Open a Breadkit circuit file to preview it.");
    return;
  }
  if (!vscode.workspace.isTrusted) {
    vscode.window.showWarningMessage("Trust this workspace before running the Breadkit renderer.");
    return;
  }
  if (document.isDirty) {
    vscode.window.showInformationMessage("Save the circuit before previewing it.");
    return;
  }
  if (document.uri.fsPath.endsWith(".bk.rb") && !vscode.workspace.getConfiguration("breadkit").get("evaluateRubyDsl", false)) {
    vscode.window.showWarningMessage("Enable breadkit.evaluateRubyDsl to preview trusted Ruby DSL files.");
    return;
  }
  try {
    const command = vscode.workspace.getConfiguration("breadkit").get("renderCommand", "bkrender");
    const { stdout } = await execFileAsync(command, ["--format", "svg", "--theme", "dark", "--static", document.uri.fsPath],
      { cwd: vscode.workspace.getWorkspaceFolder(document.uri)?.uri.fsPath, maxBuffer: 16 * 1024 * 1024, timeout: 30_000 });
    const panel = vscode.window.createWebviewPanel("breadkitPreview", `Breadkit: ${document.uri.path.split("/").pop()}`,
      vscode.ViewColumn.Beside, { enableScripts: false });
    const image = Buffer.from(stdout, "utf8").toString("base64");
    panel.webview.html = `<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'"><meta name="viewport" content="width=device-width, initial-scale=1"><style>html,body{margin:0;background:#111827}img{display:block;max-width:100%;margin:auto}</style></head><body><img alt="Breadboard circuit preview" src="data:image/svg+xml;base64,${image}"></body></html>`;
  } catch (error) {
    vscode.window.showErrorMessage(`Breadkit preview failed: ${error.stderr?.trim() || error.message}`);
  }
}

async function activate(context) {
  const output = vscode.window.createOutputChannel("Breadkit");
  const diagnostics = vscode.languages.createDiagnosticCollection("breadkit");
  context.subscriptions.push(output, diagnostics, vscode.commands.registerCommand("breadkit.preview", preview));
  async function ensureServer() {
    if (server) return;
    server = new LanguageServer(output, diagnostics);
    try {
      await server.start();
    } catch (error) {
      output.appendLine(`Language server failed: ${error.message}`);
      vscode.window.showWarningMessage("Breadkit language server could not start. Install the breadkit gem or configure breadkit.serverCommand.");
      server = undefined;
    }
  }
  context.subscriptions.push(vscode.workspace.onDidOpenTextDocument(document => {
    if (isCircuit(document)) void ensureServer().then(() => server?.open(document));
  }));
  context.subscriptions.push(vscode.workspace.onDidChangeTextDocument(event => server?.change(event.document)));
  context.subscriptions.push(vscode.workspace.onDidCloseTextDocument(document => server?.close(document)));
  context.subscriptions.push(vscode.languages.registerCompletionItemProvider(selector, {
    async provideCompletionItems(document, position) {
      if (!server?.ready) return [];
      const items = await server.request("textDocument/completion", { textDocument: { uri: document.uri.toString() }, position });
      return items.map(item => new vscode.CompletionItem(item.label,
        item.kind === 5 ? vscode.CompletionItemKind.Field : vscode.CompletionItemKind.Variable));
    }
  }, ".", ":", "\"", "'"));
  context.subscriptions.push(vscode.languages.registerHoverProvider(selector, {
    async provideHover(document, position) {
      if (!server?.ready) return undefined;
      const result = await server.request("textDocument/hover", { textDocument: { uri: document.uri.toString() }, position });
      return result ? new vscode.Hover(new vscode.MarkdownString(result.contents.value)) : undefined;
    }
  }));
  if (vscode.workspace.textDocuments.some(isCircuit)) await ensureServer();
}

function deactivate() {
  server?.stop();
  server = undefined;
}

module.exports = { activate, deactivate };
