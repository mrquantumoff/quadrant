import 'dart:io';

import 'package:clipboard/clipboard.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:quadrant/other/backend.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:quadrant/pages/modpack_importer/import_modpacks/synced_modpack.dart';
import 'package:quadrant/pages/web/mod/loading_mod.dart';
import 'package:quadrant/pages/web/mod/mod.dart';

import 'package:quadrant/pages/web/generate_user_agent.dart';

class ShareModpacksPage extends StatefulWidget {
  const ShareModpacksPage({super.key});

  @override
  State<ShareModpacksPage> createState() => _ShareModpacksPageState();
}

class DownloadedMod {
  DownloadedMod({required this.bytes, required this.file});
  List<int> bytes = [];
  File file;
}

class _ShareModpacksPageState extends State<ShareModpacksPage>
    with TickerProviderStateMixin {
  List<Widget> mods = [];
  List<String> modDownloadUrls = [];
  String modLoader = "";
  String version = "";
  String modpack = "";
  double progressValue = 0;
  int otherModCount = 0;
  bool isLoading = false;
  String modConfig = "";
  bool switchTabsBack = false;

  late TabController tabController;

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 2, vsync: this);
  }

  TextEditingController modpackEntryController = TextEditingController();
  void setProgressValue(double value) {
    setState(() {
      progressValue = value;
    });
  }

  void getMods(String rawFile, {bool switchTabs = false}) async {
    setState(() {
      mods = [];
      modDownloadUrls = [];
      modLoader = "";
      version = "";
      modpack = "";
      modConfig = rawFile;
    });

    if (switchTabs) {
      tabController.animateTo(0);
      setState(() {
        isLoading = true;
      });
      switchTabsBack = switchTabs;
    }

    try {
      Map jsonFile = json.decode(rawFile);
      if (jsonFile["modLoader"] == null ||
          jsonFile["version"] == null ||
          jsonFile["mods"] == null ||
          jsonFile["name"] == null) {
        setState(() {
          isLoading = false;
        });
        debugPrint("Invalid data 1");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.invalidData,
            ),
          ),
        );
        return;
      }
      modLoader = jsonFile["modLoader"];
      version = jsonFile["version"];
      modpack = jsonFile["name"];
      List<dynamic> sourceMods = jsonFile["mods"];
      List<Widget> newMods = [];
      try {
        for (var mod in sourceMods) {
          String id = mod["id"];
          String downloadUrl = mod["downloadUrl"];
          String rawSource = mod["source"];
          late ModSource source;
          if (rawSource == "ModSource.curseForge") {
            source = ModSource.curseForge;
          } else if (rawSource == "ModSource.modRinth") {
            source = ModSource.modRinth;
          } else {
            source = ModSource.online;
          }
          if (source == ModSource.curseForge || source == ModSource.modRinth) {
            LoadingMod mod =
                LoadingMod(modId: id, source: source, downloadable: false);
            newMods.add(mod);
          }
          if (source == ModSource.online) {
            otherModCount += 1;
          }
          modDownloadUrls.add(downloadUrl);
        }
      } catch (e) {
        debugPrint(e.toString());
        setState(() {
          isLoading = false;
        });
        return;
      }
      setState(() {
        isLoading = false;

        mods = newMods;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      debugPrint("Invalid data 2, $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.invalidData,
          ),
        ),
      );
    }
  }

  Future<List<SyncedModpack>> getSyncedModpacks(String reload) async {
    const storage = FlutterSecureStorage();
    String? token = await storage.read(key: "quadrant_id_token");
    if (token == null) {
      throw Exception(AppLocalizations.of(context)!.noQuadrantID);
    }
    http.Response res = await http.get(
        Uri.parse("https://api.mrquantumoff.dev/api/v2/get/quadrant_sync"),
        headers: {
          "User-Agent": await generateUserAgent(),
          "Authorization": "Bearer $token"
        });

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
    List<SyncedModpack> syncedModpacks = [];
    List<dynamic> data = json.decode(res.body);
    for (var modpack in data) {
      syncedModpacks.add(
        SyncedModpack(
          modpackId: modpack["modpack_id"],
          name: modpack["name"],
          mods: modpack["mods"],
          mcVersion: modpack["mc_version"],
          modLoader: modpack["mod_loader"],
          lastSynced: modpack["last_synced"],
          reload: () {
            setReload(modpack["name"]);
          },
          token: token,
          getMods: getMods,
        ),
      );
    }

    syncedModpacks.sort(((a, b) {
      return b.lastSynced.compareTo(a.lastSynced);
    }));

    return syncedModpacks;
  }

  String reload = "";

  void setReload(String newReload) {
    setState(() {
      reload = newReload;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.importMods),
        bottom: TabBar(
          controller: tabController,
          tabs: [
            Tab(
              child: Text(AppLocalizations.of(context)!.importMods),
            ),
            const Tab(child: Text("Quadrant Sync")),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: [
          Center(
            child: isLoading
                ? const CircularProgressIndicator()
                : ListView(
                    shrinkWrap: true,
                    children: (mods.isEmpty && otherModCount == 0)
                        ? [
                            Center(
                              child: Text(
                                  AppLocalizations.of(context)!.manualInput),
                            ),
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox(
                                  width: 960,
                                  child: TextField(
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                    ),
                                    controller: modpackEntryController,
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    child: FilledButton.tonal(
                                      onPressed: () async {
                                        setState(() {
                                          modDownloadUrls = [];
                                          mods = [];
                                          isLoading = true;
                                          otherModCount = 0;
                                        });
                                        FilePickerResult? filePickerResult =
                                            await FilePicker.platform.pickFiles(
                                          allowMultiple: false,
                                          allowedExtensions: ["json"],
                                          withData: true,
                                          lockParentWindow: true,
                                        );
                                        if (filePickerResult == null) {
                                          setState(() {
                                            isLoading = false;
                                          });
                                          return;
                                        }
                                        PlatformFile platformFile =
                                            filePickerResult.files[0];
                                        if (platformFile.path == null ||
                                            !platformFile.name
                                                .endsWith(".json")) {
                                          setState(() {
                                            isLoading = false;
                                          });
                                          debugPrint("Invalid data 3");

                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                AppLocalizations.of(context)!
                                                    .invalidData,
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        File file = File(platformFile.path!);
                                        String rawFile =
                                            await file.readAsString();
                                        getMods(rawFile);
                                      },
                                      child: Text(
                                        AppLocalizations.of(context)!.openFile,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    child: FilledButton.tonal(
                                      child: Text(
                                        AppLocalizations.of(context)!.paste,
                                      ),
                                      onPressed: () async {
                                        String value =
                                            await FlutterClipboard.paste();
                                        setState(
                                          () {
                                            modpackEntryController.text = value;
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    child: FilledButton(
                                      child: Text(
                                        AppLocalizations.of(context)!.download,
                                      ),
                                      onPressed: () async {
                                        setState(() {
                                          isLoading = true;
                                        });
                                        var res = await http.get(Uri.parse(
                                            "https://api.mrquantumoff.dev/api/v2/get/quadrant_share?code=${String.fromCharCodes(modpackEntryController.text.codeUnits)}"));
                                        if (res.statusCode != 200) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                AppLocalizations.of(context)!
                                                    .failedQuadrantShare,
                                              ),
                                            ),
                                          );
                                          setState(() {
                                            isLoading = false;
                                          });
                                          return;
                                        }
                                        var decoded = json.decode(res.body);
                                        debugPrint(decoded["mod_config"]);

                                        getMods(
                                          // Deep copying
                                          decoded["mod_config"],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ]
                        : [
                            Container(
                              height: 360,
                              margin: const EdgeInsets.only(
                                  bottom: 24, left: 120, right: 120),
                              child: GridView.extent(
                                maxCrossAxisExtent: 540,
                                childAspectRatio: 1.35,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                mainAxisSpacing: 24,
                                children: mods,
                              ),
                            ),
                            Center(
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  children: [
                                    Text(
                                      "$modpack | $modLoader | $version | ${AppLocalizations.of(context)!.modCount(mods.length)}",
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                    Text(
                                      AppLocalizations.of(context)!.otherMods(
                                        otherModCount,
                                      ),
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FilledButton.icon(
                                  onPressed: () async {
                                    List<DownloadedMod> downloadedMods = [];
                                    debugPrint("$modDownloadUrls");
                                    List<String> modpackFiles = [];

                                    Directory modpackDir = Directory(
                                        "${getMinecraftFolder().path}/modpacks/$modpack");
                                    if (modpackDir.existsSync()) {
                                      Stream<FileSystemEntity> installedMods =
                                          modpackDir.list(
                                              recursive: true,
                                              followLinks: true);
                                      await for (FileSystemEntity item
                                          in installedMods) {
                                        String fileName = item.path
                                            .replaceAll("\\", "/")
                                            .split("/")
                                            .last;
                                        if (fileName.endsWith(".json") ||
                                            (await FileSystemEntity.isDirectory(
                                                item.path))) {
                                          continue;
                                        }
                                        modpackFiles.add(
                                            item.path.replaceAll("\\", "/"));
                                      }
                                    }

                                    debugPrint("Modpack files: $modpackFiles");
                                    for (var downloadUrl in modDownloadUrls) {
                                      String modFileName =
                                          Uri.parse(downloadUrl)
                                              .pathSegments
                                              .last;
                                      File modDestFile = File(
                                          "${getMinecraftFolder().path}/modpacks/$modpack/$modFileName");
                                      if (modpackFiles.contains(modDestFile.path
                                          .replaceAll("\\", "/"))) {
                                        modpackFiles.remove(modDestFile.path
                                            .replaceAll("\\", "/"));
                                      }
                                      int modIndex =
                                          modDownloadUrls.indexOf(downloadUrl);

                                      if (modDestFile.existsSync()) {
                                        setProgressValue(
                                            modIndex / modDownloadUrls.length);
                                        continue;
                                      }

                                      final http.Response res = await http.get(
                                        Uri.parse(downloadUrl),
                                        headers: {
                                          "User-Agent":
                                              await generateUserAgent(),
                                        },
                                      );

                                      List<int> bytes = res.bodyBytes;
                                      setProgressValue(
                                          modIndex / modDownloadUrls.length);
                                      downloadedMods.add(
                                        DownloadedMod(
                                            bytes: bytes, file: modDestFile),
                                      );
                                    }

                                    for (String item in modpackFiles) {
                                      File itemFile = File(item);
                                      if (itemFile.existsSync()) {
                                        await itemFile.delete();
                                      }
                                    }

                                    if (!await modpackDir.exists()) {
                                      await modpackDir.create(recursive: true);
                                    }
                                    bool success = true;
                                    for (DownloadedMod dlMod
                                        in downloadedMods) {
                                      try {
                                        if (dlMod.file.existsSync()) {
                                          await dlMod.file.delete();
                                        }
                                        await dlMod.file
                                            .create(recursive: true);
                                        await dlMod.file
                                            .writeAsBytes(dlMod.bytes);
                                      } catch (e) {
                                        debugPrint(e.toString());
                                        success = false;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              AppLocalizations.of(context)!
                                                  .downloadFail,
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                    if (success) {
                                      File modpackConfig = File(
                                          "${modpackDir.path}/modConfig.json");
                                      debugPrint(modpackConfig.path);
                                      if (modpackConfig.existsSync()) {
                                        await modpackConfig.delete();
                                      }
                                      await modpackConfig.create();

                                      await modpackConfig
                                          .writeAsString(modConfig);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(context)!
                                                .downloadSuccess,
                                          ),
                                        ),
                                      );
                                      if (switchTabsBack) {
                                        tabController.animateTo(1);
                                        switchTabsBack = false;
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.download),
                                  label: Text(
                                    AppLocalizations.of(context)!.download,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              margin: const EdgeInsets.symmetric(
                                  vertical: 25, horizontal: 48),
                              child: LinearProgressIndicator(
                                value: progressValue,
                              ),
                            ),
                          ],
                  ),
          ),
          Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 4, left: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.modpackSynced,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ],
                ),
              ),
              Center(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FutureBuilder(
                      future: getSyncedModpacks(reload),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return SizedBox(
                            height: 540,
                            child: ListView(
                              children: snapshot.data!,
                            ),
                          );
                        } else if (snapshot.hasError) {
                          return Column(
                            children: [
                              const Icon(Icons.error),
                              Text(
                                snapshot.error.toString(),
                                style: const TextStyle(
                                  fontSize: 18,
                                ),
                              )
                            ],
                          );
                        }
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
