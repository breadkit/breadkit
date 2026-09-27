import assert from "node:assert/strict";
import fs from "node:fs/promises";

const root = new URL("../_site/playground/", import.meta.url);
const bundle = JSON.parse(await fs.readFile(new URL("bundle.json", root), "utf8"));
assert.equal(bundle.schema_version, 1);
for (const name of ["core", "lint", "render"]) {
  assert.match(bundle.revisions[name], /^[a-f0-9]{40}$/);
}
for (const file of [
  "/core/lib/breadkit.rb",
  "/core/data/boards/half.yml",
  "/lint/lib/breadkit/lint.rb",
  "/render/lib/breadkit/render.rb",
  "/matrix/lib/matrix.rb"
]) {
  assert.ok(bundle.files[file], `Missing ${file}`);
}
for (const file of ["index.html", "app.js", "worker.js", "matrix-license.txt"]) {
  assert.ok((await fs.stat(new URL(file, root))).size > 0, `Missing ${file}`);
}
console.log("Playground bundle contains the runtime sources and page assets.");
