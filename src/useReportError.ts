/** @format */

import { useContext } from "react";
import { useTranslation } from "react-i18next";
import { describeError } from "./errors";
import { ContentContext } from "./intefaces";

/** Logs a caught error and shows its translated message in the snackbar. */
export function useReportError(): (error: unknown) => void {
  const { setSnackbar } = useContext(ContentContext);
  const { t } = useTranslation();
  return (error) => {
    console.error(error);
    setSnackbar({
      message: describeError(error, t),
      className: "bg-red-700",
      timeout: 5000,
    });
  };
}
