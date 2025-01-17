import { Field, Fieldset, Input } from "@headlessui/react";
import { useContext, useState } from "react";
import { useTranslation } from "react-i18next";
import Button from "../../../core/Button";
import { ContentContext } from "../../../../App";
import { fetch } from "@tauri-apps/plugin-http";

export interface SecondRegisterStepProps {
  email: string;
}

export default function SecondRegisterStep({ email }: SecondRegisterStepProps) {
  const { t } = useTranslation();
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [username, setUsername] = useState("");
  const [code, setCode] = useState("");
  const [name, setName] = useState("");
  const context = useContext(ContentContext);
  const [disableButtons, setDisableButtons] = useState(false);

  const register = async () => {
    setDisableButtons(true);
    if (password !== confirmPassword) {
      context.setSnackbar({
        className: "bg-red-500",
        message: t("passwordsDoNotMatch"),
        timeout: 8000,
      });
      return;
    }
    if (
      password == "" ||
      confirmPassword == "" ||
      code == "" ||
      username == "" ||
      name == "" ||
      email == ""
    ) {
      setDisableButtons(false);
      return;
    }
    const body = {
      email: email,
      password: password,
      verification_code: Number(code),
      login: username,
      name: name,
    };
    const request = await fetch(
      "https://api.mrquantumoff.dev/api/v3/account/registration/confirm",
      {
        body: JSON.stringify(body),
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
      }
    );
    if (request.status !== 201) {
      context.setSnackbar({
        className: "bg-red-500",
        message: t(await request.text()),
        timeout: 16000,
      });
      setDisableButtons(false);
      return;
    }
    context.changePage("account");
  };

  return (
    <>
      <div className="h-full w-full flex flex-con items-center justify-center content-main">
        <Fieldset disabled={disableButtons} onSubmit={register}>
          <Field>
            <Input
              className={"bg-slate-600 focus:outline-none rounded-2xl p-4 my-2"}
              placeholder={t("email")}
              disabled
              value={email}
              onChange={() => {}}
            ></Input>
          </Field>
          <Field>
            <Input
              className={
                "bg-slate-700 hover:bg-slate-600 focus:outline-none rounded-2xl p-4 my-2"
              }
              placeholder={t("password")}
              type="password"
              value={password}
              onChange={(e) => {
                setPassword(e.target.value);
              }}
            ></Input>
          </Field>
          <Field>
            <Input
              className={
                "bg-slate-700 hover:bg-slate-600 focus:outline-none rounded-2xl p-4 my-2"
              }
              type="password"
              placeholder={t("password")}
              value={confirmPassword}
              onChange={(e) => {
                setConfirmPassword(e.target.value);
              }}
            ></Input>
          </Field>
          <Field>
            <Input
              className={
                "bg-slate-700 hover:bg-slate-600 focus:outline-none rounded-2xl p-4 my-2"
              }
              placeholder={t("verificationCode")}
              value={code}
              onChange={(e) => {
                if (
                  isNaN(Number(e.target.value)) ||
                  e.target.value.length > 8
                ) {
                  return;
                }
                setCode(e.target.value);
              }}
            ></Input>
          </Field>
          <Field>
            <Input
              className={
                "bg-slate-700 hover:bg-slate-600 focus:outline-none rounded-2xl p-4 my-2"
              }
              placeholder={t("username")}
              value={username}
              onChange={(e) => {
                setUsername(e.target.value);
              }}
            ></Input>
          </Field>
          <Field>
            <Input
              className={
                "bg-slate-700 hover:bg-slate-600 focus:outline-none rounded-2xl p-4 my-2"
              }
              placeholder={t("name")}
              value={name}
              onChange={(e) => {
                setName(e.target.value);
              }}
            ></Input>
          </Field>
          <Button
            onClick={register}
            className="bg-emerald-600 hover:bg-emerald-800 my-4 w-full data-[disabled]:bg-slate-700 data-[disabled]:hover:bg-slate-600 data-[disabled]:cursor-not-allowed"
          >
            {t("register")}
          </Button>
        </Fieldset>
      </div>
    </>
  );
}
