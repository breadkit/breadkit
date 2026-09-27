import { DefaultRubyVM } from "https://cdn.jsdelivr.net/npm/@ruby/wasm-wasi@2.10.1/dist/browser/+esm";

let runtime;

async function loadRuntime() {
  const [wasmResponse, bundleResponse] = await Promise.all([
    fetch("https://cdn.jsdelivr.net/npm/@ruby/4.0-wasm-wasi@2.10.1/dist/ruby+stdlib.wasm"),
    fetch(new URL("bundle.json", import.meta.url))
  ]);
  if (!wasmResponse.ok || !bundleResponse.ok) throw new Error("Ruby or circuit libraries could not be downloaded.");

  const [binary, bundle] = await Promise.all([wasmResponse.arrayBuffer(), bundleResponse.json()]);
  if (bundle.schema_version !== 1 || !bundle.files) throw new Error("The Playground library bundle is invalid.");
  const { vm } = await DefaultRubyVM(await WebAssembly.compile(binary), { consolePrint: false });
  vm.eval("require 'fileutils'");
  const folders = [...new Set(Object.keys(bundle.files).map(file => file.slice(0, file.lastIndexOf("/"))))].sort();
  for (const folder of folders) vm.eval(`FileUtils.mkdir_p(${JSON.stringify(folder)})`);
  for (const [file, encoded] of Object.entries(bundle.files)) {
    vm.eval(`File.write(${JSON.stringify(file)}, '${encoded}'.unpack1('m0'))`);
  }
  vm.eval("$LOAD_PATH.unshift('/matrix/lib', '/core/lib', '/lint/lib', '/render/lib'); require 'breadkit'; require 'breadkit/lint'; require 'breadkit/render'");
  return vm;
}

function encode(text) {
  const bytes = new TextEncoder().encode(text);
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 8192) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  }
  return btoa(binary);
}

function evaluate(vm, source) {
  const encoded = encode(source);
  const ruby = `
    begin
      source = '${encoded}'.unpack1('m0').force_encoding('UTF-8')
      builder = Breadkit::DSL::Builder.new
      builder.instance_eval(source, 'playground.bk.rb', 1)
      circuit = Breadkit::Resolver.new.call(builder.document)
      diagnostics = circuit.diagnostics.map do |item|
        { code: item.code, severity: item.severity, message: item.message, line: item.location&.line }
      end
      if diagnostics.any? { |item| item[:severity] == 'error' }
        JSON.generate({ diagnostics: diagnostics, offenses: [], nets: [], svg: nil })
      else
        File.write('/playground.json', JSON.generate(circuit.to_ir))
        lint = Breadkit::Lint::Engine.new.run(['/playground.json']).first
        offenses = lint[:offenses].map do |item|
          { rule: item.rule, severity: item.severity, message: item.message, line: item.location&.line }
        end
        svg = Breadkit::Render::SvgRenderer.new.render(circuit, theme: 'dark')
        JSON.generate({ diagnostics: diagnostics, offenses: offenses,
                        nets: circuit.nets.map { |net| { name: net.name, members: net.members.length } }, svg: svg })
      end
    rescue Exception => error
      JSON.generate({ error: "#{error.class}: #{error.message}" })
    end
  `;
  return JSON.parse(vm.eval(ruby).toString());
}

self.addEventListener("message", async event => {
  const { id, source } = event.data;
  try {
    runtime ||= loadRuntime();
    const vm = await runtime;
    self.postMessage({ id, status: "running" });
    self.postMessage({ id, result: evaluate(vm, source) });
  } catch (error) {
    runtime = undefined;
    self.postMessage({ id, result: { error: error.message || String(error) } });
  }
});
