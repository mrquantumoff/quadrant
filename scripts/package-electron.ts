import path from "node:path";
import { fileURLToPath } from "node:url";
import { runCommand } from "./command-utils.ts";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(scriptDir, "..");
const extraArgs = process.argv.slice(2);

function getArgValue(flag: string): string | undefined {
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

function normalizeArch(arch: string | undefined): string {
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

function hasPublishFlag(args: string[]): boolean {
  return args.some(
    (arg) => arg === "--publish" || arg.startsWith("--publish="),
  );
}

function run(command: string, args: string[]): void {
  runCommand(command, args, {
    cwd: rootDir,
    stdio: "inherit",
    shell: process.platform === "win32",
  });
}

const targetArch = normalizeArch(getArgValue("--arch"));
const electronBuilderArchFlag = `--${targetArch}`;
const publishArgs = hasPublishFlag(extraArgs) ? [] : ["--publish", "never"];

run("bun", ["scripts/build-electron.ts", ...extraArgs]);
run("bunx", [
  "electron-builder",
  "--config",
  "electron-builder.json",
  electronBuilderArchFlag,
  ...publishArgs,
]);
