import { Field, Input, Label } from "@headlessui/react";
import { useTranslation } from "react-i18next";
import Button from "../../../core/Button";
import { useContext, useState } from "react";
import { fetch } from "@tauri-apps/plugin-http";
import { ContentContext } from "../../../../intefaces";
import SecondRegisterStep from "./Step2";

export default function FirstRegisterStep() {
  const { t } = useTranslation();
  const [email, setEmail] = useState("");
  const validEmail = (email: string) => {
    const pattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return pattern.test(email);
  };
  const context = useContext(ContentContext);

  const submit = async () => {
    if (!validEmail(email)) {
      return;
    }
    const url =
      "https://api.mrquantumoff.dev/api/v3/account/registration/request";
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email: email,
      }),
    });
    if (response.status !== 202) {
      context.setSnackbar({
        className: "bg-red-700 text-white",
        message: t(await response.text()),
        timeout: 3000,
      });
    }
    context.changeContent({
      content: <SecondRegisterStep email={email} />,
      icon: <></>,
      title: t("register"),
      main: false,
      name: t("register"),
      style: "",
    });
  };

  return (
    <div className="flex flex-col w-full h-full items-center justify-center content-main ">
      <Field
        className={"flex-col flex items-center justify-center"}
        onSubmit={submit}
      >
        <Label className="font-extrabold text-4xl my-2">{t("register")}</Label>
        <Input
          className={"input"}
          placeholder={t("email")}
          value={email}
          onChange={(e) => {
            setEmail(e.target.value);
          }}
          type="email"
        ></Input>
        <Button
          className={"w-full bg-emerald-600 my-2 h-full hover:bg-emerald-800"}
          onClick={submit}
        >
          {t("register")}
        </Button>
      </Field>
    </div>
  );
}
