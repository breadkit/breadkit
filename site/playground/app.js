const source = document.querySelector("#source");
const status = document.querySelector("#status");
const diagnostics = document.querySelector("#diagnostics");
const nets = document.querySelector("#nets");
const diagram = document.querySelector("#diagram");
const emptyPreview = document.querySelector("#empty-preview");
const runButton = document.querySelector("#run");

let worker;
let activeId = 0;
let pendingSource;
let timeout;
let debounce;
let imageUrl;

function clearPreview() {
  if (imageUrl) URL.revokeObjectURL(imageUrl);
  imageUrl = undefined;
  diagram.hidden = true;
  diagram.removeAttribute("src");
  emptyPreview.hidden = false;
  diagnostics.replaceChildren();
  nets.replaceChildren();
}

function addItem(list, text) {
  const item = document.createElement("li");
  item.textContent = text;
  list.append(item);
}

function showResult(result) {
  clearPreview();
  if (result.error) {
    status.textContent = "The circuit could not be evaluated.";
    addItem(diagnostics, result.error);
    return;
  }

  for (const item of [...result.diagnostics, ...result.offenses]) {
    const location = item.line ? `Line ${item.line}: ` : "";
    addItem(diagnostics, `${location}${item.severity} · ${item.rule || item.code}: ${item.message}`);
  }
  if (!diagnostics.children.length) addItem(diagnostics, "No wiring issues found.");
  for (const net of result.nets) addItem(nets, `${net.name} · ${net.members} connections`);
  if (result.svg) {
    imageUrl = URL.createObjectURL(new Blob([result.svg], { type: "image/svg+xml" }));
    diagram.src = imageUrl;
    diagram.hidden = false;
    emptyPreview.hidden = true;
  }
  status.textContent = `Ready · ${result.offenses.length} wiring checks, ${result.nets.length} nets`;
}

function resetWorker() {
  if (worker) worker.terminate();
  worker = new Worker("./worker.js", { type: "module" });
  worker.addEventListener("message", ({ data }) => {
    if (data.id !== activeId) return;
    if (data.status === "running") {
      clearTimeout(timeout);
      timeout = setTimeout(onTimeout, 5000);
      status.textContent = "Checking and rendering…";
      return;
    }
    clearTimeout(timeout);
    activeId = 0;
    if (pendingSource !== undefined) {
      const next = pendingSource;
      pendingSource = undefined;
      run(next);
    } else {
      showResult(data.result);
    }
  });
  worker.addEventListener("error", () => {
    clearTimeout(timeout);
    activeId = 0;
    showResult({ error: "The browser could not start the Ruby worker." });
    resetWorker();
  });
}

function onTimeout() {
  activeId = 0;
  resetWorker();
  const next = pendingSource;
  pendingSource = undefined;
  if (next !== undefined) run(next);
  else showResult({ error: "The circuit took too long to run. Check for an infinite loop and try again." });
}

function run(text = source.value) {
  if (activeId) {
    pendingSource = text;
    return;
  }
  activeId = Date.now();
  status.textContent = "Preparing the Ruby runtime…";
  timeout = setTimeout(onTimeout, 30000);
  worker.postMessage({ id: activeId, source: text });
}

runButton.addEventListener("click", () => {
  clearTimeout(debounce);
  run();
});
source.addEventListener("input", () => {
  clearTimeout(debounce);
  debounce = setTimeout(() => run(), 700);
});
resetWorker();
run();
