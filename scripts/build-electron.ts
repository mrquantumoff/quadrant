/** @format */

import path from "node:path";
import { fileURLToPath } from "node:url";
import { runCommand } from "./command-utils.ts";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(scriptDir, "..");
const extraArgs = process.argv.slice(2);

function run(command: string, args: string[]): void {
  runCommand(command, args, {
    cwd: rootDir,
    stdio: "inherit",
    shell: process.platform === "win32",
  });
}

run("bun", ["run", "build"]);
run("bun", ["scripts/build-napi.ts", "--release", ...extraArgs]);
run("bun", ["run", "build:electron-shell"]);
run("bun", ["scripts/write-electron-runtime-config.ts"]);
