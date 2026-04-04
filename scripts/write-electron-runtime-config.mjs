import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";

const rootDir = path.resolve(import.meta.dirname, "..");
const outputPath = path.join(
  rootDir,
  "electron",
  "runtime-config.generated.json",
);

function normalizeOptionalConfigValue(value) {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeRequiredConfigValue(value) {
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
