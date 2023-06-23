// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mcmodpackmanager_reborn/backend.dart';
import 'package:mcmodpackmanager_reborn/pages/modpack_installer/web/generate_user_agent.dart';
import 'package:mcmodpackmanager_reborn/pages/modpack_installer/web/mod/install_mod_page.dart';
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
    this.downloadAble = true,
  });

  final String name;
  final String description;
  final String modIconUrl;
  final int downloadCount;
  final String id;
  final ModSource source;
  final ModClass modClass;
  final String slug;
  final bool downloadAble;
  Function(bool) setAreParentButtonsActive;

  @override
  State<Mod> createState() => _ModState();
}

class _ModState extends State<Mod> {
  late bool areButttonsActive;

  @override
  void initState() {
    super.initState();
    areButttonsActive = true;
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
    String desc = widget.description.length >= 48
        ? widget.description.replaceRange(48, null, "...")
        : widget.description;
    String displayName = widget.name.length >= 36
        ? widget.name.replaceRange(36, null, "...")
        : widget.name;
    NumberFormat numberFormatter = NumberFormat.compact(
        explicitSign: false, locale: AppLocalizations.of(context)!.localeName);
    return Column(
      children: [
        Container(
          child: widget.downloadAble
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
                  margin: const EdgeInsetsDirectional.only(start: 12, top: 6.5),
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
                                  numberFormatter.format(widget.downloadCount),
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
                          child: widget.downloadAble
                              ? TextButton.icon(
                                  onPressed: () async {
                                    Uri uri = Uri.parse(
                                      'https://api.modrinth.com/v2/tag/game_version',
                                    );
                                    List<dynamic> vrs =
                                        json.decode((await http.get(
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
                          margin: widget.downloadAble
                              ? const EdgeInsets.symmetric(horizontal: 20)
                              : null,
                          child: TextButton.icon(
                            onPressed: () async {
                              final String slug = widget.slug;
                              String rawUrl = "";
                              String typeUrl = "";
                              if (widget.source == ModSource.curseForge) {
                                rawUrl =
                                    "https://beta.curseforge.com/minecraft";
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
                            label: Text(
                                AppLocalizations.of(context)!.openInTheWeb),
                          ),
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
    );
  }
}
