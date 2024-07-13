// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage_qnt/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:quadrant/draggable_appbar.dart';
import 'package:quadrant/other/backend.dart';
import "package:http/http.dart" as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:quadrant/pages/web/web_sources.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';
import 'package:quadrant/pages/web/mod/mod.dart';

class ModMember extends StatelessWidget {
  const ModMember({super.key, required this.name, required this.url});

  final String name;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                name,
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(
                height: 12,
              ),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await launchUrl(Uri.parse(url));
                },
                label: Text(AppLocalizations.of(context)!.openInTheWeb),
                icon: const Icon(
                  Icons.open_in_browser,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

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
  late String lastVersion;

  List<Widget> dependencies = [
    Container(
      margin: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
      child: const Text(
        "...",
        style: TextStyle(fontSize: 72),
      ),
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
    lastVersion = widget.installFileId == null
        ? GetStorage().read("lastUsedVersion") ?? ""
        : "";
    getDeps();
  }

  void getDeps() async {
    List<Widget> newDeps = await getDependencies(
        widget.mod, GetStorage().read("lastUsedVersion") ?? "");
    setState(() {
      dependencies = newDeps;
    });
  }

  Future<List<Mod>> getDependencies(Mod mod, String modVersion) async {
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
      return [];
    }
    return mods;
  }

  final String apiKey =
      const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");

  @override
  void dispose() {
    super.dispose();
    progressValue = 0;
    apiFieldEnabled =
        (widget.modClass == ModClass.mod && widget.installFileId == null);
    versionFieldEnabled = (widget.installFileId == null);
    versionFieldController.dispose();
    apiFieldController.dispose();
    dependencyVersionFieldController.dispose();
    modpackFieldController.dispose();
    lastVersion = widget.installFileId == null
        ? GetStorage().read("lastUsedVersion") ?? ""
        : "";
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

  Future<List<ModMember>> getMembers() async {
    debugPrint("Getting members");

    List<ModMember> members = [];
    if (widget.mod.source == ModSource.curseForge) {
      List<dynamic> rawMembers = widget.mod.rawMod["authors"];
      for (dynamic author in rawMembers) {
        members.add(
          ModMember(
            name: author["name"],
            url: author["url"],
          ),
        );
      }
    } else if (widget.mod.source == ModSource.modRinth) {
      http.Response membersRes = await http.get(
        Uri.parse(
            "https://api.modrinth.com/v2/project/${widget.mod.id}/members"),
        headers: {
          "User-Agent": await generateUserAgent(),
        },
      );
      final List<dynamic> resJSON = json.decode(membersRes.body);
      resJSON.sort((a, b) => a["ordering"] - b["ordering"]);
      for (dynamic member in resJSON) {
        members.add(
          ModMember(
            name: member["user"]["username"],
            url: "https://modrinth.com/user/${member["user"]["id"]}",
          ),
        );
      }
    }
    return members;
  }

  @override
  Widget build(BuildContext context) {
    String license = "?";

    if (widget.mod.source == ModSource.modRinth) {
      debugPrint("${widget.mod.rawMod["license"]}");
      try {
        license = widget.mod.rawMod["license"]["id"];
      } catch (e) {
        license = widget.mod.rawMod["license"];
      }
    }

    void updateDependencies() async {
      List<Mod> mods = await getDependencies(
          widget.mod, dependencyVersionFieldController.text);
      setState(() {
        dependencies = mods;
      });
      debugPrint("Updating dependencies");
    }

    String desc = widget.mod.description;
    String displayName = widget.mod.name;
    NumberFormat numberFormatter = NumberFormat.compact(
      explicitSign: false,
      locale: AppLocalizations.of(context)!.localeName,
    );

    List<Widget> screenshots = [];

    for (String screenshot in widget.mod.thumbnailUrl) {
      screenshots.add(
        Image.network(
          screenshot,
          fit: BoxFit.contain,
        ),
      );
    }

    return Scaffold(
      appBar: DraggableAppBar(
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
      ),
      body: ListView(
        children: [
          Card.outlined(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 370,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    screenshots.isEmpty
                        ? Container()
                        : const SizedBox(
                            width: 12,
                          ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(left: 0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                  GetStorage().read("clipIcons") == true
                                      ? 80
                                      : 0),
                              child: Image(
                                image: NetworkImage(widget.mod.modIconUrl),
                                alignment: Alignment.centerRight,
                                height: 96,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
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
                                margin: const EdgeInsets.only(top: 12, left: 0),
                                child: Text(
                                  displayName,
                                  style: const TextStyle(fontSize: 32),
                                ),
                              ),
                              Container(
                                margin:
                                    const EdgeInsets.only(left: 16, top: 24),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.download,
                                        color: Colors.grey, size: 28),
                                    Text(
                                      numberFormatter
                                          .format(widget.mod.downloadCount),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 640),
                                child: Container(
                                  margin: const EdgeInsets.only(left: 0),
                                  child: SingleChildScrollView(
                                    child: Text(
                                      desc,
                                      style: const TextStyle(fontSize: 24),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.only(
                                  top: 8,
                                  bottom: 8,
                                ),
                                child: Text(
                                  getModpackTypeString(),
                                  style: const TextStyle(
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              license == "?"
                                  ? Container()
                                  : Container(
                                      margin: const EdgeInsets.only(
                                        bottom: 8,
                                      ),
                                      child: Text(
                                        AppLocalizations.of(context)!
                                            .licensedUnder(license),
                                        style: const TextStyle(
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    screenshots.isEmpty
                        ? Container()
                        : const SizedBox(
                            width: 128,
                          ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: screenshots.isEmpty
                          ? null
                          : Card.outlined(
                              margin: const EdgeInsets.only(right: 12),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 465),
                                child: CarouselSlider(
                                  options: CarouselOptions(
                                    pageSnapping: true,
                                    enableInfiniteScroll: true,
                                    enlargeFactor: 5,
                                    enlargeStrategy:
                                        CenterPageEnlargeStrategy.scale,
                                    scrollDirection: Axis.horizontal,
                                    height: 304,
                                    autoPlay: true,
                                  ),
                                  items: screenshots,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Text(
                "${AppLocalizations.of(context)!.owners}:",
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
          Card.outlined(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: FutureBuilder(
                future: getMembers(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  } else if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        snapshot.error.toString(),
                      ),
                    );
                  }

                  return Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 24),
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        shrinkWrap: true,
                        children: snapshot.data!,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  "${AppLocalizations.of(context)!.download}:",
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                child: DropdownMenu(
                  controller: versionFieldController,
                  dropdownMenuEntries: widget.versions,
                  initialSelection: widget.installFileId == null
                      ? GetStorage().read("lastUsedVersion")
                      : null,
                  enableSearch: true,
                  width: 840,
                  enableFilter: true,
                  onSelected: (val) {
                    setState(() {
                      dependencyVersionFieldController.text = val;
                    });
                    updateDependencies();
                  },
                  label: Text(AppLocalizations.of(context)!.chooseVersion),
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
                    DropdownMenuEntry(label: "NeoForge", value: "NeoForge"),
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
                    if (widget.installFileId != null) {
                      return;
                    }
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
                    child: FilledButton.icon(
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
                                      "mods": modsIndex,
                                      "name": modpackConfig["name"]
                                    };
                                    String finalModpackConfig =
                                        json.encode(newModpackConfig);
                                    debugPrint(finalModpackConfig);

                                    await modpackConfigFile
                                        .writeAsString(finalModpackConfig);
                                    File modpackSyncFile = File(
                                        "${getMinecraftFolder().path}/modpacks/$modpack/quadrantSync.json");
                                    if (GetStorage().read("autoQuadrantSync") ==
                                            true &&
                                        modpackSyncFile.existsSync()) {
                                      await syncModpack(
                                          context, finalModpackConfig, false);
                                    }
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
                                    File modpackSyncFile = File(
                                        "${getMinecraftFolder().path}/modpacks/$modpack/quadrantSync.json");
                                    if (GetStorage().read("autoQuadrantSync") ==
                                            true &&
                                        modpackSyncFile.existsSync()) {
                                      await syncModpack(
                                          context, finalModpackConfig, false);
                                    }
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
                    child: FilledButton.tonalIcon(
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
                        initialSelection: lastVersion,
                        label:
                            Text(AppLocalizations.of(context)!.chooseVersion),
                        width: 840,
                        enabled: versionFieldEnabled,
                        onSelected: (newValue) => updateDependencies(),
                      ),
                    ),
                    dependencies.isNotEmpty
                        ? SizedBox(
                            height: 720,
                            child: GridView.extent(
                              maxCrossAxisExtent: 540,
                              mainAxisSpacing: 15,
                              crossAxisSpacing: 0,
                              childAspectRatio: 1.35,
                              padding: const EdgeInsets.only(bottom: 0),
                              children: dependencies,
                            ),
                          )
                        : Container(
                            margin: const EdgeInsets.only(bottom: 64),
                            child: Center(
                              child: Text(
                                AppLocalizations.of(context)!.emptyDependencies,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
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
