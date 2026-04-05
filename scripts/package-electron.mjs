import path from "node:path";
import { runCommand } from "./command-utils.mjs";

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

function hasPublishFlag(args) {
  return args.some(
    (arg) => arg === "--publish" || arg.startsWith("--publish="),
  );
}

function run(command, args) {
  runCommand(command, args, {
    cwd: rootDir,
    stdio: "inherit",
    shell: process.platform === "win32",
  });
}

const targetArch = normalizeArch(getArgValue("--arch"));
const electronBuilderArchFlag = `--${targetArch}`;
const publishArgs = hasPublishFlag(extraArgs) ? [] : ["--publish", "never"];

run("node", ["scripts/build-electron.mjs", ...extraArgs]);
run("bunx", [
  "electron-builder",
  "--config",
  "electron-builder.json",
  electronBuilderArchFlag,
  ...publishArgs,
]);
