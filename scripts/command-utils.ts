/** @format */

import { spawnSync, type SpawnSyncOptions } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

export interface RunCommandOptions extends SpawnSyncOptions {
  notFoundMessage?: string;
}

function formatCommand(command: string, args: readonly string[]): string {
  return [command, ...args].join(" ");
}

export function resolveCargoCommand(): string {
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

export function runCommand(
  command: string,
  args: string[],
  options: RunCommandOptions = {},
): ReturnType<typeof spawnSync> {
  const { notFoundMessage, ...spawnOptions } = options;
  const result = spawnSync(command, args, spawnOptions);

  if (result.error) {
    const error = result.error as NodeJS.ErrnoException;
    if (error.code === "ENOENT") {
      throw new Error(
        notFoundMessage ??
          `Failed to run \`${formatCommand(command, args)}\`: command not found.`,
      );
    }

    throw new Error(
      `Failed to run \`${formatCommand(command, args)}\`: ${error.message}`,
    );
  }

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }

  return result;
}
