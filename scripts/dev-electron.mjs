import { spawn } from "node:child_process";
import http from "node:http";
import path from "node:path";
import chokidar from "chokidar";

const rootDir = path.resolve(import.meta.dirname, "..");
const devUrl = "http://127.0.0.1:1420";
const electronWatchGlobs = [
  "electron/**/*",
  "package.json",
  "packages/quadrant-node/**/*",
  "scripts/build-napi.mjs",
  "scripts/command-utils.mjs",
  "scripts/write-electron-runtime-config.mjs",
  "src-tauri/Cargo.toml",
  "src-tauri/Cargo.lock",
  "src-tauri/crates/quadrant-napi/**/*",
];
const ignoredWatchGlobs = [
  "**/.DS_Store",
  "**/node_modules/**",
  "electron/runtime-config.generated.json",
  "packages/quadrant-node/native/**",
  "src-tauri/target/**",
];

let isShuttingDown = false;
let isRestartingElectron = false;
let electronRestartQueued = false;
let electronRestartTimer = null;
let electronProcess = null;

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
      reject(new Error(`${label} exited with code ${code ?? 1}`));
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

async function runPrepareStep(command, args, label) {
  const childProcess = spawnProcess(command, args);
  await waitForChildProcess(childProcess, label);
}

async function runElectronPrepareSteps() {
  await runPrepareStep(
    "node",
    ["scripts/write-electron-runtime-config.mjs"],
    "scripts/write-electron-runtime-config.mjs",
  );
  await runPrepareStep(
    "node",
    ["scripts/build-napi.mjs"],
    "scripts/build-napi.mjs",
  );
}

function launchElectron() {
  const nextElectronProcess = spawnProcess(
    "bunx",
    ["electron", "electron/main.mjs"],
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

async function stopElectronProcess() {
  if (!electronProcess || electronProcess.exitCode !== null) {
    electronProcess = null;
    return;
  }

  const runningElectronProcess = electronProcess;

  await new Promise((resolve) => {
    let resolved = false;

    const finalize = () => {
      if (resolved) {
        return;
      }
      resolved = true;
      clearTimeout(forceKillTimeout);
      resolve(undefined);
    };

    const forceKillTimeout = setTimeout(() => {
      if (!runningElectronProcess.killed) {
        runningElectronProcess.kill("SIGKILL");
      }
    }, 10000);

    runningElectronProcess.once("exit", finalize);
    runningElectronProcess.kill("SIGTERM");
  });

  if (electronProcess === runningElectronProcess) {
    electronProcess = null;
  }
}

async function restartElectron(reason) {
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
      console.error(
        `[dev:electron] Failed to restart Electron: ${error.message}`,
      );
    }
  } while (electronRestartQueued && !isShuttingDown);

  isRestartingElectron = false;
}

function scheduleElectronRestart(reason) {
  if (isShuttingDown) {
    return;
  }

  if (electronRestartTimer) {
    clearTimeout(electronRestartTimer);
  }

  electronRestartTimer = setTimeout(() => {
    electronRestartTimer = null;
    restartElectron(reason).catch((error) => {
      console.error(
        `[dev:electron] Unexpected restart failure: ${error.message}`,
      );
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

const electronWatcher = chokidar.watch(electronWatchGlobs, {
  cwd: rootDir,
  ignoreInitial: true,
  ignored: ignoredWatchGlobs,
});

electronWatcher.on("all", (eventName, filePath) => {
  scheduleElectronRestart(`${eventName} ${filePath}`);
});

const cleanup = async () => {
  if (isShuttingDown) {
    return;
  }

  isShuttingDown = true;

  if (electronRestartTimer) {
    clearTimeout(electronRestartTimer);
    electronRestartTimer = null;
  }

  await Promise.allSettled([
    electronWatcher.close(),
    stopElectronProcess(),
  ]);

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
