/** @format */

import js from "@eslint/js";
import globals from "globals";
import tseslint from "typescript-eslint";
import react from "eslint-plugin-react";
import markdown from "@eslint/markdown";
import css from "@eslint/css";
import { defineConfig } from "eslint/config";

export default defineConfig([
	// Base JS
	js.configs.recommended,

	// TypeScript
	...tseslint.configs.recommended,

	// React
	{
		files: ["**/*.{jsx,tsx}"],
		plugins: {
			react,
		},
		rules: {
			...react.configs.recommended.rules,
			"react/react-in-jsx-scope": "off",
		},
		settings: {
			react: {
				version: "detect",
			},
		},
	},

	// Browser globals
	{
		files: ["**/*.{js,mjs,cjs,ts,mts,cts,jsx,tsx}"],
		languageOptions: {
			globals: globals.browser,
		},
	},

	// Markdown
	{
		files: ["**/*.md"],
		plugins: {
			markdown,
		},
		processor: "markdown/markdown",
	},

	// CSS
	{
		files: ["**/*.css"],
		plugins: {
			css,
		},
		rules: {
			...css.configs.recommended.rules,
		},
	},
	{
		rules: {
			"@typescript-eslint/no-explicit-any": "off",
		},
	},
]);
