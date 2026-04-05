import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(scriptDir, "..");
const sourceDir = path.join(rootDir, "scripts", "quadrant-node");
const targetDir = path.join(rootDir, "packages", "quadrant-node");

function readUtf8(filePath: string): string {
  return readFileSync(filePath, "utf8");
}

function writeIfChanged(filePath: string, contents: string): boolean {
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

export function syncQuadrantNodePackage(): {
  indexJs: boolean;
  indexTypes: boolean;
} {
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
