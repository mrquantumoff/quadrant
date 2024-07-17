import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:get_storage_qnt/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/other/restart_app.dart';
import 'package:quadrant/pages/settings/send_feedback/send_feedpack.dart';
import 'package:url_launcher/url_launcher.dart';

class Settings extends StatefulWidget {
  const Settings({super.key, required this.setLocale});

  final Function(String locale) setLocale;

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  late TextEditingController _controller;
  late String mcFolder;
  late String latestVersion;
  bool clipButtons = GetStorage().read("clipIcons");
  bool collectData = GetStorage().read("collectUserData");
  bool curseForge = GetStorage().read("curseForge");
  bool modrinth = GetStorage().read("modrinth");
  bool devMode = GetStorage().read("devMode") ?? false;
  bool rssFeeds = GetStorage().read("rssFeeds");
  bool silentNews = GetStorage().read("silentNews");

  bool autoQuadrantSync = GetStorage().read("autoQuadrantSync");
  bool extendedNavigation = GetStorage().read("extendedNavigation");
  bool showUnupgradeableMods = GetStorage().read("showUnupgradeableMods");
  bool experimentalFeatures = GetStorage().read("experimentalFeatures");

  @override
  void dispose() {
    super.dispose();
  }

  void updateMinecraftFolderText() {
    setState(() {
      mcFolder = getMinecraftFolder().path;
    });
  }

  void setClipButtons(bool newValue) {
    GetStorage().write("clipIcons", newValue);
    setState(() {
      clipButtons = newValue;
    });
  }

  void setDevMode(bool newValue) {
    GetStorage().write("devMode", newValue);
    setState(() {
      devMode = newValue;
    });
  }

  void setShowUnupgradeableMods(bool newValue) {
    GetStorage().write("showUnupgradeableMods", newValue);
    setState(() {
      showUnupgradeableMods = newValue;
    });
  }

  void setRSSFeeds(bool newValue) {
    GetStorage().write("rssFeeds", newValue);
    setState(() {
      rssFeeds = newValue;
    });
  }

  void setSilentNews(bool newValue) {
    GetStorage().write("silentNews", newValue);
    setState(() {
      silentNews = newValue;
    });
  }

  void setCollectData(bool newValue) {
    GetStorage().write("collectUserData", newValue);
    if (!newValue) {
      GetStorage().write("dontShowTelemetryRecommendation", false);
    }
    setState(() {
      collectData = newValue;
    });
  }

  void setExpFeatures(bool newValue) {
    GetStorage().write("experimentalFeatures", newValue);
    setState(() {
      experimentalFeatures = newValue;
    });
    // RestartWidget.restartApp(context);
  }

  @override
  void initState() {
    mcFolder = getMinecraftFolder().path;
    super.initState();
    _controller = TextEditingController();
  }

  void setModrinth(bool newValue) {
    GetStorage().write("modrinth", newValue);
    setState(() {
      modrinth = newValue;
    });
  }

  void setCurseForge(bool newValue) {
    GetStorage().write("curseForge", newValue);
    setState(() {
      curseForge = newValue;
    });
  }

  void setAutoQuadrantSync(bool newValue) {
    GetStorage().write("autoQuadrantSync", newValue);
    setState(() {
      autoQuadrantSync = newValue;
    });
  }

