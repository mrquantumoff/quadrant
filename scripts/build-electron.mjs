/** @format */

import path from "node:path";
import { runCommand } from "./command-utils.mjs";

const rootDir = path.resolve(import.meta.dirname, "..");
const extraArgs = process.argv.slice(2);

function run(command, args) {
	runCommand(command, args, {
		cwd: rootDir,
		stdio: "inherit",
		shell: process.platform === "win32",
	});
}

run("node", ["scripts/write-electron-runtime-config.mjs"]);
run("bun", ["run", "build"]);
run("node", ["scripts/build-napi.mjs", "--release", ...extraArgs]);
