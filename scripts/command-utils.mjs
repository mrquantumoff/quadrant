import { existsSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

function formatCommand(command, args) {
  return [command, ...args].join(" ");
}

export function resolveCargoCommand() {
  if (process.env.CARGO?.trim()) {
    return process.env.CARGO.trim();
  }

  const rustupCargo = path.join(
    homedir(),
    ".cargo",
    "bin",
    process.platform === "win32" ? "cargo.exe" : "cargo",
  );
  if (existsSync(rustupCargo)) {
    return rustupCargo;
  }

  return "cargo";
}

export function runCommand(command, args, options = {}) {
  const { notFoundMessage, ...spawnOptions } = options;
  const result = spawnSync(command, args, spawnOptions);

  if (result.error) {
    if (result.error.code === "ENOENT") {
      throw new Error(
        notFoundMessage ??
          `Failed to run \`${formatCommand(command, args)}\`: command not found.`,
      );
    }

    throw new Error(
      `Failed to run \`${formatCommand(command, args)}\`: ${result.error.message}`,
    );
  }

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }

  return result;
}
