/** @format */

import React, { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import { useTranslation } from "react-i18next";
import {
	Popover,
	PopoverBackdrop,
	PopoverButton,
	PopoverPanel,
} from "@headlessui/react";
import { listen } from "@tauri-apps/api/event";
import {
	isPermissionGranted,
	requestPermission,
	sendNotification,
} from "@tauri-apps/plugin-notification";
import { LazyStore } from "@tauri-apps/plugin-store";
import {
	MdCheck,
	MdClear,
	MdMarkEmailRead,
	MdNotifications,
	MdOpenInBrowser,
} from "react-icons/md";
import Button from "../core/Button";
import {
	AccountNotification,
	Article,
	SnackbarHistoryItem,
} from "../../intefaces";
import {
	answerInvite,
	getAccountInfo,
	getNews,
	openIn,
	readNotification,
} from "../../tools";

type NotificationsProps = {
	config: LazyStore;
	snackBarHistory: SnackbarHistoryItem[];
	setSnackbarHistory: React.Dispatch<
		React.SetStateAction<SnackbarHistoryItem[]>
	>;
};

function Notifications({
	config,
	snackBarHistory,
	setSnackbarHistory,
}: NotificationsProps) {
	const { t } = useTranslation();
	const [notifications, setNotifications] = useState<AccountNotification[]>([]);
	const [areNotificationsHighlighted, setAreNotificationsHighlighted] =
		useState("bg-slate-700 hover:bg-slate-600");
	const [news, setNews] = useState<Article[]>([]);
	const newsRef = useRef<HTMLDivElement | null>(null);

	useEffect(() => {
		let isUnmounted = false;
		const cleanupFns: Array<() => void> = [];

		const effect = async () => {
			const refreshNotificationsUnlisten = await listen(
				"refreshNotifications",
				async (event) => {
					if (isUnmounted) {
						return;
					}
					const sortedNotifications = [
						...(event.payload as AccountNotification[]),
					].sort((a, b) => b.created_at - a.created_at);

					let newlyReceived: AccountNotification[] = [];
					setNotifications((prevNotifications) => {
						const previousIds = new Set(
							prevNotifications.map((n) => n.notification_id),
						);
						newlyReceived = sortedNotifications.filter(
							(notification) => !previousIds.has(notification.notification_id),
						);
						return sortedNotifications;
					});

					if (newlyReceived.length === 0) {
						return;
					}

					let permissionGranted = await isPermissionGranted();
					if (!permissionGranted) {
						const permission = await requestPermission();
						permissionGranted = permission === "granted";
						console.log("Permission granted: " + permissionGranted);
					}

					if (!permissionGranted || isUnmounted) {
						return;
					}

					const shownNotifications: string[] =
						(await config.get("shownNotifications")) ?? [];

					const unseenNotifications = newlyReceived.filter(
						(notification) =>
							!notification.read &&
							!shownNotifications.includes(notification.notification_id),
					);

					if (unseenNotifications.length === 0 || isUnmounted) {
						return;
					}

					const updatedShown = [...shownNotifications];
					for (const notification of unseenNotifications) {
						updatedShown.push(notification.notification_id);
						if (isUnmounted) {
							break;
						}
						await sendNotification({
							title: "Quadrant ID",
							body: JSON.parse(notification.message)["simple_message"],
						});
					}

					if (!isUnmounted) {
						await config.set("shownNotifications", updatedShown);
						await config.save();
					}
				},
			);
			if (isUnmounted) {
				refreshNotificationsUnlisten();
			} else {
				cleanupFns.push(refreshNotificationsUnlisten);
			}

			try {
				const accountInfo = await getAccountInfo();
				if (!isUnmounted) {
					const newNotifications = [...accountInfo.notifications];
					newNotifications.sort((a, b) => {
						return b.created_at - a.created_at;
					});
					setNotifications(newNotifications);
				}
			} catch (e) {
				console.log(e);
			}
			try {
				const latestNews = await getNews();
				if (!isUnmounted) {
					setNews(latestNews);
				}
			} catch (e) {
				console.error("Failed to get news: " + e);
			}
		};

		effect().catch((error) => {
			console.error(error);
		});

		return () => {
			isUnmounted = true;
			while (cleanupFns.length > 0) {
				const cleanup = cleanupFns.pop();
				try {
					cleanup?.();
				} catch (error) {
					console.error(error);
				}
			}
		};
	}, [config]);

	useEffect(() => {
		if (notifications.filter((n) => !n.read).length > 0) {
			setAreNotificationsHighlighted("bg-red-600 hover:bg-red-500 ");
		} else if (news.filter((n) => n.new).length > 0) {
			setAreNotificationsHighlighted("bg-indigo-700 hover:bg-indigo-600 ");
		} else {
			setAreNotificationsHighlighted("bg-slate-700 hover:bg-slate-800 ");
		}
	}, [notifications]);

	return (
		<Popover className="relative">
			{({ open }) => {
				return (
					<>
						<div className={"flex justify-center items-center mr-2"}>
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
						<PopoverBackdrop className={"fixed inset-0 bg-slate-900/15"} />
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
									className="flex flex-col p-4 mt-4 font-bold bg-slate-800 rounded-4xl w-[35vw] my-8 h-[75vh] "
								>
									<div className="border-b-2 border-slate-700">
										{snackBarHistory.length > 0 && (
											<motion.div className="my-2 flex items-center justify-between gap-2">
												<div
													className={
														snackBarHistory[0].className +
														" rounded-4xl p-4 flex flex-1 min-w-0 items-center justify-between"
													}
												>
													<span>{snackBarHistory[0].message}</span>
													{snackBarHistory[0].count > 1 && (
														<span className="ml-2 bg-slate-900/50 px-2 py-1 rounded-full text-sm">
															{snackBarHistory[0].count}x
														</span>
													)}
												</div>
												<Button
													className="bg-slate-700 hover:bg-slate-600 transition-all flex items-center justify-center shrink-0"
													onClick={() => {
														setSnackbarHistory([]);
													}}
												>
													{t("pureClear")}
													<MdClear className="w-4 h-4 ml-2" />
												</Button>
											</motion.div>
										)}
										{snackBarHistory.slice(1).map((item) => {
											return (
												<div className="my-2" key={item.id}>
													<div
														className={
															item.className +
															" rounded-4xl p-4 flex items-center justify-between"
														}
													>
														<span>{item.message}</span>
														{item.count > 1 && (
															<span className="ml-2 bg-slate-900/50 px-2 py-1 rounded-full text-sm">
																{item.count}x
															</span>
														)}
													</div>
												</div>
											);
										})}
									</div>
									<div className="border-b-2 border-slate-700">
										{notifications.map((notification) => {
											const detailedMessage = JSON.parse(notification.message);
											const messageType = detailedMessage.notification_type;
											let message: string;

											let action: React.ReactElement | null = (
												<>
													<Button
														className="w-full bg-emerald-600 hover:bg-emerald-800 transition-all ease-linear flex items-center justify-center"
														onClick={async () => {
															await readNotification(
																notification.notification_id,
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
													"You have been invited to collaborate on a modpack by ",
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
																		true,
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
																		false,
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
												message = detailedMessage.simple_message;
											}

											if (notification.read) {
												action = null;
											}

											return (
												<div
													key={notification.notification_id}
													className="bg-slate-700 rounded-4xl my-2 p-2 text-center flex flex-col items-center justify-center"
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
													className="bg-slate-900 rounded-4xl my-2  p-4 text-center flex flex-col items-center justify-center"
												>
													<h3 className="font-black">{article.title}</h3>
													<div
														className="font-normal"
														dangerouslySetInnerHTML={{
															__html: article.summary,
														}}
													/>
													<div className="bg-slate-800 w-full flex p-2 rounded-4xl">
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
	);
}

export default Notifications;
