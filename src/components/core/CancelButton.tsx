/** @format */

import { useTranslation } from "react-i18next";
import { MdArrowBack } from "react-icons/md";
import Button from "./Button";

export default function CancelButton({
  onClick,
  className = "",
}: {
  onClick: () => void;
  className?: string;
}) {
  const { t } = useTranslation();

  return (
    <Button
      onClick={onClick}
      className={
        "self-start flex items-center justify-center bg-slate-800 hover:bg-slate-700 " +
        className
      }
    >
      <MdArrowBack aria-hidden="true" className="w-6 h-6 mr-1 shrink-0" />
      {t("cancel")}
    </Button>
  );
}
