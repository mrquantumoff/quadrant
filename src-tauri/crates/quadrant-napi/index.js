/**
 * eslint-disable @typescript-eslint/no-require-imports
 *
 * @format
 */

/** @format */

const candidates = [
	process.env.QUADRANT_NAPI_BINDING,
	"./index.node",
	"./quadrant-napi.node",
	"./quadrant_napi.node",
].filter(Boolean);

let loaded;
let lastError;

for (const candidate of candidates) {
	try {
		loaded = require(candidate);
		break;
	} catch (error) {
		lastError = error;
	}
}

if (!loaded) {
	throw new Error(
		`Failed to load Quadrant N-API binding. Set QUADRANT_NAPI_BINDING to the built addon path. Last error: ${lastError}`,
	);
}

export default loaded;
