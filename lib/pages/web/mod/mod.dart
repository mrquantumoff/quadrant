// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage_qnt/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';
import 'package:quadrant/pages/web/mod/install_mod_page.dart';
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
    this.downloadable = true,
    this.showPreVersion = false,
    this.preVersion = "",
    this.versionTarget = "",
    this.modpackToUpdate = "",
    this.newVersionUrl = "",
    this.deletable = false,
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
  final String preVersion;
  final String newVersionUrl;
  final String modpackToUpdate;
  final String versionTarget;
  Function(bool) setAreParentButtonsActive;

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
    Uri uri = Uri.parse(
      'https://api.modrinth.com/v2/tag/game_version',
    );
    List<dynamic> vrs = json.decode((await http.get(
      uri,
      headers: {
        "User-Agent": await generateUserAgent(),
      },
    ))
        .body);
    List<String> versions = [];
    for (var v in vrs) {
      if (v["version_type"] == "release") {
        versions.add(v["version"].toString());
      }
    }

    for (var version in versions) {
      versionItems.add(
        DropdownMenuEntry(label: version.toString(), value: version),
      );
    }

    List<String> modpacks = getModpacks(hideFree: false);

    for (var modpack in modpacks) {
      modpackItems.add(
        DropdownMenuEntry(label: modpack, value: modpack),
      );
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

    // If there are new lines in the description we hide theme
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

    return Visibility(
      maintainState: widget.showPreVersion,
      child: OpenContainer(
        closedBuilder: (context, action) {
          return Card(
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
                        child: Image(
                          image: NetworkImage(widget.modIconUrl),
                          alignment: Alignment.centerRight,
                          height: 64,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const CircularProgressIndicator();
                          },
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      margin:
                          const EdgeInsets.only(top: 8, bottom: 8, right: 8),
                      child: widget.downloadable
                          ? FilledButton.icon(
                              onPressed: () {
                                if (GetStorage().read("experimentalFeatures")) {
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
                              icon: const Icon(Icons.file_download),
                              label:
                                  Text(AppLocalizations.of(context)!.download),
                            )
                          : null,
                    ),
                    Container(
                      margin:
                          const EdgeInsets.only(top: 8, bottom: 8, right: 8),
                      child: widget.deletable
                          ? FilledButton.icon(
                              onPressed: () async {
                                File modFile = File(
                                    "${getMinecraftFolder().path}/modpacks/${widget.modpackToUpdate}/${widget.preVersion}");
                                if (await modFile.exists()) {
                                  await modFile.delete();
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
                                String newModConfigRaw = json.encode(modConfig);
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
                              label: Text(AppLocalizations.of(context)!.delete),
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
                                      http.Response res = await http
                                          .get(Uri.parse(widget.newVersionUrl));
                                      Directory modpackFolder = Directory(
                                          "${getMinecraftFolder().path}/modpacks/${widget.modpackToUpdate}");
                                      File resFile = File(
                                          "${modpackFolder.path}/${widget.newVersionUrl.trim().split("/").last}");
                                      if (!await resFile.exists()) {
                                        await resFile.create(recursive: true);
                                      }
                                      await resFile.writeAsBytes(res.bodyBytes,
                                          flush: true, mode: FileMode.write);
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
                        label: Text(AppLocalizations.of(context)!.openInTheWeb),
                      ),
                    ),
                  ],
                ),
                Container(
                  margin: widget.showPreVersion
                      ? const EdgeInsets.symmetric(horizontal: 20, vertical: 20)
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
    );
  }
}
