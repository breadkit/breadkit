"use strict";

const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const vm = require("node:vm");

test("restarts the language server when a circuit is opened after it exits", async () => {
  const document = {
    uri: { scheme: "file", fsPath: "/tmp/circuit.bk.yml", toString: () => "file:///tmp/circuit.bk.yml" },
    languageId: "yaml", version: 1, getText: () => "board: full"
  };
  let onOpen;
  const processes = [];
  const vscode = {
    workspace: {
      workspaceFolders: [{ uri: { fsPath: "/tmp" } }], textDocuments: [document], isTrusted: false,
      getConfiguration: () => ({ get: (_, fallback) => fallback }),
      onDidOpenTextDocument: callback => { onOpen = callback; return {}; },
      onDidChangeTextDocument: () => ({}), onDidCloseTextDocument: () => ({})
    },
    window: { createOutputChannel: () => ({ append() {}, appendLine() {} }) },
    commands: { registerCommand: () => ({}) },
    languages: {
      createDiagnosticCollection: () => ({ delete() {} }),
      registerCompletionItemProvider: () => ({}), registerHoverProvider: () => ({})
    }
  };
  function spawn() {
    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.exitCode = null;
    child.stdin = { write(chunk) {
      if (!Buffer.isBuffer(chunk)) return;
      const message = JSON.parse(chunk.toString());
      if (message.method !== "initialize") return;
      const body = Buffer.from(JSON.stringify({ jsonrpc: "2.0", id: message.id, result: {} }));
      queueMicrotask(() => child.stdout.emit("data", Buffer.concat([
        Buffer.from(`Content-Length: ${body.length}\r\n\r\n`), body
      ])));
    } };
    child.kill = () => { child.exitCode = 0; child.emit("exit", 0); };
    processes.push(child);
    return child;
  }
  const extension = { exports: {} };
  vm.runInNewContext(readFileSync(join(__dirname, "extension.js"), "utf8"), {
    module: extension, Buffer, process, setTimeout, queueMicrotask,
    require: name => {
      if (name === "vscode") return vscode;
      if (name === "node:child_process") return { spawn, execFile() {} };
      return require(name);
    }
  });
  await extension.exports.activate({ subscriptions: [] });
  assert.equal(processes.length, 1);

  processes[0].exitCode = 1;
  processes[0].emit("exit", 1);
  onOpen(document);
  await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(processes.length, 2);
  extension.exports.deactivate();
});