  void setExtendedNavigation(bool newValue) {
    GetStorage().write("extendedNavigation", newValue);
    setState(() {
      extendedNavigation = newValue;
    });
    RestartWidget.restartApp(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.someSettingsRequireReload),
      ),
      body: Container(
        margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
        child: ListView(
          children: [
            const SizedBox(
              height: 4,
            ),
            DropdownMenu(
              width: 300,
              controller: _controller,
              label: Text(AppLocalizations.of(context)!.language),
              dropdownMenuEntries: [
                const DropdownMenuEntry(value: "en", label: "English"),
                const DropdownMenuEntry(value: "uk", label: "Українська"),
                const DropdownMenuEntry(value: "tr", label: "Türkçe"),
                DropdownMenuEntry(
                    value: "native",
                    label: AppLocalizations.of(context)!.systemLocale),
              ],
              onSelected: (value) async {
                debugPrint("Selected value: ${value ?? "en"}");
                widget.setLocale(value ?? "en");
              },
            ),
            FutureBuilder<Map<String, String>>(
              builder: (BuildContext context,
                  AsyncSnapshot<Map<String, String>> snapshot) {
                if (snapshot.hasError) {
                  return Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 12),
                    child: const Icon(Icons.error),
                  );
                }
                if (snapshot.hasData) {
                  return Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 0),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.currentVersion(
                                "v${snapshot.data!["currentRelease"]}",
                              ),
                              style: const TextStyle(fontSize: 16),
                            ),
                            Text(
                              AppLocalizations.of(context)!.latestVersion(
                                snapshot.data!["latestRelease"] ??
                                    AppLocalizations.of(context)!.unknown,
                              ),
                              style: const TextStyle(fontSize: 16),
                            ),
                            Container(
                              margin: const EdgeInsets.only(top: 12),
                              child: TextButton.icon(
                                onPressed: () {
                                  Uri uri = Uri.parse(
                                    snapshot.data!["url"] ??
                                        AppLocalizations.of(context)!.unknown,
                                  );
                                  launchUrl(uri);
                                },
                                icon: const Icon(Icons.open_in_browser),
                                label: Text(
                                  AppLocalizations.of(context)!
                                      .openLatestRelease,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }
                return Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 12),
                  child: const LinearProgressIndicator(),
                );
              },
              future: getReleaseInfo(),
            ),
            Container(
              alignment: AlignmentDirectional.topStart,
              child: Container(
                margin: const EdgeInsets.only(top: 0, bottom: 12),
                child: TextButton.icon(
                  onPressed: () async {
                    await launchUrl(
                      Uri.parse(
                          "https://github.com/mrquantumoff/quadrant/blob/master/QUADRANT-ID-TOS.md"),
                    );
                  },
                  label: Text(AppLocalizations.of(context)!.quadrantIDToS),
                  icon: const Icon(Icons.open_in_browser),
                ),
              ),
            ),
            Container(
              alignment: AlignmentDirectional.topStart,
              margin: const EdgeInsets.only(top: 12),
              child: TextButton.icon(
                onPressed: () async {
                  var package = await PackageInfo.fromPlatform();
                  showAboutDialog(
                    context: context,
                    applicationLegalese:
                        "Copyright (c) 2022-2024 qnt/MrQuantumOFF (Demir Yerli), licensed to you under MPL-2.0",
                    applicationName: AppLocalizations.of(context)!.productName,
                    applicationVersion:
                        "${package.appName} v${package.version}+${package.buildNumber}",
                    applicationIcon: Image.asset(
                      "assets/icons/logo256.png",
                      width: 64,
                    ),
                  );
                },
                icon: const Icon(Icons.info),
                label: Text(
                  AppLocalizations.of(context)!.details,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            Container(
              alignment: AlignmentDirectional.topStart,
              margin: const EdgeInsets.only(top: 12),
              child: Container(
                margin: const EdgeInsets.only(top: 0, bottom: 6),
                child: TextButton.icon(
                  onPressed: () async {
                    Get.to(
                      () => const SendFeedpackPage(),
                      transition: Transition.upToDown,
                    );
                  },
                  label: Text(
                    AppLocalizations.of(context)!.sendFeedback,
                    style: const TextStyle(fontSize: 16),
                  ),
                  icon: const Icon(Icons.send),
                ),
              ),
            ),
            Container(
              alignment: AlignmentDirectional.topStart,
              child: Container(
                margin: const EdgeInsets.only(top: 0, bottom: 12),
                child: TextButton.icon(
                  onPressed: () async {
                    await launchUrl(
                      Uri.parse(
                          "https://github.com/mrquantumoff/quadrant/issues/new/choose"),
                    );
                  },
                  label: Text(
                    AppLocalizations.of(context)!.submitBugReport,
                    style: const TextStyle(fontSize: 16),
                  ),
                  icon: const Icon(Icons.bug_report),
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(mcFolder),
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    child: TextButton(
                      onPressed: () =>
                          overwriteMinecraftFolder(updateMinecraftFolderText),
                      child: Text(
                        AppLocalizations.of(context)!.overrideMinecraftFolder,
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    child: TextButton(
                      onPressed: () => clearMinecraftFolderOverwrite(
                          updateMinecraftFolderText),
                      child: Text(
                          AppLocalizations.of(context)!.resetMinecraftFolder),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsetsDirectional.only(
                      end: 12,
                    ),
                    child: Switch(
                      value: clipButtons,
                      onChanged: setClipButtons,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8.5),
                    child: Text(AppLocalizations.of(context)!.clipIcons),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 12),
                    child: Switch(
                      value: collectData,
                      onChanged: setCollectData,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8.5),
                    child: Text(
                      AppLocalizations.of(context)!.dataCollectionQuestionShort,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  child: TextButton.icon(
                    icon: const Icon(Icons.save),
                    onPressed: () => collectUserInfo(saveToFile: true),
                    label: Text(
                      AppLocalizations.of(context)!.collectData,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  child: TextButton.icon(
                    icon: const Icon(Icons.open_in_browser),
                    onPressed: () async {
                      await launchUrl(
                        Uri.parse(
                            "https://mrquantumoff.dev/projects/quadrant/analytics"),
                      );
                    },
                    label: Text(
                      AppLocalizations.of(context)!.viewPublicUsage(
                        AppLocalizations.of(context)!.productName,
                      ),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  child: TextButton.icon(
                    icon: const Icon(Icons.open_in_browser),
                    onPressed: () async {
                      if (GetStorage().read("collectUserData")) {
                        MachineIdAndOS info = await getMachineIdAndOs();

                        await launchUrl(
                          Uri.parse(
                              "https://mrquantumoff.dev/projects/quadrant/analytics/${info.machineId}"),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppLocalizations.of(context)!.invalidData,
                            ),
                          ),
                        );
                      }
                    },
                    label: Text(
                      AppLocalizations.of(context)!.viewYourUsageData,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  child: TextButton.icon(
                    icon: const Icon(Icons.delete_forever),
                    style: const ButtonStyle(
                      iconColor:
                          WidgetStatePropertyAll<Color>(Colors.redAccent),
                    ),
                    onPressed: () {
                      try {
                        deleteUsageInfo();
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(AppLocalizations.of(context)!
                                .failedToDeleteUsageInfo),
                          ),
                        );
                      }
                    },
                    label: Text(
                      AppLocalizations.of(context)!.deleteYourUsageData,
                      style: const TextStyle(
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 12),
                    child: Switch(
                      value: curseForge,
                      onChanged: setCurseForge,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8.5),
                    child: const Text("CurseForge"),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 12),
                    child: Switch(
                      value: modrinth,
                      onChanged: setModrinth,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8.5),
                    child: const Text("Modrinth"),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 12),
                    child: Switch(
                      value: devMode,
                      onChanged: setDevMode,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8.5),
                    child: Text(AppLocalizations.of(context)!.devMode),
                  ),
                ],
              ),
            ),
            devMode
                ? Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: SizedBox(
                      width: 150,
                      child: devMode
                          ? Column(
                              children: [
                                TextField(
                                  onSubmitted: (value) async {
                                    const storage = FlutterSecureStorage();
                                    await storage.write(
                                      key: "quadrant_id_token",
                                      value: value,
                                    );
                                    debugPrint("Set token to $value");
                                  },
                                  decoration: const InputDecoration(
                                    label: Text("Quadrant ID Token override"),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ],
                            )
                          : Container(),
                    ),
                  )
                : Container(),
            Container(
              margin: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 12),
                    child: Switch(
                      value: rssFeeds,
                      onChanged: setRSSFeeds,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8.5),
                    child: Text(AppLocalizations.of(context)!.rssFeeds),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 12),
                    child: Switch(
                      value: silentNews,
                      onChanged: setSilentNews,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8.5),
                    child: Text(AppLocalizations.of(context)!.silentNews),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 12),
                    child: Switch(
                      value: showUnupgradeableMods,
                      onChanged: setShowUnupgradeableMods,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8.5),
                    child: Text(
                        AppLocalizations.of(context)!.showUnupgradeableMods),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 12),
                    child: Switch(
                      value: extendedNavigation,
                      onChanged: setExtendedNavigation,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8.5),
                    child:
                        Text(AppLocalizations.of(context)!.extendedNavigation),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 12),
                    child: Switch(
                      value: experimentalFeatures,
                      onChanged: setExpFeatures,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8.5),
                    child: Text(
                      AppLocalizations.of(context)!.experimentalFeatures,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 12),
                    child: Switch(
                      value: autoQuadrantSync,
                      onChanged: setAutoQuadrantSync,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8.5),
                    child: Text(
                      AppLocalizations.of(context)!.autoQuadrantSync,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
