import { useContext, useEffect, useState } from "react";
import { AccountInfo } from "../../../intefaces";
import { clearAccountToken, getAccountInfo, openIn } from "../../../tools";
import Button from "../../core/Button";
import { listen } from "@tauri-apps/api/event";
import { useTranslation } from "react-i18next";
import { LazyStore } from "@tauri-apps/plugin-store";
import { MdOpenInBrowser, MdOutlineAccountCircle } from "react-icons/md";
import { ContentContext } from "../../../intefaces";
import FirstRegisterStep from "./RegisterPages/Step1";
import SignInPage from "./SignInPage";
import { start } from "@fabianlars/tauri-plugin-oauth";
import { cancel, onUrl as onOAuth } from "@fabianlars/tauri-plugin-oauth";
import { invoke } from "@tauri-apps/api/core";

export default function AccountPage() {
  const { t } = useTranslation();
  const [accountInfo, setAccountInfo] = useState<AccountInfo | null>(null);

  const updateAccountInfo = async () => {
    try {
      setAccountInfo(await getAccountInfo());
    } catch (e) {
      setAccountInfo(null);
    }
  };

  useEffect(() => {
    listen<string>("recheckAccountToken", async (_) => {
      try {
        setAccountInfo(await getAccountInfo());
      } catch (e) {
        setAccountInfo(null);
      }
    });

    const effect = async () => {
      try {
        const newAccountInfo = await getAccountInfo();
        console.log("Account info: " + newAccountInfo);
        setAccountInfo(newAccountInfo);
      } catch (e) {
        setAccountInfo(null);
      }
    };
    effect().catch(console.error);
  }, []);

  const config = new LazyStore("config.json");

  const context = useContext(ContentContext);

  //   const;
  return accountInfo !== null ? (
    <>
      <div className="flex flex-col items-center justify-center align-middle flex-1 h-full">
        <h1 className="font-extrabold text-4xl">
          {t("hello", { name: accountInfo.name })}
        </h1>
        <div className="w-[50%] items-center justify-center text-center font-bold">
          <h2 className="bg-slate-800 p-2 rounded-2xl my-4">
            {t("email")}: {accountInfo.email}
          </h2>
          <h2 className="bg-slate-800 p-2 rounded-2xl my-4">
            {t("username")}: {accountInfo.login}
          </h2>
          <h2 className="bg-slate-800 p-2 rounded-2xl my-4">
            {t("syncLimit")}: {accountInfo.quadrant_sync_limit}
          </h2>
          <h2 className="bg-slate-800 p-2 rounded-2xl my-4">
            {t("shareLimit")}: {accountInfo.quadrant_share_limit}
          </h2>
        </div>
        <div className="flex flex-row w-[75%] items-center justify-center mt-4">
          <Button
            className="bg-red-700 hover:bg-red-800 h-min mx-2 w-full"
            onClick={async () => {
              await clearAccountToken();
              updateAccountInfo();
            }}
          >
            {t("signout")}
          </Button>
          <Button
            className="bg-blue-600 hover:bg-blue-800 h-min mx-2 w-full"
            onClick={async () => {
              openIn("https://mrquantumoff.dev/account/manage");
            }}
          >
            {t("edit")}
          </Button>
        </div>
      </div>
    </>
  ) : (
    <div className="items-center justify-center align-middle flex flex-1 h-full flex-col w-full ">
      <div className="place-content-center w-[75%] ">
        <div className="bg-slate-800 rounded-2xl p-2 my-4">
          <h1 className="font-extrabold text-4xl my-2">{t("signIn")}</h1>
          <h2 className="font-bold text-2xl my-2">{t("emailAndPassword")}</h2>
        </div>
        <div className="w-full flex flex-row">
          <Button
            onClick={async () => {
              const randomString = Math.random().toString(36).substring(2, 26);

              await config.set("oauthState", randomString);

              try {
                const port = await start({
                  response:
                    "<html><body><h1>" +
                    t("returnToTheApp") +
                    "</h1></body></html>",
                });

                console.log(`OAuth server started on port ${port}`);

                openIn(
                  "https://mrquantumoff.dev/account/oauth2/authorize?client_id=2e1830be-1134-4fec-bfcb-c403dd2b9c94&redirect_uri=http://127.0.0.1:" +
                    port +
                    "&scope=user_data,quadrant_sync,notifications&duration=7776000&response_type=code&state=" +
                    randomString
                );
                onOAuth(async (rawUrl) => {
                  try {
                    const url = URL.parse(rawUrl);
                    const actions = url!.pathname.split("/");
                    console.log(actions);
                    console.log(rawUrl);

                    const oAuthState = await config.get<string>("oauthState");

                    const providedState = url!.searchParams.get("state");
                    console.log("State: " + oAuthState);
                    console.log("Provided state: " + providedState);
                    if (providedState !== oAuthState) {
                      return;
                    }
                    const code = url!.searchParams.get("code");
                    console.log("Code: " + code);
                    if (code === null) {
                      return;
                    }
                    await invoke("oauth2_login", {
                      code: code,
                    });
                  } catch (e) {
                    console.error(e);
                  }
                  await cancel(port);
                });
              } catch (error) {
                console.error("Error starting OAuth server:", error);
              }
            }}
            className="bg-sky-500 hover:bg-sky-800 w-full mx-2"
          >
            {t("signInWithOAuth")}
          </Button>
          <Button
            onClick={async () => {
              context.changeContent({
                content: <SignInPage />,
                icon: <></>,
                title: t("signInNoOAuth"),
                main: false,
                name: t("signInNoOAuth"),
                style: "",
              });
            }}
            className="bg-slate-500 hover:bg-slate-800 w-full mx-2"
          >
            {t("signInNoOAuth")}
          </Button>
          <Button
            onClick={async () => {
              context.changeContent({
                content: <FirstRegisterStep />,
                icon: <MdOutlineAccountCircle />,
                title: t("register"),
                main: false,
                name: t("register"),
                style: "",
              });
            }}
            className="bg-blue-500 hover:bg-blue-800 w-full mx-2"
          >
            {t("dontHaveAccount")}
          </Button>
        </div>
      </div>
      <div className="mt-4 w-[47.5vw]">
        <Button
          className="bg-slate-700 hover:bg-slate-800 w-full h-full flex flex-row items-center justify-center text-lg"
          onClick={async () => {
            openIn(
              "https://github.com/mrquantumoff/quadrant/blob/master/QUADRANT-ID-TOS.md"
            );
          }}
        >
          {t("acceptQuadrantIDTOS")}
          <MdOpenInBrowser className="w-12 h-12 ml-2 "></MdOpenInBrowser>
        </Button>
      </div>
    </div>
  );
}
