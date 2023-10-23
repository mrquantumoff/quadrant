// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
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
    super.build(context);
    debugPrint(widget.preVersion);
    String desc = widget.description.length >= 48
        ? widget.description.replaceRange(48, null, "...")
        : widget.description;
    String displayName = widget.name.length >= 36
        ? widget.name.replaceRange(36, null, "...")
        : widget.name;

    bool isNewVersionUrl = widget.newVersionUrl.trim().isEmpty;

    NumberFormat numberFormatter = NumberFormat.compact(
        explicitSign: false, locale: AppLocalizations.of(context)!.localeName);
    if (((widget.showPreVersion && isNewVersionUrl) &&
        GetStorage().read("showUnupgradeableMods") == false)) {
      return const SizedBox.shrink();
    }

    if (hide) {
      return const SizedBox.shrink();
    }

    return Visibility(
      maintainSize: widget.showPreVersion,
      maintainState: widget.showPreVersion,
      maintainAnimation: widget.showPreVersion,
      maintainInteractivity: widget.showPreVersion,
      maintainSemantics: widget.showPreVersion,
      child: Column(
        children: [
          Container(
            child: widget.downloadable
                ? const Divider(
                    height: 1.5,
                    thickness: 1,
                  )
                : null,
          ),
          Container(
            margin: const EdgeInsets.all(12),
            child: Card(
              elevation: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    margin:
                        const EdgeInsetsDirectional.only(start: 12, top: 6.5),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                          GetStorage().read("clipIcons") == true ? 80 : 0),
                      child: Image(
                        image: NetworkImage(widget.modIconUrl),
                        alignment: Alignment.centerRight,
                        height: 84,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const CircularProgressIndicator();
                        },
                        width: 84,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 15),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(fontSize: 32),
                            ),
                            Container(
                              margin: const EdgeInsets.only(left: 14, top: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Icon(Icons.download,
                                      color: Colors.grey, size: 20),
                                  Text(
                                    numberFormatter
                                        .format(widget.downloadCount),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin:
                            const EdgeInsets.only(left: 18, right: 18, top: 8),
                        child: Text(
                          desc,
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 24),
                        ),
                      ),
                      Container(
                        margin:
                            const EdgeInsets.only(top: 8, bottom: 8, left: 18),
                        child: Text(
                          getModpackTypeString(),
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 20),
                            child: widget.downloadable
                                ? TextButton.icon(
                                    onPressed: () async {
                                      Uri uri = Uri.parse(
                                        'https://api.modrinth.com/v2/tag/game_version',
                                      );
                                      List<dynamic> vrs =
                                          json.decode((await http.get(
                                        uri,
                                        headers: {
                                          "User-Agent":
                                              await generateUserAgent(),
                                        },
                                      ))
                                              .body);
                                      List<String> versions = [];
                                      for (var v in vrs) {
                                        if (v["version_type"] == "release") {
                                          versions.add(v["version"].toString());
                                        }
                                      }
                                      List<DropdownMenuEntry> versionItems = [];
                                      List<DropdownMenuEntry> modpackItems = [];

                                      for (var version in versions) {
                                        versionItems.add(
                                          DropdownMenuEntry(
                                              label: version.toString(),
                                              value: version),
                                        );
                                      }

                                      List<String> modpacks =
                                          getModpacks(hideFree: false);

                                      for (var modpack in modpacks) {
                                        modpackItems.add(
                                          DropdownMenuEntry(
                                              label: modpack, value: modpack),
                                        );
                                      }

                                      Get.to(
                                        () => InstallModPage(
                                          versions: versionItems,
                                          mod: widget,
                                          modpacks: modpackItems,
                                          source: widget.source,
                                          modClass: widget.modClass,
                                        ),
                                        preventDuplicates: false,
                                      );
                                    },
                                    icon: const Icon(Icons.file_download),
                                    label: Text(
                                        AppLocalizations.of(context)!.download),
                                  )
                                : null,
                          ),
                          Container(
                            margin: widget.downloadable
                                ? const EdgeInsets.symmetric(horizontal: 20)
                                : const EdgeInsets.symmetric(vertical: 20),
                            child: TextButton.icon(
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
                                } else if (widget.source ==
                                    ModSource.modRinth) {
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
                              label: Text(
                                  AppLocalizations.of(context)!.openInTheWeb),
                            ),
                          ),
                          Container(
                            margin: widget.showPreVersion
                                ? const EdgeInsets.symmetric(horizontal: 20)
                                : EdgeInsets.symmetric(
                                    vertical: (showUpdateButton ? 20 : 50)),
                            child: !isNewVersionUrl || !areButttonsActive
                                ? showUpdateButton
                                    ? TextButton.icon(
                                        onPressed: () async {
                                          setState(() {
                                            showUpdateButton = false;
                                            areButttonsActive = false;
                                          });
                                          http.Response res = await http.get(
                                              Uri.parse(widget.newVersionUrl));
                                          Directory modpackFolder = Directory(
                                              "${getMinecraftFolder().path}/modpacks/${widget.modpackToUpdate}");
                                          File resFile = File(
                                              "${modpackFolder.path}/${widget.newVersionUrl.trim().split("/").last}");
                                          if (!await resFile.exists()) {
                                            await resFile.create(
                                                recursive: true);
                                          }
                                          await resFile.writeAsBytes(
                                              res.bodyBytes,
                                              flush: true,
                                              mode: FileMode.write);
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
                                          await modConfig
                                              .writeAsString(newConf);

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
                                        },
                                        icon: const Icon(Icons.update),
                                        label: Text(
                                            AppLocalizations.of(context)!
                                                .update),
                                      )
                                    : SizedBox.fromSize(
                                        size: const Size(240, 2),
                                        child: const LinearProgressIndicator(),
                                      )
                                : Container(),
                          ),
                          Container(
                            margin: widget.showPreVersion
                                ? const EdgeInsets.symmetric(horizontal: 20)
                                : const EdgeInsets.symmetric(vertical: 20),
                            child: widget.showPreVersion
                                ? Text(
                                    "${widget.preVersion} -> ${widget.newVersionUrl.trim().split("/").last}",
                                  )
                                : Container(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
