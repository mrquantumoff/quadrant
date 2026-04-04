import { spawn } from "node:child_process";
import http from "node:http";
import path from "node:path";

const rootDir = path.resolve(import.meta.dirname, "..");
const devUrl = "http://127.0.0.1:1420";

function spawnProcess(command, args, extraEnv = {}) {
  return spawn(command, args, {
    cwd: rootDir,
    stdio: "inherit",
    shell: process.platform === "win32",
    env: {
      ...process.env,
      ...extraEnv,
    },
  });
}

function waitForChildProcess(childProcess, label) {
  return new Promise((resolve, reject) => {
    childProcess.on("error", (error) => {
      reject(new Error(`Failed to start ${label}: ${error.message}`));
    });
    childProcess.on("exit", (code, signal) => {
      if (code === 0) {
        resolve(undefined);
        return;
      }
      if (signal) {
        reject(new Error(`${label} terminated with signal ${signal}`));
        return;
      }
      process.exit(code ?? 1);
    });
  });
}

async function waitForUrl(url, timeoutMs = 120000) {
  const startedAt = Date.now();

  while (Date.now() - startedAt < timeoutMs) {
    const isReady = await new Promise((resolve) => {
      const request = http.get(url, (response) => {
        response.resume();
        resolve(response.statusCode !== undefined && response.statusCode < 500);
      });
      request.on("error", () => resolve(false));
      request.setTimeout(2000, () => {
        request.destroy();
        resolve(false);
      });
    });

    if (isReady) {
      return;
    }

    await new Promise((resolve) => setTimeout(resolve, 1000));
  }

  throw new Error(`Timed out waiting for ${url}`);
}

const prepareConfig = spawnProcess("node", [
  "scripts/write-electron-runtime-config.mjs",
]);
await waitForChildProcess(
  prepareConfig,
  "scripts/write-electron-runtime-config.mjs",
);

const napiBuild = spawnProcess("node", ["scripts/build-napi.mjs"]);
await waitForChildProcess(napiBuild, "scripts/build-napi.mjs");

const viteProcess = spawnProcess("bun", [
  "run",
  "dev",
  "--",
  "--host",
  "127.0.0.1",
]);

const cleanup = () => {
  viteProcess.kill();
};

process.on("SIGINT", cleanup);
process.on("SIGTERM", cleanup);

await waitForUrl(devUrl);

const electronProcess = spawnProcess(
  "bunx",
  ["electron", "electron/main.mjs"],
  {
    QUADRANT_ELECTRON_DEV_SERVER_URL: devUrl,
  },
);

electronProcess.on("exit", (code) => {
  cleanup();
  process.exit(code ?? 0);
});
