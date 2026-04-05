import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(import.meta.dirname, "..");
const sourceDir = path.join(rootDir, "scripts", "quadrant-node");
const targetDir = path.join(rootDir, "packages", "quadrant-node");

function readUtf8(filePath) {
  return readFileSync(filePath, "utf8");
}

function writeIfChanged(filePath, contents) {
  try {
    if (readUtf8(filePath) === contents) {
      return false;
    }
  } catch {
    // Fall through and create the file when it does not exist yet.
  }

  writeFileSync(filePath, contents);
  return true;
}

export function syncQuadrantNodePackage() {
  mkdirSync(targetDir, { recursive: true });

  return {
    indexJs: writeIfChanged(
      path.join(targetDir, "index.js"),
      readUtf8(path.join(sourceDir, "index.js")),
    ),
    indexTypes: writeIfChanged(
      path.join(targetDir, "index.d.ts"),
      readUtf8(path.join(sourceDir, "index.d.ts")),
    ),
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  syncQuadrantNodePackage();
}
