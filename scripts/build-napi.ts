import { cpSync, existsSync, mkdirSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolveCargoCommand, runCommand } from "./command-utils.ts";
import { normalizeElectronArch, type ElectronArch } from "./electron-arch.ts";
import { syncQuadrantNodePackage } from "./sync-quadrant-node-package.ts";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(scriptDir, "..");
const srcTauriDir = path.join(rootDir, "src-tauri");
const args = process.argv.slice(2);
const release = args.includes("--release");
const profile = release ? "release" : "debug";

function getArgValue(flag: string): string | undefined {
  const exactMatch = args.find((arg) => arg.startsWith(`${flag}=`));
  if (exactMatch) {
    return exactMatch.slice(flag.length + 1);
  }

  const flagIndex = args.indexOf(flag);
  if (flagIndex >= 0) {
    return args[flagIndex + 1];
  }

  return undefined;
}

function normalizePlatform(platform: string | undefined): string {
  if (!platform) {
    return process.platform;
  }

  switch (platform) {
    case "windows":
      return "win32";
    case "mac":
    case "macos":
      return "darwin";
    default:
      return platform;
  }
}

function getRustTargetTriple(platform: string, arch: ElectronArch): string {
  const key = `${platform}-${arch}`;
  switch (key) {
    case "win32-x64":
      return "x86_64-pc-windows-msvc";
    case "win32-arm64":
      return "aarch64-pc-windows-msvc";
    case "linux-x64":
      return "x86_64-unknown-linux-gnu";
    case "linux-arm64":
      return "aarch64-unknown-linux-gnu";
    case "darwin-x64":
      return "x86_64-apple-darwin";
    case "darwin-arm64":
      return "aarch64-apple-darwin";
    default:
      throw new Error(
        `Unsupported Electron native build target: platform=${platform} arch=${arch}`,
      );
  }
}

function findNativeBinary(directory: string): string | null {
  const entries = readdirSync(directory, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      const found = findNativeBinary(fullPath);
      if (found) {
        return found;
      }
      continue;
    }
    if (
      entry.isFile() &&
      entry.name.toLowerCase().includes("quadrant_napi") &&
      (entry.name.endsWith(".node") ||
        entry.name.endsWith(".dll") ||
        entry.name.endsWith(".so") ||
        entry.name.endsWith(".dylib"))
    ) {
      return fullPath;
    }
  }
  return null;
}

const targetPlatform = normalizePlatform(
  getArgValue("--platform") ?? getArgValue("--os"),
);
const targetArch = normalizeElectronArch(getArgValue("--arch"));
const rustTarget =
  getArgValue("--target") ?? getRustTargetTriple(targetPlatform, targetArch);
const cargoCommand = resolveCargoCommand();

syncQuadrantNodePackage();

runCommand(
  cargoCommand,
  [
    "build",
    "--manifest-path",
    path.join("src-tauri", "Cargo.toml"),
    "-p",
    "quadrant-napi",
    "--target",
    rustTarget,
    ...(release ? ["--release"] : []),
  ],
  {
    cwd: rootDir,
    stdio: "inherit",
    shell: process.platform === "win32",
    notFoundMessage:
      "Rust is required to build the Electron native addon, but `cargo` was not found. Install Rust and ensure `cargo` is on PATH, or set `CARGO=/absolute/path/to/cargo` before running `bun run dev:electron`.",
  },
);

const targetDir = path.join(srcTauriDir, "target", rustTarget, profile);
const builtNode = findNativeBinary(targetDir);

if (!builtNode || !existsSync(builtNode)) {
  throw new Error(`Could not find built N-API binary under ${targetDir}`);
}

const nativeDir = path.join(rootDir, "packages", "quadrant-node", "native");
mkdirSync(nativeDir, { recursive: true });
cpSync(
  path.join(srcTauriDir, "crates", "quadrant-napi", "index.js"),
  path.join(nativeDir, "index.js"),
);
const targetNativeDir = path.join(nativeDir, `${targetPlatform}-${targetArch}`);
mkdirSync(targetNativeDir, { recursive: true });
try {
  cpSync(builtNode, path.join(targetNativeDir, "index.node"));
  cpSync(builtNode, path.join(nativeDir, "index.node"));
} catch (error) {
  if (
    error instanceof Error &&
    "code" in error &&
    (error.code === "EIO" || error.code === "EPERM" || error.code === "EBUSY")
  ) {
    throw new Error(
      `Built Quadrant N-API successfully, but could not update packages/quadrant-node/native/index.node because it is locked. Close Electron or any process using the addon, then rerun \`bun scripts/build-napi.ts\`. Original error: ${error.message}`,
    );
  }
  throw error;
}

console.log(
  `Copied ${builtNode} to ${path.join(targetNativeDir, "index.node")} and ${path.join(nativeDir, "index.node")}`,
);
