// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:mcmodpackmanager_reborn/backend.dart';
import "package:http/http.dart" as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:mcmodpackmanager_reborn/pages/web/web_sources.dart';
import 'package:mcmodpackmanager_reborn/pages/web/generate_user_agent.dart';
import 'package:mcmodpackmanager_reborn/pages/web/mod/mod.dart';

class InstallModPage extends StatefulWidget {
  const InstallModPage({
    super.key,
    required this.versions,
    required this.mod,
    required this.modpacks,
    required this.source,
    required this.modClass,
    this.installFileId,
  });

  final List<DropdownMenuEntry<dynamic>> versions;
  final List<DropdownMenuEntry<dynamic>> modpacks;
  final ModClass modClass;
  final ModSource source;
  final int? installFileId;

  final Mod mod;
  @override
  State<InstallModPage> createState() => _InstallModPageState();
}

class _InstallModPageState extends State<InstallModPage> {
  late bool areButttonsActive;
  late TextEditingController versionFieldController;
  late TextEditingController dependencyVersionFieldController;
  late TextEditingController apiFieldController;
  late TextEditingController modpackFieldController;
  late bool apiFieldEnabled;
  late bool versionFieldEnabled;
  late double progressValue;
  List<Widget> dependencies = [
    Container(
      margin: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
      child: const LinearProgressIndicator(),
    ),
  ];
  @override
  void initState() {
    super.initState();
    progressValue = 0;
    apiFieldEnabled =
        (widget.modClass == ModClass.mod && widget.installFileId == null);
    versionFieldEnabled = (widget.installFileId == null);
    versionFieldController = TextEditingController();
    apiFieldController = TextEditingController();
    dependencyVersionFieldController = TextEditingController();
    modpackFieldController = TextEditingController();
    areButttonsActive = true;
    getDeps();
  }

  void getDeps() async {
    List<Widget> newDeps = await getDependencies(
        widget.mod, GetStorage().read("lastUsedVersion") ?? "");
    setState(() {
      dependencies = newDeps;
    });
  }

