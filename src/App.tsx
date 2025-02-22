import { useEffect, useRef, useState } from "react";
import {
  AccountNotification,
  Article,
  ContentContext,
  IContentContext,
  ModLoader,
  ModSource,
  ModType,
  Page,
  SnackbarState,
} from "./intefaces";
import "./App.css";
import { I18nextProvider, useTranslation } from "react-i18next";
import ApplyPage from "./components/Pages/ApplyPage/Apply";
import SettingsPage from "./components/Pages/SettingsPage/Settings";
import quadrantLocale from "./i18n";
import { LazyStore } from "@tauri-apps/plugin-store";
import {
  MdAccountCircle,
  MdArchive,
  MdCheck,
  MdClear,
  MdClose,
  MdDescription,
  MdMarkEmailRead,
  MdMinimize,
  MdNotifications,
  MdOpenInBrowser,
  MdSearch,
  MdSettings,
  MdSync,
} from "react-icons/md";
import CurrentModpackPage from "./components/Pages/CurrentModpackPage/CurrentModpackPage";
import { AnimatePresence, motion } from "motion/react";
import SearchPage from "./components/Pages/SearchPage/SearchPage";
import { onOpenUrl } from "@tauri-apps/plugin-deep-link";
import {
  getCurrentWindow,
  LogicalSize,
  ProgressBarStatus,
} from "@tauri-apps/api/window";
import {
  answerInvite,
  getAccountInfo,
  getMod,
  getNews,
  openIn,
  readNotification,
} from "./tools";
import ModInstallPage from "./components/Pages/ModInstallPage/ModInstallPage";
import AccountPage from "./components/Pages/AccountPage/AccountPage";
import { invoke } from "@tauri-apps/api/core";
import ShareSyncPage from "./components/Pages/ShareSyncPage/ShareSyncPage";
import Button from "./components/core/Button";
import { listen } from "@tauri-apps/api/event";
import {
  Popover,
  PopoverBackdrop,
  PopoverButton,
  PopoverPanel,
} from "@headlessui/react";
import {
  isPermissionGranted,
  requestPermission,
  sendNotification,
} from "@tauri-apps/plugin-notification";
import LinearProgress from "./components/core/LinearProgress";

interface PageWithScroll {
  scrollPositionX: number;
  scrollPositionY: number;
  page: Page;
}

