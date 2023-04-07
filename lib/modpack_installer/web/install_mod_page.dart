// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mcmodpackmanager_reborn/backend.dart';
import "package:http/http.dart" as http;
import 'package:url_launcher/url_launcher.dart';
import '../web_sources.dart';
import 'generate_user_agent.dart';
import 'mod.dart';

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
  late TextEditingController apiFieldController;
  late TextEditingController modpackFieldController;
  late double progressValue;
  @override
  void initState() {
    super.initState();
    progressValue = 0;
    versionFieldController = TextEditingController();
    apiFieldController = TextEditingController();
    modpackFieldController = TextEditingController();
    areButttonsActive = true;
  }

  final String apiKey =
      const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");

  @override
  void dispose() {
    super.dispose();
    progressValue = 0;

    areButttonsActive = false;
  }

  setProgressValue(double newValue) {
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
    String desc = widget.mod.description;
    String displayName = widget.mod.name.length >= 36
        ? widget.mod.name.replaceRange(36, null, "...")
        : widget.mod.name;
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
                      widget.mod.downloadCount.toString(),
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
                  label: Text(AppLocalizations.of(context)!.chooseVersion),
                  width: 840,
                  enabled: (widget.installFileId == null),
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
                  enabled: (widget.modClass == ModClass.mod &&
                      widget.installFileId == null),
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
                              if (areButttonsActive) {
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
                                      (GetStorage().read("modrinthUsage") ??
                                              0) +
                                          1);
                                }
                                bool isNormalNoVersion =
                                    (version.trim() == "" ||
                                        ((api.trim() == "" ||
                                                modpack.trim() == "") &&
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
                                  if ((widget.modClass ==
                                              ModClass.resourcePack ||
                                          widget.modClass ==
                                              ModClass.shaderPack) &&
                                      widget.installFileId == null) {
                                    getFilesUri = Uri.parse(
                                        "https://api.curseforge.com/v1/mods/${widget.mod.id}/files?gameVersion=${version.trim()}&sortOrder=desc");
                                  } else if (widget.installFileId != null) {
                                    getFilesUri = Uri.parse(
                                        "https://api.curseforge.com/v1/mods/${widget.mod.id}/files/${widget.installFileId}");
                                  }
                                  debugPrint(
                                      "Installing mods url: $getFilesUri");
                                  http.Response response =
                                      await http.get(getFilesUri, headers: {
                                    "User-Agent": await generateUserAgent(),
                                    "X-API-Key": apiKey,
                                  });
                                  Map responseJson = json.decode(response.body);
                                  if (widget.installFileId == null) {
                                    if ((responseJson["data"]
                                            as List<dynamic>) ==
                                        []) {
                                      setAreButtonsActive(true);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
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
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
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
                                  late ModFile mod;
                                  if (widget.installFileId != null) {
                                    versionFieldController.text =
                                        responseJson["data"]["gameVersions"][0];

                                    mod = ModFile(
                                      downloadUrl: responseJson["data"]
                                          ["downloadUrl"],
                                      fileName: responseJson["data"]
                                          ["fileName"],
                                      gameVersions: [],
                                      fileDate: DateTime.parse(
                                        responseJson["data"]["fileDate"],
                                      ),
                                    );
                                  }

                                  if (widget.installFileId == null) {
                                    mod = fileMod[0];
                                  }
                                  String modDownloadUrl = mod.downloadUrl;

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
                                      "${getMinecraftFolder().path}/modpacks/$modpack/${mod.fileName}");
                                  if (widget.modClass ==
                                      ModClass.resourcePack) {
                                    modDestFile = File(
                                        "${getMinecraftFolder().path}/resourcepacks/${mod.fileName}");
                                  } else if (widget.modClass ==
                                      ModClass.shaderPack) {
                                    modDestFile = File(
                                        "${getMinecraftFolder().path}/shaderpacks/${mod.fileName}");
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

                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              AppLocalizations.of(context)!
                                                  .downloadSuccess),
                                        ),
                                      );
                                    },
                                    onError: (e) {
                                      debugPrint(e);
                                    },
                                    cancelOnError: true,
                                  );
                                } else {
                                  Uri getFilesUri = Uri.parse(
                                      "https://api.modrinth.com/v2/project/${widget.mod.id}/version?loaders=[\"${api.toLowerCase()}\"]&game_versions=[\"$version\"]");
                                  if (widget.modClass ==
                                          ModClass.resourcePack ||
                                      widget.modClass == ModClass.shaderPack) {
                                    getFilesUri = Uri.parse(
                                        "https://api.modrinth.com/v2/project/${widget.mod.id}/version?game_versions=[\"$version\"]");
                                  }
                                  debugPrint(
                                      "Installing mods url: $getFilesUri");
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
                                    setAreButtonsActive(true);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          AppLocalizations.of(context)!
                                              .noVersion,
                                        ),
                                      ),
                                    );

                                    return;
                                  }
                                  for (var mod in (responseJson[0]["files"])) {
                                    bool primary = mod["primary"];
                                    if (!primary) {
                                      continue;
                                    }
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
                                  var mod = fileMod[0];
                                  var request = http.Request(
                                    "GET",
                                    Uri.parse(mod.downloadUrl),
                                  );
                                  final http.StreamedResponse streamedResponse =
                                      await UserAgentClient(
                                              await generateUserAgent(),
                                              http.Client())
                                          .send(request);
                                  final contentLength =
                                      streamedResponse.contentLength;

                                  File modDestFile = File(
                                      "${getMinecraftFolder().path}/modpacks/$modpack/${mod.fileName}");
                                  if (widget.modClass ==
                                      ModClass.resourcePack) {
                                    modDestFile = File(
                                        "${getMinecraftFolder().path}/resourcepacks/${mod.fileName}");
                                  } else if (widget.modClass ==
                                      ModClass.shaderPack) {
                                    modDestFile = File(
                                        "${getMinecraftFolder().path}/shaderpacks/${mod.fileName}");
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
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              AppLocalizations.of(context)!
                                                  .downloadSuccess),
                                        ),
                                      );
                                    },
                                    onError: (e) {
                                      debugPrint(e);
                                    },
                                    cancelOnError: true,
                                  );
                                }
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
                          rawUrl = "https://beta.curseforge.com/minecraft";
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
              )
            ],
          ),
        ],
      ),
    );
  }
}
