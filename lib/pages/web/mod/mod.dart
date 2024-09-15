// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';
import 'package:animations/animations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage_qnt/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';
import 'package:quadrant/pages/web/mod/install_mod_page.dart';
import 'package:quadrant/pages/web/web_sources.dart';
import 'package:url_launcher/url_launcher.dart';

enum ModSource { curseForge, modRinth, online }

enum ModClass {
  mod(6),
  resourcePack(12),
  shaderPack(4546);

  const ModClass(this.value);
  final int value;
}

class ModFile {
  ModFile({
    required this.downloadUrl,
    required this.fileName,
    required this.gameVersions,
    required this.fileDate,
  });
  String downloadUrl = "";
  String fileName = "";
  List<dynamic> gameVersions = [];
  DateTime? fileDate = DateTime.now();
}

// ignore: must_be_immutable
class Mod extends StatefulWidget {
  Mod({
    super.key,
    required this.name,
    required this.description,
    required this.modIconUrl,
    required this.id,
    required this.downloadCount,
    required this.setAreParentButtonsActive,
    required this.source,
    required this.modClass,
    required this.slug,
    required this.thumbnailUrl,
    required this.rawMod,
    this.downloadable = true,
    this.showPreVersion = false,
    this.preVersion = "",
    this.versionTarget = "",
    this.modpackToUpdate = "",
    this.newVersionUrl = "",
    this.deletable = false,
    this.autoInstall = false,
  });

  final String name;
  final String description;
  final String modIconUrl;
  final int downloadCount;
  final String id;
  final ModSource source;
  final ModClass modClass;
  final String slug;
  final bool downloadable;
  final bool showPreVersion;
  final bool deletable;
  final bool autoInstall;
  final String preVersion;
  final String newVersionUrl;
  final String modpackToUpdate;
  final String versionTarget;
  final List<String> thumbnailUrl;
  final Map rawMod;
  Function(bool) setAreParentButtonsActive;

