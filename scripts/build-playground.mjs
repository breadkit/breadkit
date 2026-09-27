import fs from "node:fs/promises";
import path from "node:path";
import { execFileSync } from "node:child_process";

const root = path.resolve(import.meta.dirname, "..");
const lint = path.resolve(process.argv[2] || path.join(root, "..", "breadkit-lint"));
const render = path.resolve(process.argv[3] || path.join(root, "..", "breadkit-render"));
const matrix = path.join(root, "scripts", "playground-vendor", "matrix");
const output = path.join(root, "_site", "playground");
const sources = [
  ["core", root, ["lib", "data/boards", "data/parts"]],
  ["lint", lint, ["lib", "config", "locales"]],
  ["render", render, ["lib"]],
  ["matrix", matrix, ["lib"]]
];

async function filesUnder(directory) {
  const entries = await fs.readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await filesUnder(full));
    else if (entry.isFile() && /\.(rb|yml)$/.test(entry.name)) files.push(full);
  }
  return files;
}

const files = {};
const revisions = {};
for (const [mount, directory, folders] of sources) {
  if (mount !== "matrix") revisions[mount] = execFileSync("git", ["rev-parse", "HEAD"], { cwd: directory, encoding: "utf8" }).trim();
  for (const folder of folders) {
    for (const file of await filesUnder(path.join(directory, folder))) {
      const relative = path.relative(directory, file).split(path.sep).join("/");
      files[`/${mount}/${relative}`] = (await fs.readFile(file)).toString("base64");
    }
  }
}
await fs.mkdir(output, { recursive: true });
await fs.writeFile(path.join(output, "bundle.json"), JSON.stringify({ schema_version: 1, revisions, files }));
await fs.copyFile(path.join(matrix, "BSDL"), path.join(output, "matrix-license.txt"));
process.stdout.write(`Packed ${Object.keys(files).length} Ruby and YAML files for the Playground.\n`);
