import { cpSync, existsSync, mkdirSync, readdirSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(import.meta.dirname, "..");
const srcTauriDir = path.join(rootDir, "src-tauri");
const release = process.argv.includes("--release");
const profile = release ? "release" : "debug";

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: rootDir,
    stdio: "inherit",
    shell: process.platform === "win32",
    ...options,
  });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function findNativeBinary(directory) {
  const entries = readdirSync(directory, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      const found = findNativeBinary(fullPath);
      if (found) {
        return found;
      }
      continue;
    }
    if (
      entry.isFile() &&
      entry.name.toLowerCase().includes("quadrant_napi") &&
      (entry.name.endsWith(".node") ||
        entry.name.endsWith(".dll") ||
        entry.name.endsWith(".so") ||
        entry.name.endsWith(".dylib"))
    ) {
      return fullPath;
    }
  }
  return null;
}

run("cargo", [
  "build",
  "--manifest-path",
  path.join("src-tauri", "Cargo.toml"),
  "-p",
  "quadrant-napi",
  ...(release ? ["--release"] : []),
]);

const targetDir = path.join(srcTauriDir, "target", profile);
const builtNode = findNativeBinary(targetDir);

if (!builtNode || !existsSync(builtNode)) {
  throw new Error(`Could not find built N-API binary under ${targetDir}`);
}

const nativeDir = path.join(rootDir, "packages", "quadrant-node", "native");
mkdirSync(nativeDir, { recursive: true });
cpSync(path.join(srcTauriDir, "crates", "quadrant-napi", "index.js"), path.join(nativeDir, "index.js"));
cpSync(builtNode, path.join(nativeDir, "index.node"));

console.log(`Copied ${builtNode} to ${path.join(nativeDir, "index.node")}`);