  void install(
    BuildContext context,
    String version,
    String api,
    String modpack,
    Function(bool) setAreButtonsActive,
    String apiKey, {
    int? installFileId,
    Function(double)? setProgressValue,
  }) async {
    setAreButtonsActive(false);

    GetStorage().writeInMemory("lastUsedVersion", version);
    GetStorage().writeInMemory("lastUsedAPI", api);
    GetStorage().writeInMemory("lastUsedModpack", modpack);
    if (source == ModSource.curseForge) {
      GetStorage().write(
          "curseForgeUsage", (GetStorage().read("curseForgeUsage") ?? 0) + 1);
    } else {
      GetStorage().write(
          "modrinthUsage", (GetStorage().read("modrinthUsage") ?? 0) + 1);
    }
    bool isNormalNoVersion = (version.trim() == "" ||
        ((api.trim() == "" || modpack.trim() == "") &&
            modClass == ModClass.mod));
    if ((isNormalNoVersion && installFileId == null) ||
        (modpack.trim() == "" &&
            installFileId != null &&
            modClass == ModClass.mod)) {
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

    if (source == ModSource.curseForge) {
      Uri getFilesUri = Uri.parse(
          "https://api.curseforge.com/v1/mods/$id/files?gameVersion=${version.trim()}&sortOrder=desc&modLoaderType=${api.trim()}");
      if ((modClass == ModClass.resourcePack ||
              modClass == ModClass.shaderPack) &&
          installFileId == null) {
        getFilesUri = Uri.parse(
            "https://api.curseforge.com/v1/mods/$id/files?gameVersion=${version.trim()}&sortOrder=desc");
      } else if (installFileId != null) {
        getFilesUri = Uri.parse(
            "https://api.curseforge.com/v1/mods/$id/files/$installFileId");
      }
      debugPrint("Installing mods url: $getFilesUri");
      http.Response response = await http.get(getFilesUri, headers: {
        "User-Agent": await generateUserAgent(),
        "X-API-Key": apiKey,
      });
      Map responseJson = json.decode(utf8.decode(response.bodyBytes));
      if (installFileId == null) {
        if ((responseJson["data"] as List<dynamic>) == []) {
          setAreButtonsActive(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.noVersion,
              ),
            ),
          );
        }
        for (var mod in responseJson["data"]) {
          try {
            DateTime fileDate = DateTime.parse(mod["fileDate"]);
            List<dynamic> gameVersions = mod["gameVersions"];
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
          (a, b) => b.fileDate!.compareTo(a.fileDate!),
        );
        debugPrint(fileMod.toString());
        if (fileMod.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.noVersion),
            ),
          );
          setAreButtonsActive(true);

          return;
        }
      }
      late ModFile currentModFile;
      if (installFileId != null) {
        currentModFile = ModFile(
          downloadUrl: responseJson["data"]["downloadUrl"],
          fileName: responseJson["data"]["fileName"],
          gameVersions: [],
          fileDate: DateTime.parse(
            responseJson["data"]["fileDate"],
          ),
        );
      }

      if (installFileId == null) {
        currentModFile = fileMod[0];
      }
      String modDownloadUrl = currentModFile.downloadUrl;

      var request = http.Request(
        "GET",
        Uri.parse(modDownloadUrl),
      );
      final http.StreamedResponse streamedResponse =
          await UserAgentClient(await generateUserAgent(), http.Client())
              .send(request);
      final contentLength = streamedResponse.contentLength;

      File modDestFile = File(
          "${getMinecraftFolder().path}/modpacks/$modpack/${currentModFile.fileName}");
      if (modClass == ModClass.resourcePack) {
        modDestFile = File(
            "${getMinecraftFolder().path}/resourcepacks/${currentModFile.fileName}");
      } else if (modClass == ModClass.shaderPack) {
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
          if (setProgressValue != null) {
            setProgressValue(downloadedLength / (contentLength ?? 1));
          }
        },
        onDone: () async {
          await modDestFile.writeAsBytes(bytes, flush: true);
          if (setProgressValue != null) {
            setProgressValue(1);
          }
          debugPrint("Downloaded");
          setAreButtonsActive(true);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.downloadSuccess),
            ),
          );
          File modpackConfigFile = File(
              "${getMinecraftFolder().path}/modpacks/$modpack/modConfig.json");

          debugPrint(modpackConfigFile.path);
          if (!modpackConfigFile.existsSync()) {
            return;
          }
          String modpackConfigRaw = await modpackConfigFile.readAsString();
          Map modpackConfig = json.decode(modpackConfigRaw);
          List<dynamic> modsIndex = modpackConfig["mods"] ?? [];
          bool doesExist = false;
          for (Map<dynamic, dynamic> modItem in modsIndex) {
            if (modItem["id"] == id) {
              doesExist = true;
              return;
            }
          }
          if (doesExist) {
            return;
          }
          modsIndex.add(
            {
              "id": id,
              "source": source.toString(),
              "downloadUrl": currentModFile.downloadUrl,
            },
          );
          Map newModpackConfig = {
            "modLoader": modpackConfig["modLoader"],
            "version": modpackConfig["version"],
            "mods": modsIndex,
            "name": modpackConfig["name"]
          };
          String finalModpackConfig = json.encode(newModpackConfig);
          debugPrint(finalModpackConfig);

          await modpackConfigFile.writeAsString(finalModpackConfig);
          File modpackSyncFile = File(
              "${getMinecraftFolder().path}/modpacks/$modpack/quadrantSync.json");
          if (GetStorage().read("autoQuadrantSync") == true &&
              modpackSyncFile.existsSync()) {
            await syncModpack(context, finalModpackConfig, false);
          }
        },
        onError: (e) {
          debugPrint(e);
        },
        cancelOnError: true,
      );
    } else {
      Uri getFilesUri = Uri.parse(
          "https://api.modrinth.com/v2/project/$id/version?loaders=[\"${api.toLowerCase()}\"]&game_versions=[\"$version\"]");
      if (modClass == ModClass.resourcePack ||
          modClass == ModClass.shaderPack) {
        getFilesUri = Uri.parse(
            "https://api.modrinth.com/v2/project/$id/version?game_versions=[\"$version\"]");
      }
      debugPrint("Installing mods url: $getFilesUri");
      setAreButtonsActive(false);
      http.Response response = await http.get(getFilesUri, headers: {
        "User-Agent": await generateUserAgent(),
      });
      dynamic responseJson = json.decode(utf8.decode(response.bodyBytes));
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
            content: Text(AppLocalizations.of(context)!.noVersion),
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
      List<int> bytes = [];

      FileInfo? cachedFile = await QuadrantCacheManager.instance
          .getFileFromCache(currentModFile.downloadUrl);
      if (cachedFile != null) {
        bytes = await cachedFile.file.readAsBytes();
      }

      File modDestFile = File(
          "${getMinecraftFolder().path}/modpacks/$modpack/${currentModFile.fileName}");
      if (modClass == ModClass.resourcePack) {
        modDestFile = File(
            "${getMinecraftFolder().path}/resourcepacks/${currentModFile.fileName}");
      } else if (modClass == ModClass.shaderPack) {
        modDestFile = File(
            "${getMinecraftFolder().path}/shaderpacks/${currentModFile.fileName}");
      }
      if (await modDestFile.exists()) {
        modDestFile.delete();
      }
      await modDestFile.create(recursive: true);
      debugPrint(modDestFile.path);
      void done() async {
        await modDestFile.writeAsBytes(bytes, flush: true);
        await QuadrantCacheManager.instance
            .putFile(currentModFile.downloadUrl, Uint8List.fromList(bytes));
        if (setProgressValue != null) {
          setProgressValue(1);
        }
        debugPrint("Downloaded");
        setAreButtonsActive(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.downloadSuccess),
          ),
        );
        File modpackConfigFile = File(
            "${getMinecraftFolder().path}/modpacks/$modpack/modConfig.json");
        debugPrint(modpackConfigFile.path);
        if (!modpackConfigFile.existsSync()) {
          return;
        }
        String modpackConfigRaw = await modpackConfigFile.readAsString();
        Map modpackConfig = json.decode(modpackConfigRaw);
        List<dynamic> modsIndex = modpackConfig["mods"] ?? [];
        bool doesExist = false;
        for (Map<dynamic, dynamic> modItem in modsIndex) {
          if ((modItem["id"] ?? "") == id) {
            doesExist = true;
            return;
          }
        }
        if (doesExist) {
          return;
        }
        modsIndex.add(
          {
            "id": id,
            "source": source.toString(),
            "downloadUrl": currentModFile.downloadUrl,
          },
        );
        Map newModpackConfig = {
          "modLoader": modpackConfig["modLoader"],
          "version": modpackConfig["version"],
          "mods": modsIndex,
          "name": modpackConfig["name"],
        };
        String finalModpackConfig = json.encode(newModpackConfig);
        debugPrint(finalModpackConfig);

        await modpackConfigFile.writeAsString(finalModpackConfig);
        File modpackSyncFile = File(
            "${getMinecraftFolder().path}/modpacks/$modpack/quadrantSync.json");
        if (GetStorage().read("autoQuadrantSync") == true &&
            modpackSyncFile.existsSync()) {
          await syncModpack(context, finalModpackConfig, false);
        }
      }

      if (bytes.isNotEmpty) {
        debugPrint("Using cached mod");
        done();
        return;
      }

      final http.StreamedResponse streamedResponse =
          await UserAgentClient(await generateUserAgent(), http.Client())
              .send(request);
      final contentLength = streamedResponse.contentLength;

      streamedResponse.stream.listen(
        (List<int> newBytes) {
          bytes.addAll(newBytes);
          final downloadedLength = bytes.length;
          if (setProgressValue != null) {
            setProgressValue(downloadedLength / (contentLength ?? 1));
          }
        },
        onDone: done,
        onError: (e) {
          debugPrint(e);
        },
        cancelOnError: true,
      );
    }
  }

  @override
  State<Mod> createState() => _ModState();
}

