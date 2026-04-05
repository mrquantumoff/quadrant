import { spawn, type ChildProcess } from "node:child_process";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import chokidar, { type FSWatcher } from "chokidar";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(scriptDir, "..");
const devUrl = "http://127.0.0.1:1420";
const electronWatchGlobs = [
  "electron/**/*.ts",
  "package.json",
  "electron-builder.json",
  "tsconfig.electron.json",
  "tsconfig.scripts.json",
  "scripts/build-napi.ts",
  "scripts/build-electron.ts",
  "scripts/command-utils.ts",
  "scripts/dev-electron.ts",
  "scripts/package-electron.ts",
  "scripts/sync-quadrant-node-package.ts",
  "scripts/quadrant-node/**/*",
  "scripts/write-electron-runtime-config.ts",
  "src-tauri/Cargo.toml",
  "src-tauri/Cargo.lock",
  "src-tauri/crates/quadrant-napi/**/*",
];
const ignoredWatchGlobs = [
  "**/.DS_Store",
  "**/node_modules/**",
  "dist-electron-shell/runtime-config.generated.json",
  "packages/quadrant-node/native/**",
  "src-tauri/target/**",
];

let isShuttingDown = false;
let isRestartingElectron = false;
let electronRestartQueued = false;
let electronRestartTimer: ReturnType<typeof setTimeout> | null = null;
let electronProcess: ChildProcess | null = null;

function spawnProcess(
  command: string,
  args: string[],
  extraEnv: NodeJS.ProcessEnv = {},
): ChildProcess {
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

function waitForChildProcess(
  childProcess: ChildProcess,
  label: string,
): Promise<void> {
  return new Promise((resolve, reject) => {
    childProcess.on("error", (error) => {
      reject(new Error(`Failed to start ${label}: ${error.message}`));
    });
    childProcess.on("exit", (code, signal) => {
      if (code === 0) {
        resolve();
        return;
      }
      if (signal) {
        reject(new Error(`${label} terminated with signal ${signal}`));
        return;
      }
      reject(new Error(`${label} exited with code ${code ?? 1}`));
    });
  });
}

async function waitForUrl(url: string, timeoutMs = 120_000): Promise<void> {
  const startedAt = Date.now();

  while (Date.now() - startedAt < timeoutMs) {
    const isReady = await new Promise<boolean>((resolve) => {
      const request = http.get(url, (response) => {
        response.resume();
        resolve(response.statusCode !== undefined && response.statusCode < 500);
      });
      request.on("error", () => resolve(false));
      request.setTimeout(2_000, () => {
        request.destroy();
        resolve(false);
      });
    });

    if (isReady) {
      return;
    }

    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }

  throw new Error(`Timed out waiting for ${url}`);
}

async function runPrepareStep(
  command: string,
  args: string[],
  label: string,
): Promise<void> {
  const childProcess = spawnProcess(command, args);
  await waitForChildProcess(childProcess, label);
}

async function runElectronPrepareSteps(): Promise<void> {
  await runPrepareStep("bun", ["run", "build:electron-shell"], "build:electron-shell");
  await runPrepareStep(
    "bun",
    ["scripts/write-electron-runtime-config.ts"],
    "scripts/write-electron-runtime-config.ts",
  );
  await runPrepareStep(
    "bun",
    ["scripts/build-napi.ts"],
    "scripts/build-napi.ts",
  );
}

function launchElectron(): void {
  const nextElectronProcess = spawnProcess(
    "bunx",
    ["electron", "dist-electron-shell/main.js"],
    {
      QUADRANT_ELECTRON_DEV_SERVER_URL: devUrl,
    },
  );

  electronProcess = nextElectronProcess;
  nextElectronProcess.on("exit", (code, signal) => {
    if (electronProcess !== nextElectronProcess) {
      return;
    }

    electronProcess = null;

    if (isShuttingDown || isRestartingElectron) {
      return;
    }

    if (signal) {
      console.error(`Electron exited with signal ${signal}`);
      process.exit(1);
      return;
    }

    process.exit(code ?? 0);
  });
}

async function stopElectronProcess(): Promise<void> {
  if (!electronProcess || electronProcess.exitCode !== null) {
    electronProcess = null;
    return;
  }

  const runningElectronProcess = electronProcess;

  await new Promise<void>((resolve) => {
    let resolved = false;

    const finalize = () => {
      if (resolved) {
        return;
      }
      resolved = true;
      clearTimeout(forceKillTimeout);
      resolve();
    };

    const forceKillTimeout = setTimeout(() => {
      if (!runningElectronProcess.killed) {
        runningElectronProcess.kill("SIGKILL");
      }
    }, 10_000);

    runningElectronProcess.once("exit", finalize);
    runningElectronProcess.kill("SIGTERM");
  });

  if (electronProcess === runningElectronProcess) {
    electronProcess = null;
  }
}

async function restartElectron(reason: string): Promise<void> {
  if (isShuttingDown) {
    return;
  }

  if (isRestartingElectron) {
    electronRestartQueued = true;
    return;
  }

  isRestartingElectron = true;

  do {
    electronRestartQueued = false;
    console.log(`[dev:electron] Restarting Electron (${reason})`);

    try {
      await stopElectronProcess();
      await runElectronPrepareSteps();
      if (!isShuttingDown) {
        launchElectron();
      }
    } catch (error) {
      const message =
        error instanceof Error ? error.message : `Unknown error: ${String(error)}`;
      console.error(`[dev:electron] Failed to restart Electron: ${message}`);
    }
  } while (electronRestartQueued && !isShuttingDown);

  isRestartingElectron = false;
}

function scheduleElectronRestart(reason: string): void {
  if (isShuttingDown) {
    return;
  }

  if (electronRestartTimer) {
    clearTimeout(electronRestartTimer);
  }

  electronRestartTimer = setTimeout(() => {
    electronRestartTimer = null;
    restartElectron(reason).catch((error) => {
      const message =
        error instanceof Error ? error.message : `Unknown error: ${String(error)}`;
      console.error(`[dev:electron] Unexpected restart failure: ${message}`);
    });
  }, 250);
}

const viteProcess = spawnProcess("bun", [
  "run",
  "dev",
  "--",
  "--host",
  "127.0.0.1",
]);

const electronWatcher: FSWatcher = chokidar.watch(electronWatchGlobs, {
  cwd: rootDir,
  ignoreInitial: true,
  ignored: ignoredWatchGlobs,
});

electronWatcher.on("all", (eventName, filePath) => {
  scheduleElectronRestart(`${eventName} ${filePath}`);
});

const cleanup = async (): Promise<void> => {
  if (isShuttingDown) {
    return;
  }

  isShuttingDown = true;

  if (electronRestartTimer) {
    clearTimeout(electronRestartTimer);
    electronRestartTimer = null;
  }

  await Promise.allSettled([electronWatcher.close(), stopElectronProcess()]);

  if (viteProcess.exitCode === null) {
    viteProcess.kill("SIGTERM");
  }
};

process.on("SIGINT", () => {
  cleanup().finally(() => process.exit(0));
});

process.on("SIGTERM", () => {
  cleanup().finally(() => process.exit(0));
});

viteProcess.on("exit", async (code, signal) => {
  if (isShuttingDown) {
    return;
  }

  await cleanup();

  if (signal) {
    console.error(`Vite dev server terminated with signal ${signal}`);
    process.exit(1);
    return;
  }

  process.exit(code ?? 0);
});

try {
  await runElectronPrepareSteps();
  await waitForUrl(devUrl);
  launchElectron();
} catch (error) {
  await cleanup();
  throw error;
}
