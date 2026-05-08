import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(scriptDir, "..");
const outputPath = path.join(
  rootDir,
  "dist-electron-shell",
  "runtime-config.generated.json",
);

function normalizeOptionalConfigValue(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeRequiredConfigValue(value: unknown): string {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim();
}

const config = {
  oauthClientId: normalizeRequiredConfigValue(
    process.env.QUADRANT_OAUTH2_CLIENT_ID,
  ),
  oauthClientSecret: normalizeRequiredConfigValue(
    process.env.QUADRANT_OAUTH2_CLIENT_SECRET,
  ),
  quadrantApiKey: normalizeRequiredConfigValue(process.env.QUADRANT_API_KEY),
  apiBaseUrl: normalizeOptionalConfigValue(process.env.QUADRANT_API_BASE_URL),
};

mkdirSync(path.dirname(outputPath), { recursive: true });
writeFileSync(outputPath, JSON.stringify(config, null, 2));

console.log(`Wrote Electron runtime config to ${outputPath}`);
