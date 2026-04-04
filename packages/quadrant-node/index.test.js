import test from "node:test";
import assert from "node:assert/strict";

import { createQuadrantClient } from "./index.js";

test("createQuadrantClient maps events and invoke-style methods", async () => {
  const seen = [];
  const fakeNative = {
    QuadrantHostAddon: class {
      constructor() {
        fakeNative.instance = this;
      }

      on_event(callback) {
        this.callback = callback;
      }

      invoke(command, payload) {
        return Promise.resolve({ command, payload });
      }

      get_modpacks(hideFree) {
        return Promise.resolve([{ name: "demo", hideFree }]);
      }

      get_account_info() {
        return Promise.resolve({ login: "demo" });
      }

      get_news() {
        return Promise.resolve([{ title: "hello" }]);
      }

      install_mod() {
        return Promise.resolve();
      }

      sync_modpack() {
        return Promise.resolve();
      }

      start_background_workers() {
        return Promise.resolve();
      }

      stop_background_workers() {
        return Promise.resolve();
      }

      shutdown() {
        return Promise.resolve();
      }

      init_config() {
        return Promise.resolve();
      }

      get_minecraft_folder() {
        return Promise.resolve("C:/demo/.minecraft");
      }
    },
  };

  const client = createQuadrantClient(
    {
      dataDir: "C:/quadrant",
      oauthClientId: "client",
      oauthClientSecret: "secret",
      quadrantApiKey: "api-key",
    },
    fakeNative,
  );

  const dispose = client.on("refreshNotifications", (payload) => {
    seen.push(payload);
  });

  fakeNative.instance.callback?.(
    JSON.stringify({
      event: "refreshNotifications",
      payload: [{ notification_id: "n1" }],
    }),
  );

  const invokeResult = await client.invoke("get_modpacks", { hideFree: true });
  const modpacks = await client.getModpacks(true);

  assert.deepEqual(invokeResult, {
    command: "get_modpacks",
    payload: { hideFree: true },
  });
  assert.equal(modpacks[0].name, "demo");
  assert.deepEqual(seen, [[{ notification_id: "n1" }]]);
  dispose();
});
