/** @format */

import { AccountInfo } from "./intefaces";
import { getAccountInfo } from "./tools";
import { isSignedOutError } from "./errors";

/**
 * What the app knows about the Quadrant ID session. `unreachable` keeps the
 * session: the server could not be asked, so the user is not signed out.
 */
export type AccountState =
  | { status: "loading" }
  | { status: "signedOut" }
  | { status: "unreachable"; error: unknown }
  | { status: "signedIn"; info: AccountInfo };

export async function readAccountState(): Promise<AccountState> {
  try {
    return { status: "signedIn", info: await getAccountInfo() };
  } catch (error) {
    console.error("Failed to get account info", error);
    return isSignedOutError(error)
      ? { status: "signedOut" }
      : { status: "unreachable", error };
  }
}
