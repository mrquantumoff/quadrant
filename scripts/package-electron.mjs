import { spawnSync } from "node:child_process";
import path from "node:path";

const rootDir = path.resolve(import.meta.dirname, "..");
const extraArgs = process.argv.slice(2);

function getArgValue(flag) {
  const exactMatch = extraArgs.find((arg) => arg.startsWith(`${flag}=`));
  if (exactMatch) {
    return exactMatch.slice(flag.length + 1);
  }

  const flagIndex = extraArgs.indexOf(flag);
  if (flagIndex >= 0) {
    return extraArgs[flagIndex + 1];
  }

  return undefined;
}

function normalizeArch(arch) {
  if (!arch) {
    return process.arch;
  }

  switch (arch) {
    case "aarch64":
      return "arm64";
    case "amd64":
      return "x64";
    default:
      return arch;
  }
}

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

const targetArch = normalizeArch(getArgValue("--arch"));
const electronBuilderArchFlag = `--${targetArch}`;

run("node", ["scripts/build-electron.mjs", ...extraArgs]);
run("bunx", [
  "electron-builder",
  "--config",
  "electron-builder.json",
  electronBuilderArchFlag,
]);
