import { Field, Fieldset, Input } from "@headlessui/react";
import { useContext, useState } from "react";
import { useTranslation } from "react-i18next";
import Button from "../../core/Button";
import { ContentContext } from "../../../intefaces";
import { invoke } from "@tauri-apps/api/core";

export default function SignInPage() {
  const { t } = useTranslation();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [isOTPRequired, setIsOTPRequired] = useState(false);
  const context = useContext(ContentContext);

  const attemptSignIn = async () => {
    const requestBody = {
      email: email,
      password: password,
      otp: Number.parseInt(code),
    };
    console.log(
      "Attempting sign in...\nRequest body: " + JSON.stringify(requestBody)
    );
    try {
      await invoke("sign_in", requestBody);
    } catch (e: any) {
      console.error(e);

      if (e.toString().includes("OTP")) {
        setIsOTPRequired(true);
        return;
      }
      context.setSnackbar({
        className: "bg-red-700 text-white",
        message: t(e.toString()),
        timeout: 5000,
      });
      setIsOTPRequired(false);
      return;
    }
    context.back();
  };

  return (
    <div className="w-full h-full flex flex-row items-center justify-center content-main">
      {isOTPRequired ? (
        <div>
          <Fieldset className={"flex flex-col"}>
            <Field className={"my-2"}>
              <Input
                className={"input"}
                type="text"
                placeholder={t("otp")}
                value={code}
                onChange={(e) => {
                  if (isNaN(Number.parseInt(e.target.value))) {
                    return;
                  }
                  setCode(e.target.value);
                }}
              />
            </Field>
            <Button
              className="bg-emerald-600 hover:bg-emerald-800 my-2"
              onClick={attemptSignIn}
            >
              {t("signIn")}
            </Button>
          </Fieldset>
        </div>
      ) : (
        <Fieldset className={"flex flex-col"}>
          <Field className={"my-2"}>
            <Input
              className={"input"}
              type="email"
              placeholder={t("email")}
              value={email}
              onChange={(e) => {
                setEmail(e.target.value);
              }}
              autoComplete="off"
            />
          </Field>
          <Field className={"my-2"}>
            <Input
              className={"input"}
              type="password"
              placeholder={t("password")}
              value={password}
              onChange={(e) => {
                setPassword(e.target.value);
              }}
              autoComplete="off"
            />
          </Field>
          <Button
            className="bg-emerald-600 hover:bg-emerald-800 my-2"
            onClick={attemptSignIn}
          >
            {t("signIn")}
          </Button>
        </Fieldset>
      )}
    </div>
  );
}
