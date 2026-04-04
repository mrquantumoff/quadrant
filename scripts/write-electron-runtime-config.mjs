import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";

const rootDir = path.resolve(import.meta.dirname, "..");
const outputPath = path.join(
  rootDir,
  "electron",
  "runtime-config.generated.json",
);

const config = {
  oauthClientId: process.env.QUADRANT_OAUTH2_CLIENT_ID ?? "",
  oauthClientSecret: process.env.QUADRANT_OAUTH2_CLIENT_SECRET ?? "",
  quadrantApiKey: process.env.QUADRANT_API_KEY ?? "",
  apiBaseUrl: process.env.QUADRANT_API_BASE_URL ?? "",
};

mkdirSync(path.dirname(outputPath), { recursive: true });
writeFileSync(outputPath, JSON.stringify(config, null, 2));

console.log(`Wrote Electron runtime config to ${outputPath}`);