class _ModState extends State<Mod> with AutomaticKeepAliveClientMixin {
  late bool areButttonsActive;
  late bool hide;
  late bool showUpdateButton;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    areButttonsActive = true;
    showUpdateButton = true;
    hide = false;
  }

  List<DropdownMenuEntry> versionItems = [];
  List<DropdownMenuEntry> modpackItems = [];

  void updateModpackInfo() async {
    try {
      List<DropdownMenuEntry> versions = await getVersionsEntries();

      versionItems = versions;

      List<String> modpacks = getModpacks(hideFree: false);

      for (var modpack in modpacks) {
        modpackItems.add(
          DropdownMenuEntry(label: modpack, value: modpack),
        );
      }
    } catch (e) {
      debugPrint(e.toString());
    }
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
  void dispose() {
    super.dispose();
  }

  final String apiKey =
      const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");
  double progressValue = 0;

  void setProgressValue(double newValue) {
    setState(() {
      progressValue = newValue;
    });
  }

  @override
  Widget build(BuildContext context) {
    updateModpackInfo();

    super.build(context);
    debugPrint(widget.preVersion);
    String desc = widget.description.length >= 36
        ? widget.description.replaceRange(36, null, "...")
        : widget.description;
    String displayName = widget.name.length >= 24
        ? widget.name.replaceRange(24, null, "...")
        : widget.name;

    // If there are new lines in the description we hide them
    desc = desc.contains("\n") ? "${desc.split("\n").first}..." : desc;

    bool isNewVersionUrl = widget.newVersionUrl.trim().isEmpty;

    NumberFormat numberFormatter = NumberFormat.compact(
        explicitSign: false, locale: AppLocalizations.of(context)!.localeName);
    if (((widget.showPreVersion && isNewVersionUrl) &&
        GetStorage().read("showUnupgradeableMods") == false)) {
      return Container();
    }

    if (hide) {
      return Container();
    }
    bool installable = true;

    String modpack = GetStorage().read("lastUsedModpack") ?? "";
    try {
      File modConfigFile =
          File("${getMinecraftFolder().path}/modpacks/$modpack/modConfig.json");
      if (!widget.autoInstall) {
        modConfigFile =
            File("${getMinecraftFolder().path}/mods/modConfig.json");
      }
      if (modConfigFile.existsSync()) {
        Map modConfig = json.decode(modConfigFile.readAsStringSync());
        List<dynamic> mods = modConfig["mods"];
        for (dynamic mod in mods) {
          if (mod["id"] == widget.id) {
            installable = false;
            break;
          }
        }
      }
    } catch (e) {}

    return Visibility.maintain(
      child: Animate(
        effects: [
          FadeEffect(
            duration: 400.ms,
          ),
          BlurEffect(
            delay: 200.ms,
            duration: 300.ms,
            end: const Offset(0, 0),
            begin: const Offset(10, 10),
          ),
        ],
        child: OpenContainer(
          closedBuilder: (context, action) {
            return Card.outlined(
              // elevation: 12,
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 0, vertical: 0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                              GetStorage().read("clipIcons") == true ? 80 : 0),
                          child: CachedNetworkImage(
                            cacheManager: QuadrantImageCacheManager.instance,
                            imageUrl: widget.modIconUrl.trim().isEmpty
                                ? "https://github.com/mrquantumoff/quadrant/raw/master/assets/icons/logo256.png"
                                : widget.modIconUrl.trim(),
                            progressIndicatorBuilder:
                                (context, url, downloadProgress) =>
                                    CircularProgressIndicator(
                                        value: downloadProgress.progress),
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.error),
                            alignment: Alignment.centerRight,
                            height: 64,
                            width: 64,
                          ),
                        ),
                      ),
                      Container(
                        margin: EdgeInsets.only(
                            left: 0, top: widget.showPreVersion ? 24 : 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                FittedBox(
                                  fit: BoxFit.cover,
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontSize: 24,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              margin: const EdgeInsets.only(
                                  top: 6, left: 0, bottom: 0),
                              child: Text(
                                desc.trim(),
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 16),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(
                                  top: 4, bottom: 8, left: 0, right: 16),
                              child: Text(
                                getModpackTypeString(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.download,
                                    color: Colors.grey, size: 16.5),
                                Text(
                                  numberFormatter.format(widget.downloadCount),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                  widget.autoInstall
                      ? Container(
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: LinearProgressIndicator(
                            value: progressValue,
                          ),
                        )
                      : Container(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        margin:
                            const EdgeInsets.only(top: 8, bottom: 8, right: 8),
                        child: widget.downloadable && !widget.autoInstall
                            ? FilledButton.icon(
                                onPressed: () {
                                  if (GetStorage()
                                      .read("experimentalFeatures")) {
                                    action();
                                  } else {
                                    Get.to(
                                      () => InstallModPage(
                                        versions: versionItems,
                                        mod: widget,
                                        modpacks: modpackItems,
                                        source: widget.source,
                                        modClass: widget.modClass,
                                      ),
                                    );
                                  }
                                },
                                icon: installable
                                    ? const Icon(Icons.download)
                                    : const Icon(Icons.check_circle_outline),
                                label: Text(
                                  installable
                                      ? AppLocalizations.of(context)!.download
                                      : AppLocalizations.of(context)!.installed,
                                ),
                              )
                            : null,
                      ),
                      Container(
                        margin: widget.downloadable && widget.autoInstall
                            ? const EdgeInsets.only(top: 8, bottom: 8, right: 8)
                            : null,
                        child: widget.downloadable && widget.autoInstall
                            ? progressValue < 1 && installable
                                ? FilledButton.icon(
                                    onPressed: () async {
                                      String version =
                                          GetStorage().read("lastUsedVersion");
                                      String api =
                                          GetStorage().read("lastUsedAPI");
                                      String modpack =
                                          GetStorage().read("lastUsedModpack");
                                      widget.install(
                                        context,
                                        version,
                                        api,
                                        modpack,
                                        widget.setAreParentButtonsActive,
                                        apiKey,
                                        setProgressValue: setProgressValue,
                                      );
                                    },
                                    icon: const Icon(Icons.file_download),
                                    label: Text(
                                        AppLocalizations.of(context)!.download),
                                  )
                                : OutlinedButton.icon(
                                    onPressed: () {},
                                    label: Text(AppLocalizations.of(context)!
                                        .installed),
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.greenAccent,
                                    ),
                                  )
                            : null,
                      ),
                      Container(
                        margin: widget.deletable
                            ? const EdgeInsets.only(top: 8, bottom: 8, right: 8)
                            : null,
                        child: widget.deletable
                            ? FilledButton.icon(
                                onPressed: () async {
                                  widget.setAreParentButtonsActive(false);
                                  try {
                                    String fileName =
                                        Uri.decodeComponent(widget.preVersion);
                                    File modFile = File(
                                        "${getMinecraftFolder().path}/modpacks/${widget.modpackToUpdate}/$fileName");
                                    debugPrint(modFile.path);
                                    if (await modFile.exists()) {
                                      await modFile.delete(recursive: true);
                                    }
                                  } catch (e) {
                                    debugPrint(e.toString());
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          AppLocalizations.of(context)!
                                              .failedToDelete(
                                            e.toString(),
                                          ),
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  File modConfigFile = File(
                                      "${getMinecraftFolder().path}/modpacks/${widget.modpackToUpdate}/modConfig.json");
                                  String modConfigRaw =
                                      await modConfigFile.readAsString();
                                  Map modConfig = json.decode(modConfigRaw);

                                  List<dynamic> mods = modConfig["mods"];
                                  mods.removeWhere(
                                      (element) => element["id"] == widget.id);
                                  modConfig["mods"] = mods;
                                  String newModConfigRaw =
                                      json.encode(modConfig);
                                  await modConfigFile
                                      .writeAsString(newModConfigRaw);
                                  File modpackSyncFile = File(
                                      "${getMinecraftFolder().path}/modpacks/${widget.modpackToUpdate}/quadrantSync.json");
                                  if (GetStorage().read("autoQuadrantSync") ==
                                          true &&
                                      modpackSyncFile.existsSync()) {
                                    await syncModpack(
                                        context, newModConfigRaw, false);
                                  }
                                  widget.setAreParentButtonsActive(true);
                                },
                                icon: const Icon(Icons.delete),
                                label:
                                    Text(AppLocalizations.of(context)!.delete),
                              )
                            : null,
                      ),
                      Container(
                        margin: widget.showPreVersion
                            ? const EdgeInsets.symmetric(horizontal: 0)
                            : EdgeInsets.symmetric(
                                vertical: (showUpdateButton ? 20 : 50),
                                horizontal: 0),
                        child: !isNewVersionUrl || !areButttonsActive
                            ? showUpdateButton
                                ? Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    child: FilledButton.icon(
                                      onPressed: () async {
                                        setState(() {
                                          showUpdateButton = false;
                                          areButttonsActive = false;
                                        });
                                        File res = await QuadrantCacheManager
                                            .instance
                                            .getSingleFile(
                                                widget.newVersionUrl);
                                        Directory modpackFolder = Directory(
                                            "${getMinecraftFolder().path}/modpacks/${widget.modpackToUpdate}");
                                        File resFile = File(
                                            "${modpackFolder.path}/${widget.newVersionUrl.trim().split("/").last}");
                                        if (!await resFile.exists()) {
                                          await resFile.create(recursive: true);
                                        }
                                        await resFile.writeAsBytes(
                                          await res.readAsBytes(),
                                          flush: true,
                                          mode: FileMode.write,
                                        );
                                        File modConfig = File(
                                            "${modpackFolder.path}/modConfig.json");
                                        Map modConf = json.decode(
                                            (await modConfig.readAsString()));
                                        int modIndex = 0;

                                        for (var mod in modConf["mods"]) {
                                          if (mod["id"] != widget.id) {
                                            modIndex += 1;
                                          } else {
                                            modConf["mods"][modIndex]
                                                    ["downloadUrl"] =
                                                widget.newVersionUrl;
                                            break;
                                          }
                                        }
                                        String newConf = json.encode(modConf);
                                        await modConfig.writeAsString(newConf);

                                        File oldVer = File(
                                            "${modpackFolder.path}/${widget.preVersion}");
                                        if (await oldVer.exists()) {
                                          await oldVer.delete();
                                        }
                                        setState(() {
                                          hide = true;
                                        });
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                AppLocalizations.of(context)!
                                                    .downloadSuccess),
                                          ),
                                        );
                                        File modpackSyncFile = File(
                                            "${modpackFolder.path}/quadrantSync.json");
                                        if (GetStorage()
                                                    .read("autoQuadrantSync") ==
                                                true &&
                                            modpackSyncFile.existsSync()) {
                                          await syncModpack(
                                              context, newConf, false);
                                        }
                                      },
                                      icon: const Icon(Icons.update),
                                      label: Text(
                                          AppLocalizations.of(context)!.update),
                                    ),
                                  )
                                : Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: SizedBox.fromSize(
                                      size: const Size(120, 2),
                                      child: const LinearProgressIndicator(),
                                    ),
                                  )
                            : Container(),
                      ),
                      Container(
                        margin: widget.downloadable
                            ? const EdgeInsets.symmetric(horizontal: 0)
                            : EdgeInsets.symmetric(
                                vertical: !widget.downloadable ? 8 : 0,
                              ),
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            final String slug = widget.slug;
                            String rawUrl = "";
                            String typeUrl = "";
                            if (widget.source == ModSource.curseForge) {
                              rawUrl = "https://curseforge.com/minecraft";
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
                          label:
                              Text(AppLocalizations.of(context)!.openInTheWeb),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    margin: widget.showPreVersion
                        ? const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 20)
                        : const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        widget.showPreVersion
                            ? Text(
                                "${widget.preVersion} -> ",
                              )
                            : Container(),
                        widget.showPreVersion
                            ? Text(widget.newVersionUrl.trim().split("/").last)
                            : Container(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
          openBuilder: (context, action) {
            if (!widget.downloadable) {
              return Container();
            }
            return InstallModPage(
              versions: versionItems,
              mod: widget,
              modpacks: modpackItems,
              source: widget.source,
              modClass: widget.modClass,
            );
          },
          closedColor: Colors.transparent,
          middleColor: Colors.transparent,
          openColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          closedElevation: 0,
          openElevation: 0,
          transitionDuration: Durations.long2,
          tappable:
              widget.downloadable && GetStorage().read("experimentalFeatures"),
        ),
      ),
    );
  }
}
