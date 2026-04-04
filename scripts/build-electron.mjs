/** @format */

import { spawnSync } from "node:child_process";
import path from "node:path";

const rootDir = path.resolve(import.meta.dirname, "..");

function run(command, args) {
	const result = spawnSync(command, args, {
		cwd: rootDir,
		stdio: "inherit",
		shell: process.platform === "win32",
	});

	if (result.status !== 0) {
		process.exit(result.status ?? 1);
	}
}

run("node", ["scripts/write-electron-runtime-config.mjs"]);
run("bun", ["run", "build"]);
run("node", ["scripts/build-napi.mjs", "--release"]);