function App() {
  const { t } = useTranslation();
  const pages: Page[] = [
    {
      content: <ApplyPage />,
      title: t("apply"),
      name: "apply",
      icon: <MdCheck className="duration-0 w-8 h-8" />,
      style: " hover:bg-emerald-400 data-[selected=true]:bg-emerald-900 ",
      main: true,
    },
    {
      content: <CurrentModpackPage />,
      title: t("currentModpack"),
      name: "currentModpack",
      icon: <MdDescription className="duration-0 w-8 h-8" />,
      style: " hover:bg-blue-400 data-[selected=true]:bg-blue-900 ",
      main: true,
    },
    {
      content: <SearchPage />,
      title: t("search"),
      name: "search",
      icon: <MdSearch className="duration-0 w-8 h-8" />,
      style: " hover:bg-sky-400 data-[selected=true]:bg-sky-900 ",
      main: true,
    },
    {
      content: <ShareSyncPage />,
      title: t("importMods"),
      name: "shareSync",
      icon: <MdSync className="duration-0 w-8 h-8" />,
      style: " hover:bg-cyan-400 data-[selected=true]:bg-cyan-900 ",
      main: true,
    },
    {
      content: <AccountPage />,
      title: t("account"),
      name: "account",
      icon: <MdAccountCircle className="duration-0 w-8 h-8" />,
      style: " hover:bg-orange-400 data-[selected=true]:bg-orange-900 ",
      main: true,
    },
    {
      content: <SettingsPage />,
      title: t("settings"),
      name: "settings",
      icon: <MdSettings className="duration-0 w-8 h-8" />,
      style: " hover:bg-gray-700 data-[selected=true]:bg-black/25 ",
      main: true,
    },
  ];
  const [page, setPage] = useState(pages[0]);
  const [content, setContent] = useState<Page>(pages[0]);
  const [updateDownloadProgress, setUpdateDownloadProgress] = useState(0);
  const config = new LazyStore("config.json");
  const [contentHistory, setContentHistory] = useState<PageWithScroll[]>([]);
  const [extendedNavigation, setExtendedNavigation] = useState(false);
  const [notifications, setNotifications] = useState<AccountNotification[]>([]);
  const [snackBarHistory, setSnackbarHistory] = useState<SnackbarState[]>([]);
  const [areNotificationsHighlighted, setAreNotificationsHighlighted] =
    useState("bg-slate-700 hover:bg-slate-600");
  const [news, setNews] = useState<Article[]>([]);

  const contentRef = useRef<HTMLDivElement | null>(null);

  const [showApp, setShowApp] = useState(false);

  useEffect(() => {
    const effect = async () => {
      await listen("updateDownloadProgress", async (e: any) => {
        if (updateDownloadProgress !== e.payload) {
          setUpdateDownloadProgress(e.payload);
          currentWindow.setProgressBar({ progress: e.payload * 100 });
          if (e.payload === 1) {
            currentWindow.setProgressBar({
              progress: 0,
              status: ProgressBarStatus.None,
            });
          }
        }
      });

      await listen("disableRightClick", (_: any) =>
        document.addEventListener("contextmenu", (event) =>
          event.preventDefault()
        )
      );

      await listen("quadrantExportProgress", async (e: any) => {
        console.log("Raw progress: " + e.payload);
        const progress = Math.round(e.payload * 100);

        console.log(progress);

        currentWindow.setProgressBar({ progress: progress });
        if (e.payload === 1) {
          currentWindow.setProgressBar({
            progress: 0,
            status: ProgressBarStatus.None,
          });
          contextFunctions.setSnackbar({
            className: "bg-emerald-700 rounded-2xl",
            message: (
              <span className="flex">
                <span>{t("export")}</span>
                <MdArchive className="w-6 h-6 mx-2" /> {progress}%
              </span>
            ),
            timeout: 15000,
          });
        } else {
          contextFunctions.setSnackbarNoState({
            message: (
              <span className="flex">
                <span>{t("export")}</span>
                <MdArchive className="w-6 h-6 mx-2" /> {progress}%
              </span>
            ),
            className: "bg-gray-700 rounded-2xl",
            timeout: 500000,
          });
        }
      });

      await listen("modpackDownloadProgress", async (e: any) => {
        const progress = Math.round(e.payload);
        currentWindow.setProgressBar({
          progress: progress,
        });
        if (progress === 1) {
          currentWindow.setProgressBar({
            progress: 0,
            status: ProgressBarStatus.None,
          });
        }
      });

      setExtendedNavigation(
        (await config.get<boolean>("extendedNavigation")) ?? false
      );
      setPage(pages[(await config.get<number>("lastPage")) ?? 0]);
      setContent(pages[(await config.get<number>("lastPage")) ?? 0]);

      config.onKeyChange(
        "extendedNavigation",
        async (newValue: boolean | undefined) => {
          setExtendedNavigation(newValue ?? false);
        }
      );
      config.onChange(async (key) => {
        if (key === "lastSettingsUpdated") {
          return;
        }
        config.set("lastSettingsUpdated", new Date().toISOString());
      });
      setContentHistory([
        {
          page: pages[(await config.get<number>("lastPage")) ?? 0],
          scrollPositionX: 0,
          scrollPositionY: 0,
        },
      ]);
      const locale = await config.get<string>("locale");
      await quadrantLocale.changeLanguage(locale);
      onOpenUrl(async (urls) => {
        console.log("deep link:", urls);
        for (const gottenUrl of urls) {
          const url = URL.parse(gottenUrl);
          const actionType = url?.protocol;
          console.log("url:", url);
          await currentWindow.setFocus();
          console.log("url protocol:", actionType);
          if (actionType === "curseforge:") {
            const action = url!.pathname.replace("/", "");
            console.log("CurseForge action:", action);
            if (action.includes("/install\\")) {
              console.log("CurseForge action is not install");
              contextFunctions.setSnackbar({
                message: t("unsupportedDownload"),
                className: "bg-red-500 text-white",
                timeout: 5000,
              });
              return;
            }
            console.log("Getting mod");
            const modId = url!.searchParams.get("addonId") ?? "";
            const fileId = url!.searchParams.get("fileId") ?? undefined;
            const mod = await getMod(
              {
                deletable: false,
                id: modId,
                downloadable: true,
                showPreviousVersion: false,
                versionTarget: "",
                modpack: "",
                modLoader: ModLoader.Unknown,
                selectable: false,
                selectUrl: null,
              },
              ModSource.CurseForge
            );
            if (mod.modType === ModType.Unknown) {
              contextFunctions.setSnackbar({
                message: t("unsupportedDownload"),
                className: "bg-red-500 text-white",
                timeout: 5000,
              });
              return;
            }
            const randomString = Math.random().toString(36).substring(2, 10);

            contextFunctions.changeContent({
              content: <ModInstallPage mod={mod} fileId={fileId} />,
              name: randomString,
              icon: <></>,
              title: mod.name,
              style: "",
              main: false,
            });
          } else if (actionType === "modrinth:") {
            console.log(url!.pathname.split("/"));

            const action = url?.pathname.split("/")[2] ?? url?.host ?? "";

            console.log("Modrinth action:", action);
            if (
              action.includes("mod") ||
              action.includes("resourcepack") ||
              action.includes("shader")
            ) {
              console.log("Getting mod");
              // This gets the slug, not the ID, but it doesn't matter for Modrinth
              let modId = "";
              url?.pathname.split("/").forEach((val) => {
                if (val !== "") {
                  modId = val;
                }
              });
              console.log("Modrinth mod ID: ", modId);
              const mod = await getMod(
                {
                  deletable: false,
                  id: modId,
                  downloadable: true,
                  showPreviousVersion: false,
                  versionTarget: "",
                  modpack: "",
                  modLoader: ModLoader.Unknown,
                  selectable: false,
                  selectUrl: null,
                },
                ModSource.Modrinth
              );
              if (mod.modType === ModType.Unknown) {
                contextFunctions.setSnackbar({
                  message: t("unsupportedDownload"),
                  className: "bg-red-500 text-white",
                  timeout: 5000,
                });
                return;
              }
              // Random string
              const randomString = Math.random().toString(36).substring(2, 10);

              contextFunctions.changeContent({
                content: <ModInstallPage mod={mod} />,
                name: randomString,
                icon: <></>,
                title: mod.name,
                style: "",
                main: false,
              });
              return;
            }
            console.log("Modrinth action is not supported");
            contextFunctions.setSnackbar({
              message: t("unsupportedDownload"),
              className: "bg-red-500 text-white",
              timeout: 5000,
            });
            return;
          } else if (actionType === "quadrantnext:") {
            const actions = url!.pathname.split("/");
            console.log(actions);
            if (!actions.includes("login") && url!.host !== "login") {
              console.log("Not login");
              return;
            }

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
          }
        }
      });

      await listen("refreshNotifications", async (event) => {
        const newNotifications = event.payload as AccountNotification[];
        newNotifications.sort((a, b) => {
          return b.created_at - a.created_at;
        });
        if (newNotifications !== notifications) {
          let permissionGranted = await isPermissionGranted();

          const newlyReceivedNotifications = newNotifications.filter(
            (n) => !notifications.includes(n)
          );

          if (!permissionGranted) {
            const permission = await requestPermission();
            permissionGranted = permission === "granted";
            console.log("Permission granted: " + permissionGranted);
          }
          setNotifications(newNotifications);

          if (permissionGranted) {
            for (const notification of newlyReceivedNotifications) {
              const shownNotifications: string[] =
                (await config.get("shownNotifications")) ?? [];
              if (
                notification.read ||
                shownNotifications.includes(notification.notification_id)
              ) {
                // console.log("Notification already displayed");
                return;
              }
              console.log("Sending notification");
              await config.set("shownNotifications", [
                ...shownNotifications,
                notification.notification_id,
              ]);

              await config.save();

              await sendNotification({
                title: "Quadrant ID",
                body: JSON.parse(notification.message)["simple_message"],
              });
            }
          }
        }
      });
      try {
        const accountInfo = await getAccountInfo();
        const newNotifications = [...accountInfo.notifications];
        newNotifications.sort((a, b) => {
          return b.created_at - a.created_at;
        });
        setNotifications(newNotifications);
      } catch (e) {
        console.log(e);
      }
      try {
        const news = await getNews();
        setNews(news);
      } catch (e) {
        console.error("Failed to get news: " + e);
      }
      setShowApp(true);
    };
    effect();
  }, []);

  useEffect(() => {
    if (notifications.filter((n) => !n.read).length > 0) {
      setAreNotificationsHighlighted("bg-red-600 hover:bg-red-500 ");
    } else if (news.filter((n) => n.new).length > 0) {
      setAreNotificationsHighlighted("bg-indigo-700 hover:bg-indigo-600 ");
    } else {
      setAreNotificationsHighlighted("bg-slate-700 hover:bg-slate-800 ");
    }
  }, [notifications]);

  useEffect(() => {
    if (updateDownloadProgress !== 0) {
      currentWindow.setSize(new LogicalSize(240, 640));
      currentWindow.setResizable(false);
      currentWindow.show();
    }
  }, [updateDownloadProgress]);

  const contextFunctions: IContentContext = {
    back: async () => {
      // If there's no previous history, do nothing.
      if (contentHistory.length < 2) return;

      // Create a copy of the history and remove the current entry.
      const newHistory = [...contentHistory];
      newHistory.pop();

      // The new last item is the previous page.
      const previousEntry = newHistory[newHistory.length - 1];

      // Update state with the previous page.
      setContent(previousEntry.page);
      setContentHistory(newHistory);

      // Wait a short time to ensure the new content is rendered before scrolling.
      setTimeout(() => {
        contentRef.current?.scrollTo({
          top: Math.round(previousEntry.scrollPositionY),
          left: Math.round(previousEntry.scrollPositionX),
          behavior: "smooth",
        });
      }, 50);
    },
    changeContent: (component) => {
      let newHistory = [...contentHistory];
      console.log(component);
      newHistory.push({
        page: component,
        scrollPositionX: 0,
        scrollPositionY: 0,
      });
      newHistory[newHistory.length - 2].scrollPositionX =
        contentRef.current?.scrollLeft ?? 0;
      newHistory[newHistory.length - 2].scrollPositionY =
        contentRef.current?.scrollTop ?? 0;

      setContentHistory(newHistory);
      contentRef.current?.scrollTo({
        top: 0,
        left: 0,
        behavior: "instant",
      });
      console.log(newHistory);
      setContent(component);
    },
    changePage: (name) => {
      const newPage = pages.filter((pg) => pg.name === name);
      setContent(newPage[0]);
      let newHistory = [...contentHistory];
      newHistory.push({
        page: newPage[0],
        scrollPositionX: 0,
        scrollPositionY: 0,
      });
      setContentHistory(newHistory);
      contentRef.current?.scrollTo({
        top: 0,
        left: 0,
        behavior: "instant",
      });
    },
    setSnackbar(newSnackBarState) {
      setSnackbarState(newSnackBarState);
      setSnackbarHistory([...snackBarHistory, newSnackBarState]);
      setSnackbarEnabled(true);
    },
    setSnackbarNoState(newSnackBarState) {
      setSnackbarState(newSnackBarState);
      setSnackbarEnabled(true);
    },
  };

  const [snackbarState, setSnackbarState] = useState<SnackbarState>({
    message: "",
    className: "hidden",
    timeout: 0,
  });

  const [snackbarEnabled, setSnackbarEnabled] = useState<boolean>(false);
  const newsRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (snackbarEnabled) {
      setTimeout(() => {
        setSnackbarEnabled(false);
      }, snackbarState.timeout);
    }
  }, [snackbarEnabled]);
  const currentWindow = getCurrentWindow();
  return (
    <I18nextProvider i18n={quadrantLocale}>
      <AnimatePresence>
        {updateDownloadProgress === 0 ? (
          <ContentContext.Provider value={contextFunctions}>
            <main className="flex flex-1 p-0 h-screen w-screen disableSelect ">
              <div className="flex items-center justify-center ">
                <div className="w-16 mx-2 flex flex-col items-center justify-center border-slate-700 ">
                  {pages.map((p, i) => {
                    const isSelected = p.name == page.name;
                    return (
                      <button
                        data-selected={isSelected}
                        className={
                          "text-center place-content-center grid justify-center align-center w-16 break-words relative min-h-fit  transition-all duration-200 ease-linear font-extrabold py-4 p-1 my-1 rounded-2xl " +
                          p.style +
                          (page === p ? "bg-slate-600" : "bg-slate-800")
                        }
                        key={i}
                        onClick={async () => {
                          await config.set("lastPage", i);
                          await config.save();
                          setPage(p);
                          setContent(p);
                          setContentHistory([
                            {
                              page: p,
                              scrollPositionX:
                                contentRef.current?.scrollLeft ?? 0,
                              scrollPositionY:
                                contentRef.current?.scrollTop ?? 0,
                            },
                          ]);
                          contentRef.current?.scrollTo({
                            top: 0,
                            left: 0,
                            behavior: "instant",
                          });
                        }}
                      >
                        <div className="grid place-content-center ">
                          {p.icon}
                        </div>
                        <AnimatePresence>
                          {extendedNavigation && (
                            <motion.p
                              initial={{ opacity: 0 }}
                              animate={{ opacity: 1 }}
                              exit={{ opacity: 0 }}
                              className="overflow-hidden text-xs break-words"
                            >
                              {p.title}
                            </motion.p>
                          )}
                        </AnimatePresence>
                      </button>
                    );
                  })}
                </div>
                <div className="border-2 h-svh border-slate-700"></div>
              </div>
              <div className="flex flex-1 flex-col text-2xl w-full overflow-y-auto">
                <div
                  data-tauri-drag-region
                  className="border-b-4 w-full border-slate-700 flex items-center shadow-2xl shadow-slate-900"
                >
                  <h1
                    data-tauri-drag-region
                    className="font-extrabold mt-4 h-full w-full"
                  >
                    <p className=" bg-slate-700 my-4 p-2 rounded-2xl w-fit mx-4">
                      {content.title}
                    </p>
                  </h1>
                  <div
                    data-tauri-drag-region
                    className="w-full items-center justify-end flex h-full mx-8"
                  >
                    <div className="bg-slate-800 p-2 flex rounded-full items-center justify-center">
                      <Popover className="relative">
                        {({ open }) => {
                          return (
                            <>
                              <div
                                className={
                                  "flex justify-center items-center mr-2"
                                }
                              >
                                <PopoverButton
                                  className={
                                    "focus:outline-hidden rounded-full transition-all duration-150 ease-linear " +
                                    areNotificationsHighlighted
                                  }
                                >
                                  <div className="p-2 rounded-full">
                                    <MdNotifications />
                                  </div>
                                </PopoverButton>
                              </div>
                              <PopoverBackdrop
                                className={"fixed inset-0 bg-slate-900/15"}
                              />
                              <AnimatePresence>
                                {open && (
                                  <PopoverPanel
                                    static
                                    as={motion.div}
                                    anchor="top start"
                                    initial={{
                                      opacity: 0,
                                      y: -100,
                                      scaleY: 0,
                                      scaleX: 0,
                                      x: 50,
                                    }}
                                    animate={{
                                      opacity: 1,
                                      y: 0,
                                      scaleY: 1,
                                      scaleX: 1,
                                      x: -150,
                                    }}
                                    exit={{
                                      opacity: 0,
                                      y: -200,
                                      scaleY: 0,
                                      scaleX: 0,
                                      x: 50,
                                    }}
                                    className="flex flex-col p-4 mt-4 font-bold bg-slate-800 rounded-2xl w-[35vw] my-8 h-[75vh] "
                                  >
                                    <div className="border-b-2 border-slate-700">
                                      {snackBarHistory.map((item) => {
                                        const randomString = Math.random()
                                          .toString(36)
                                          .substring(2, 10);

                                        return (
                                          <div
                                            className="my-2"
                                            key={item.message + randomString}
                                          >
                                            <div
                                              className={
                                                item.className +
                                                " rounded-2xl p-4"
                                              }
                                            >
                                              {item.message}
                                            </div>
                                          </div>
                                        );
                                      })}
                                    </div>
                                    <div className="border-b-2 border-slate-700">
                                      {notifications.map((notification) => {
                                        const detailedMessage = JSON.parse(
                                          notification.message
                                        );
                                        const messageType =
                                          detailedMessage.notification_type;
                                        let message: string;

                                        let action: React.ReactElement | null =
                                          (
                                            <>
                                              <Button
                                                className="w-full bg-emerald-600 hover:bg-emerald-800 transition-all ease-linear flex items-center justify-center"
                                                onClick={async () => {
                                                  await readNotification(
                                                    notification.notification_id
                                                  );
                                                }}
                                              >
                                                {t("read")}
                                                <MdMarkEmailRead className="w-4 h-4 mx-2" />
                                              </Button>
                                            </>
                                          );

                                        if (messageType == "invite_to_sync") {
                                          const inviter = (
                                            detailedMessage.message as string
                                          ).split(
                                            "You have been invited to collaborate on a modpack by "
                                          )[1];
                                          message = t("invited", {
                                            name: inviter,
                                          });
                                          action = (
                                            <>
                                              <div className="w-full flex">
                                                <Button
                                                  className="bg-emerald-600 hover:bg-emerald-800 w-full flex items-center justify-center mr-2"
                                                  onClick={async () => {
                                                    await answerInvite(
                                                      detailedMessage.invite_id,
                                                      notification.notification_id,
                                                      true
                                                    );
                                                  }}
                                                >
                                                  {t("accept")}
                                                  <MdCheck className="w-4 h-4 mx-2" />
                                                </Button>
                                                <Button
                                                  className="bg-red-700 hover:bg-red-800 w-full flex items-center justify-center"
                                                  onClick={async () => {
                                                    await answerInvite(
                                                      detailedMessage.invite_id,
                                                      notification.notification_id,
                                                      false
                                                    );
                                                  }}
                                                >
                                                  {t("decline")}
                                                  <MdClear className="w-4 h-4 mx-2" />
                                                </Button>
                                              </div>
                                            </>
                                          );
                                        } else {
                                          message =
                                            detailedMessage.simple_message;
                                        }

                                        if (notification.read) {
                                          action = null;
                                        }

                                        return (
                                          <div
                                            key={notification.notification_id}
                                            className="bg-slate-700 rounded-2xl my-2 p-2 text-center flex flex-col items-center justify-center"
                                          >
                                            <h3>{message}</h3>
                                            {action != null && (
                                              <div className="w-full my-2 flex items-center justify-center ">
                                                {action}
                                              </div>
                                            )}
                                          </div>
                                        );
                                      })}
                                    </div>
                                    <div ref={newsRef}>
                                      {news.map((article) => {
                                        return (
                                          <div
                                            key={article.guid}
                                            className="bg-slate-900 rounded-2xl my-2 p-2 text-center flex flex-col items-center justify-center"
                                          >
                                            <h3 className="font-black">
                                              {article.title}
                                            </h3>
                                            <p className="font-normal">
                                              {article.summary}
                                            </p>
                                            <div className="bg-slate-800 w-full flex p-2 rounded-2xl">
                                              <Button
                                                onClick={async () => {
                                                  await openIn(article.link);
                                                }}
                                                className="bg-blue-700 hover:bg-blue-800 transition-all w-full flex items-center justify-center"
                                              >
                                                {t("read")}
                                                <MdOpenInBrowser className="w-4 h-4 mx-2" />
                                              </Button>
                                            </div>
                                          </div>
                                        );
                                      })}
                                    </div>
                                  </PopoverPanel>
                                )}
                              </AnimatePresence>
                            </>
                          );
                        }}
                      </Popover>

                      <Button
                        fullRound
                        className="bg-slate-700 hover:bg-slate-600 mx-2"
                        onClick={async () => {
                          await currentWindow.minimize();
                        }}
                      >
                        <MdMinimize />
                      </Button>
                      <Button
                        fullRound
                        className="bg-slate-700 hover:bg-slate-600 ml-2"
                        onClick={async () => {
                          await currentWindow.hide();
                          await currentWindow.setEnabled(false);
                        }}
                      >
                        <MdClose />
                      </Button>
                    </div>
                  </div>
                </div>
                <motion.div
                  initial={{ y: 500, opacity: 0 }}
                  animate={{ y: 0, opacity: 1 }}
                  exit={{ y: 5000 }}
                  layoutScroll
                  className="h-full overflow-y-auto "
                  transition={{ type: "keyframes", duration: 0.1 }}
                  // key={content.name}
                  ref={contentRef}
                >
                  {content.main !== true && content.content}
                  <div
                    className={
                      "h-full content-main " +
                      (content.main === true && content.name === page.name
                        ? ""
                        : "hidden")
                    }
                  >
                    <AnimatePresence>{page.content}</AnimatePresence>
                  </div>
                </motion.div>
              </div>
              {/* Snackbar */}
              <AnimatePresence>
                {snackbarEnabled && (
                  <motion.div
                    initial={{ opacity: 0, y: 5000, scale: 0.125 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    exit={{ opacity: 0, y: 500, scale: 0.125 }}
                    className={
                      "transition-transform bottom-8 font-bold text-slate-50 left-8 fixed w-max h-max p-4 rounded-2xl flex flex-col items-center justify-center " +
                      snackbarState.className
                    }
                  >
                    <p>{snackbarState.message}</p>
                  </motion.div>
                )}
              </AnimatePresence>
            </main>
          </ContentContext.Provider>
        ) : showApp ? (
          <motion.div
            initial={{ opacity: 0, filter: "blur(8px)" }}
            animate={{ opacity: 1, filter: "" }}
            className="flex flex-col flex-1 items-center font-extrabold text-4xl justify-center align-middle w-screen h-screen "
            data-tauri-drag-region
          >
            <img src="/logoNoBg.svg" height={"192px"} width={"192px"}></img>
            <h1 className="flex flex-col my-2 h-min items-center font-extrabold text-4xl justify-center align-middle w-full ">
              {t("appUpdate")}
            </h1>
            <div className=" flex flex-col my-2  h-min items-center font-extrabold text-7xl justify-center align-middle w-[60vw]  ">
              <LinearProgress
                progress={updateDownloadProgress * 100}
              ></LinearProgress>
            </div>
          </motion.div>
        ) : (
          <motion.div
            initial={{ opacity: 0, filter: "blur(8px)" }}
            animate={{ opacity: 1, filter: "" }}
            className="flex flex-col flex-1 items-center font-extrabold text-4xl justify-center align-middle w-screen h-screen "
            data-tauri-drag-region
          >
            <img src="/logoNoBg.svg" height={"192px"} width={"192px"}></img>
          </motion.div>
        )}
      </AnimatePresence>
    </I18nextProvider>
  );
}

export default App;