  Future<List<Widget>> getDependencies(Mod mod, String modVersion) async {
    List<Mod> mods = [];

    debugPrint("Getting dependencies");

    if (mod.source == ModSource.curseForge) {
      http.Response response = await http.get(
        Uri.parse("https://api.curseforge.com/v1/mods/${mod.id}/files"),
        headers: {"User-Agent": await generateUserAgent(), "X-API-Key": apiKey},
      );
      final List<dynamic> responseJSON = json.decode(response.body)["data"];
      for (dynamic file in responseJSON) {
        if (!(file["gameVersions"] as List<dynamic>).contains(modVersion)) {
          continue;
        }

        final List<dynamic> dependencies = file["dependencies"];
        for (dynamic item in dependencies) {
          bool doesContainTheMod = false;
          for (var mod in mods) {
            if (mod.id == item["modId"].toString()) {
              doesContainTheMod = true;
            }
          }
          if (!doesContainTheMod) {
            debugPrint(item["modId"].toString());

            mods.add(
              await getMod(
                item["modId"].toString(),
                ModSource.curseForge,
                setAreButtonsActive,
              ),
            );
          }
        }
      }
    } else {
      debugPrint("Modrinth dependencies");
      http.Response response = await http.get(
        Uri.parse("https://api.modrinth.com/v2/project/${mod.id}/dependencies"),
        headers: {
          "User-Agent": await generateUserAgent(),
        },
      );
      final resJSON = json.decode(response.body);
      for (dynamic item in resJSON["projects"]) {
        mods.add(
          await getMod(item["id"], ModSource.modRinth, setAreButtonsActive),
        );
      }
    }
    if (mods.isEmpty) {
      return [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            AppLocalizations.of(context)!.emptyDependencies,
            style: const TextStyle(fontSize: 24),
          ),
        )
      ];
    }
    return mods;
  }

  final String apiKey =
      const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");

  @override
  void dispose() {
    super.dispose();
    progressValue = 0;

    areButttonsActive = false;
  }

  void setProgressValue(double newValue) {
    setState(() {
      progressValue = newValue;
    });
  }

  void setAreButtonsActive(bool value) {
    setState(() {
      areButttonsActive = value;
    });
  }

  String getModpackTypeString() {
    if (widget.modClass == ModClass.mod) {
      return AppLocalizations.of(context)!.mod(
        widget.source.name.toLowerCase(),
      );
    } else if (widget.modClass == ModClass.resourcePack) {
      return AppLocalizations.of(context)!.resourcePack(
        widget.source.name.toLowerCase(),
      );
    } else if (widget.modClass == ModClass.shaderPack) {
      return AppLocalizations.of(context)!.shaderPack(
        widget.source.name.toLowerCase(),
      );
    } else {
      return "Unknown";
    }
  }

  @override
  Widget build(BuildContext context) {
    void updateDependencies() async {
      List<Widget> mods = await getDependencies(
          widget.mod, dependencyVersionFieldController.text);
      setState(() {
        dependencies = mods;
      });
      debugPrint("Updating dependencies");
    }

    String desc = widget.mod.description;
    String displayName = widget.mod.name.length >= 36
        ? widget.mod.name.replaceRange(36, null, "...")
        : widget.mod.name;
    NumberFormat numberFormatter = NumberFormat.compact(
        explicitSign: false, locale: AppLocalizations.of(context)!.localeName);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: areButttonsActive
              ? () {
                  Get.back();
                }
              : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.of(context)!
                          .downloadIsAlreadyInProgress),
                    ),
                  );
                },
        ),
        title: Text(AppLocalizations.of(context)!.download),
      ),
      body: ListView(
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                  GetStorage().read("clipIcons") == true ? 80 : 0),
              child: Image(
                image: NetworkImage(widget.mod.modIconUrl),
                alignment: Alignment.centerRight,
                height: 96,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const CircularProgressIndicator();
                },
                width: 96,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, left: 12),
                child: Text(
                  displayName,
                  style: const TextStyle(fontSize: 32),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(left: 14, top: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.download, color: Colors.grey, size: 28),
                    Text(
                      numberFormatter.format(widget.mod.downloadCount),
                      style: const TextStyle(
                        fontSize: 24,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 256),
                child: SingleChildScrollView(
                  child: Text(
                    desc,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 8, left: 18),
                child: Text(
                  getModpackTypeString(),
                  style: const TextStyle(
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                child: DropdownMenu(
                  controller: versionFieldController,
                  dropdownMenuEntries: widget.versions,
                  initialSelection: widget.installFileId == null
                      ? GetStorage().read("lastUsedVersion")
                      : null,
                  onSelected: (val) {
                    setState(() {
                      dependencyVersionFieldController.text = val;
                    });
                    updateDependencies();
                  },
                  label: Text(AppLocalizations.of(context)!.chooseVersion),
                  width: 840,
                  enabled: versionFieldEnabled,
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                child: DropdownMenu(
                  label: Text(AppLocalizations.of(context)!.choosePreferredAPI),
                  controller: apiFieldController,
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(label: "Fabric", value: "Fabric"),
                    DropdownMenuEntry(label: "Forge", value: "Forge"),
                    DropdownMenuEntry(label: "Quilt", value: "Quilt"),
                    DropdownMenuEntry(label: "Rift", value: "Rift"),
                  ],
                  width: 840,
                  initialSelection: widget.installFileId == null
                      ? widget.modClass == ModClass.mod
                          ? GetStorage().read("lastUsedAPI")
                          : null
                      : null,
                  enabled: apiFieldEnabled,
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                child: DropdownMenu(
                  label: Text(AppLocalizations.of(context)!.chooseModpack),
                  controller: modpackFieldController,
                  dropdownMenuEntries: widget.modpacks,
                  initialSelection: widget.modClass == ModClass.mod
                      ? GetStorage().read("lastUsedModpack")
                      : null,
                  width: 840,
                  enabled: widget.modClass == ModClass.mod,
                  onSelected: (dynamic newValue) async {
                    String value = newValue.toString().trim();
                    Directory mcFolder = getMinecraftFolder();
                    File config =
                        File("${mcFolder.path}/modpacks/$value/modConfig.json");
                    if (!(await config.exists())) {
                      setState(() {
                        apiFieldEnabled = true;
                        versionFieldEnabled = true;
                      });
                      return;
                    }
                    String configJson = await config.readAsString();
                    Map modpackConf = json.decode(configJson);
                    setState(() {
                      apiFieldController.text = modpackConf["modLoader"];
                      versionFieldController.text = modpackConf["version"];
                      apiFieldEnabled = false;
                      versionFieldEnabled = false;
                    });
                  },
                ),
              ),
              Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
                child: LinearProgressIndicator(
                  value: progressValue,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: TextButton.icon(
                      onPressed: areButttonsActive
                          ? () async {
                              setAreButtonsActive(false);

                              String version =
                                  versionFieldController.value.text;
                              String api = apiFieldController.value.text;
                              String modpack =
                                  modpackFieldController.value.text;

                              GetStorage()
                                  .writeInMemory("lastUsedVersion", version);
                              GetStorage().writeInMemory("lastUsedAPI", api);
                              GetStorage()
                                  .writeInMemory("lastUsedModpack", modpack);
                              if (widget.mod.source == ModSource.curseForge) {
                                GetStorage().write(
                                    "curseForgeUsage",
                                    (GetStorage().read("curseForgeUsage") ??
                                            0) +
                                        1);
                              } else {
                                GetStorage().write(
                                    "modrinthUsage",
                                    (GetStorage().read("modrinthUsage") ?? 0) +
                                        1);
                              }
                              bool isNormalNoVersion = (version.trim() == "" ||
                                  ((api.trim() == "" || modpack.trim() == "") &&
                                      widget.modClass == ModClass.mod));
                              if ((isNormalNoVersion &&
                                      widget.installFileId == null) ||
                                  (modpack.trim() == "" &&
                                      widget.installFileId != null &&
                                      widget.modClass == ModClass.mod)) {
                                setAreButtonsActive(true);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      AppLocalizations.of(context)!.noVersion,
                                    ),
                                  ),
                                );
                                return;
                              }
                              debugPrint(api);
                              List<ModFile> fileMod = [];

                              if (widget.source == ModSource.curseForge) {
                                Uri getFilesUri = Uri.parse(
                                    "https://api.curseforge.com/v1/mods/${widget.mod.id}/files?gameVersion=${version.trim()}&sortOrder=desc&modLoaderType=${api.trim()}");
                                if ((widget.modClass == ModClass.resourcePack ||
                                        widget.modClass ==
                                            ModClass.shaderPack) &&
                                    widget.installFileId == null) {
                                  getFilesUri = Uri.parse(
                                      "https://api.curseforge.com/v1/mods/${widget.mod.id}/files?gameVersion=${version.trim()}&sortOrder=desc");
                                } else if (widget.installFileId != null) {
                                  getFilesUri = Uri.parse(
                                      "https://api.curseforge.com/v1/mods/${widget.mod.id}/files/${widget.installFileId}");
                                }
                                debugPrint("Installing mods url: $getFilesUri");
                                http.Response response =
                                    await http.get(getFilesUri, headers: {
                                  "User-Agent": await generateUserAgent(),
                                  "X-API-Key": apiKey,
                                });
                                Map responseJson = json.decode(response.body);
                                if (widget.installFileId == null) {
                                  if ((responseJson["data"] as List<dynamic>) ==
                                      []) {
                                    setAreButtonsActive(true);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          AppLocalizations.of(context)!
                                              .noVersion,
                                        ),
                                      ),
                                    );
                                  }
                                  for (var mod in responseJson["data"]) {
                                    try {
                                      DateTime fileDate =
                                          DateTime.parse(mod["fileDate"]);
                                      List<dynamic> gameVersions =
                                          mod["gameVersions"];
                                      String fileName = mod["fileName"];
                                      String downloadUrl = mod["downloadUrl"];

                                      fileMod.add(
                                        ModFile(
                                          fileDate: fileDate,
                                          gameVersions: gameVersions,
                                          fileName: fileName,
                                          downloadUrl: downloadUrl,
                                        ),
                                      );
                                    } catch (e) {
                                      debugPrint("No download url found");
                                    }
                                  }

                                  fileMod.sort(
                                    (a, b) =>
                                        b.fileDate!.compareTo(a.fileDate!),
                                  );
                                  debugPrint(fileMod.toString());
                                  if (fileMod.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            AppLocalizations.of(context)!
                                                .noVersion),
                                      ),
                                    );
                                    setAreButtonsActive(true);

                                    return;
                                  }
                                }
                                late ModFile currentModFile;
                                if (widget.installFileId != null) {
                                  versionFieldController.text =
                                      responseJson["data"]["gameVersions"][0];

                                  currentModFile = ModFile(
                                    downloadUrl: responseJson["data"]
                                        ["downloadUrl"],
                                    fileName: responseJson["data"]["fileName"],
                                    gameVersions: [],
                                    fileDate: DateTime.parse(
                                      responseJson["data"]["fileDate"],
                                    ),
                                  );
                                }

                                if (widget.installFileId == null) {
                                  currentModFile = fileMod[0];
                                }
                                String modDownloadUrl =
                                    currentModFile.downloadUrl;

                                var request = http.Request(
                                  "GET",
                                  Uri.parse(modDownloadUrl),
                                );
                                final http.StreamedResponse streamedResponse =
                                    await UserAgentClient(
                                            await generateUserAgent(),
                                            http.Client())
                                        .send(request);
                                final contentLength =
                                    streamedResponse.contentLength;

                                File modDestFile = File(
                                    "${getMinecraftFolder().path}/modpacks/$modpack/${currentModFile.fileName}");
                                if (widget.modClass == ModClass.resourcePack) {
                                  modDestFile = File(
                                      "${getMinecraftFolder().path}/resourcepacks/${currentModFile.fileName}");
                                } else if (widget.modClass ==
                                    ModClass.shaderPack) {
                                  modDestFile = File(
                                      "${getMinecraftFolder().path}/shaderpacks/${currentModFile.fileName}");
                                }
                                if (await modDestFile.exists()) {
                                  modDestFile.delete();
                                }
                                await modDestFile.create(recursive: true);
                                debugPrint(modDestFile.path);
                                List<int> bytes = [];
                                streamedResponse.stream.listen(
                                  (List<int> newBytes) {
                                    bytes.addAll(newBytes);
                                    final downloadedLength = bytes.length;
                                    setProgressValue(downloadedLength /
                                        (contentLength ?? 1));
                                  },
                                  onDone: () async {
                                    await modDestFile.writeAsBytes(bytes,
                                        flush: true);
                                    setProgressValue(1);
                                    debugPrint("Downloaded");
                                    setAreButtonsActive(true);

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            AppLocalizations.of(context)!
                                                .downloadSuccess),
                                      ),
                                    );
                                    File modpackConfigFile = File(
                                        "${getMinecraftFolder().path}/modpacks/$modpack/modConfig.json");
                                    debugPrint(modpackConfigFile.path);
                                    if (!modpackConfigFile.existsSync()) {
                                      return;
                                    }
                                    String modpackConfigRaw =
                                        await modpackConfigFile.readAsString();
                                    Map modpackConfig =
                                        json.decode(modpackConfigRaw);
                                    List<dynamic> modsIndex =
                                        modpackConfig["mods"] ?? [];
                                    bool doesExist = false;
                                    for (Map<dynamic, dynamic> modItem
                                        in modsIndex) {
                                      if (modItem["id"] == widget.mod.id) {
                                        doesExist = true;
                                        return;
                                      }
                                    }
                                    if (doesExist) {
                                      return;
                                    }
                                    modsIndex.add(
                                      {
                                        "id": widget.mod.id,
                                        "source": widget.source.toString(),
                                        "downloadUrl":
                                            currentModFile.downloadUrl,
                                      },
                                    );
                                    Map newModpackConfig = {
                                      "modLoader": modpackConfig["modLoader"],
                                      "version": modpackConfig["version"],
                                      "mods": modsIndex
                                    };
                                    String finalModpackConfig =
                                        json.encode(newModpackConfig);
                                    debugPrint(finalModpackConfig);
                                    await modpackConfigFile
                                        .writeAsString(finalModpackConfig);
                                  },
                                  onError: (e) {
                                    debugPrint(e);
                                  },
                                  cancelOnError: true,
                                );
                              } else {
                                Uri getFilesUri = Uri.parse(
                                    "https://api.modrinth.com/v2/project/${widget.mod.id}/version?loaders=[\"${api.toLowerCase()}\"]&game_versions=[\"$version\"]");
                                if (widget.modClass == ModClass.resourcePack ||
                                    widget.modClass == ModClass.shaderPack) {
                                  getFilesUri = Uri.parse(
                                      "https://api.modrinth.com/v2/project/${widget.mod.id}/version?game_versions=[\"$version\"]");
                                }
                                debugPrint("Installing mods url: $getFilesUri");
                                setAreButtonsActive(false);
                                http.Response response =
                                    await http.get(getFilesUri, headers: {
                                  "User-Agent": await generateUserAgent(),
                                });
                                dynamic responseJson =
                                    json.decode(response.body);
                                debugPrint(responseJson.toString());
                                List<ModFile> fileMod = [];

                                debugPrint(responseJson.toString());
                                try {
                                  if (responseJson[0]["files"] == null) {}
                                } catch (e) {
                                  debugPrint("Files are null");
                                  setAreButtonsActive(true);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppLocalizations.of(context)!.noVersion,
                                      ),
                                    ),
                                  );

                                  return;
                                }
                                for (var mod in (responseJson[0]["files"])) {
                                  // bool primary = mod["primary"];
                                  // if (!primary) {
                                  //   continue;
                                  // }
                                  String fileName = mod["filename"];
                                  String downloadUrl = mod["url"];

                                  fileMod.add(
                                    ModFile(
                                      fileDate: null,
                                      gameVersions: [],
                                      fileName: fileName,
                                      downloadUrl: downloadUrl,
                                    ),
                                  );
                                }

                                debugPrint(fileMod.toString());
                                if (fileMod.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          AppLocalizations.of(context)!
                                              .noVersion),
                                    ),
                                  );
                                  setAreButtonsActive(true);

                                  return;
                                }
                                var currentModFile = fileMod[0];
                                var request = http.Request(
                                  "GET",
                                  Uri.parse(currentModFile.downloadUrl),
                                );
                                final http.StreamedResponse streamedResponse =
                                    await UserAgentClient(
                                            await generateUserAgent(),
                                            http.Client())
                                        .send(request);
                                final contentLength =
                                    streamedResponse.contentLength;

                                File modDestFile = File(
                                    "${getMinecraftFolder().path}/modpacks/$modpack/${currentModFile.fileName}");
                                if (widget.modClass == ModClass.resourcePack) {
                                  modDestFile = File(
                                      "${getMinecraftFolder().path}/resourcepacks/${currentModFile.fileName}");
                                } else if (widget.modClass ==
                                    ModClass.shaderPack) {
                                  modDestFile = File(
                                      "${getMinecraftFolder().path}/shaderpacks/${currentModFile.fileName}");
                                }
                                if (await modDestFile.exists()) {
                                  modDestFile.delete();
                                }
                                await modDestFile.create(recursive: true);
                                debugPrint(modDestFile.path);
                                List<int> bytes = [];
                                streamedResponse.stream.listen(
                                  (List<int> newBytes) {
                                    bytes.addAll(newBytes);
                                    final downloadedLength = bytes.length;
                                    setProgressValue(downloadedLength /
                                        (contentLength ?? 1));
                                    debugPrint(progressValue.toString());
                                  },
                                  onDone: () async {
                                    await modDestFile.writeAsBytes(bytes,
                                        flush: true);
                                    setProgressValue(1);
                                    debugPrint("Downloaded");
                                    setAreButtonsActive(true);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            AppLocalizations.of(context)!
                                                .downloadSuccess),
                                      ),
                                    );
                                    File modpackConfigFile = File(
                                        "${getMinecraftFolder().path}/modpacks/$modpack/modConfig.json");
                                    debugPrint(modpackConfigFile.path);
                                    if (!modpackConfigFile.existsSync()) {
                                      return;
                                    }
                                    String modpackConfigRaw =
                                        await modpackConfigFile.readAsString();
                                    Map modpackConfig =
                                        json.decode(modpackConfigRaw);
                                    List<dynamic> modsIndex =
                                        modpackConfig["mods"] ?? [];
                                    bool doesExist = false;
                                    for (Map<dynamic, dynamic> modItem
                                        in modsIndex) {
                                      if ((modItem["id"] ?? "") ==
                                          widget.mod.id) {
                                        doesExist = true;
                                        return;
                                      }
                                    }
                                    if (doesExist) {
                                      return;
                                    }
                                    modsIndex.add(
                                      {
                                        "id": widget.mod.id,
                                        "source": widget.source.toString(),
                                        "downloadUrl":
                                            currentModFile.downloadUrl,
                                      },
                                    );
                                    Map newModpackConfig = {
                                      "modLoader": modpackConfig["modLoader"],
                                      "version": modpackConfig["version"],
                                      "mods": modsIndex,
                                      "name": modpackConfig["name"],
                                    };
                                    String finalModpackConfig =
                                        json.encode(newModpackConfig);
                                    debugPrint(finalModpackConfig);
                                    await modpackConfigFile
                                        .writeAsString(finalModpackConfig);
                                  },
                                  onError: (e) {
                                    debugPrint(e);
                                  },
                                  cancelOnError: true,
                                );
                              }
                            }
                          : null,
                      icon: const Icon(Icons.file_download),
                      label: Text(AppLocalizations.of(context)!.download),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: TextButton.icon(
                      onPressed: () async {
                        final String slug = widget.mod.slug;
                        String rawUrl = "";
                        String typeUrl = "";
                        if (widget.source == ModSource.curseForge) {
                          rawUrl = "https://www.curseforge.com/minecraft";
                          switch (widget.modClass) {
                            case ModClass.mod:
                              typeUrl = "mc-mods";
                              break;
                            case ModClass.resourcePack:
                              typeUrl = "texture-packs";
                              break;
                            case ModClass.shaderPack:
                              typeUrl = "customization";
                              break;
                          }
                        } else if (widget.source == ModSource.modRinth) {
                          rawUrl = "https://modrinth.com";
                          switch (widget.modClass) {
                            case ModClass.mod:
                              typeUrl = "mod";
                              break;
                            case ModClass.resourcePack:
                              typeUrl = "resourcepack";
                              break;
                            case ModClass.shaderPack:
                              typeUrl = "shader";
                              break;
                          }
                        }
                        rawUrl = "$rawUrl/$typeUrl/$slug";
                        Uri uri = Uri.parse(rawUrl);
                        launchUrl(uri);
                      },
                      icon: const Icon(Icons.open_in_browser),
                      label: Text(AppLocalizations.of(context)!.openInTheWeb),
                    ),
                  ),
                ],
              ),
              Center(
                child: Column(
                  children: [
                    Text(
                      AppLocalizations.of(context)!.dependencies,
                      style: const TextStyle(fontSize: 24),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      child: DropdownMenu(
                        controller: dependencyVersionFieldController,
                        dropdownMenuEntries: widget.versions,
                        initialSelection: widget.installFileId == null
                            ? GetStorage().read("lastUsedVersion")
                            : null,
                        label:
                            Text(AppLocalizations.of(context)!.chooseVersion),
                        width: 840,
                        enabled: versionFieldEnabled,
                        onSelected: (newValue) => updateDependencies(),
                      ),
                    ),
                    Column(
                      children: dependencies,
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
