/** @format */

import { useContext } from "react";
import { MdCheck } from "react-icons/md";
import { ContentContext } from "./intefaces";

/** Confirms a finished action with a check mark in the snackbar. */
export function useReportSuccess(): (message: string) => void {
  const { setSnackbar } = useContext(ContentContext);
  return (message) => {
    setSnackbar({
      message: (
        <span className="flex">
          <MdCheck className="w-5 h-5 mx-2" />
          {message}
        </span>
      ),
      className: "bg-emerald-600 rounded-4xl",
      timeout: 5000,
    });
  };
}
