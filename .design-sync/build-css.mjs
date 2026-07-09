/**
 * design-sync: compile Quadrant's Tailwind v4 stylesheet.
 *
 * The app styles with Tailwind v4 (`@import "tailwindcss"` in src/App.css) plus
 * a handful of custom classes (.input, .center, …) and an Inter @font-face.
 * The design-sync converter can't run Tailwind, so we precompile the global
 * stylesheet here with the repo's OWN toolchain (@tailwindcss/postcss) and point
 * cfg.cssEntry at the result. Re-run this before every (re)build.
 *
 *   node .design-sync/build-css.mjs
 *
 * Output: .design-sync/quadrant-compiled.css  (+ Inter-Font.ttf copied alongside)
 */
import { readFileSync, writeFileSync, copyFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { createRequire } from "node:module";

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, "..");
const require = createRequire(resolve(repo, "package.json"));

const postcss = require("postcss");
const tailwind = require("@tailwindcss/postcss");

const inputPath = resolve(repo, "src/App.css");
const css = readFileSync(inputPath, "utf8");

const result = await postcss([tailwind()]).process(css, { from: inputPath });

// The app serves fonts from web root ("/Inter-Font.ttf"); make it local to the
// stylesheet so the converter resolves + ships it into fonts/.
copyFileSync(resolve(repo, "public/Inter-Font.ttf"), resolve(here, "Inter-Font.ttf"));
const out = result.css.replaceAll('url("/Inter-Font.ttf")', 'url("./Inter-Font.ttf")');

const outPath = resolve(here, "quadrant-compiled.css");
writeFileSync(outPath, out);
console.error(`compiled ${(out.length / 1024).toFixed(0)} KB → ${outPath}`);
