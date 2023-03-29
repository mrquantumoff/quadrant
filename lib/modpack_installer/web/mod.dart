// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:mcmodpackmanager_reborn/backend.dart';
import 'package:mcmodpackmanager_reborn/modpack_installer/web/generate_user_agent.dart';
import 'package:mcmodpackmanager_reborn/modpack_installer/web/install_mod_page.dart';

enum ModSource { curseForge, modRinth }

enum ModClass {
  mod(6),
  resourcePack(12),
  shaderPack(4546);

  const ModClass(this.value);
  final int value;
}

class ModFile {
  ModFile(
      {required this.downloadUrl,
      required this.fileName,
      required this.gameVersions,
      required this.fileDate});
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
  });

  final String name;
  final String description;
  final String modIconUrl;
  final int downloadCount;
  final String id;
  final ModSource source;
  final ModClass modClass;
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
      return AppLocalizations.of(context)!.mod +
          widget.source.name.toLowerCase();
    } else if (widget.modClass == ModClass.resourcePack) {
      return AppLocalizations.of(context)!.resourcePack +
          widget.source.name.toLowerCase();
    } else if (widget.modClass == ModClass.shaderPack) {
      return AppLocalizations.of(context)!.shaderPack +
          widget.source.name.toLowerCase();
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
    return Container(
      margin: const EdgeInsets.all(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
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
          List<DropdownMenuEntry> versionItems = [];
          List<DropdownMenuEntry> modpackItems = [];

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
          Get.to(
            () => InstallModPage(
              versions: versionItems,
              mod: widget,
              modpacks: modpackItems,
              source: widget.source,
              modClass: widget.modClass,
            ),
          );
        },
        child: Card(
          elevation: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsetsDirectional.only(start: 12, top: 6.5),
                child: Image(
                  image: NetworkImage(widget.modIconUrl),
                  alignment: Alignment.centerRight,
                  height: 84,
                  width: 84,
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
                        const Divider(thickness: 50),
                        Container(
                          margin: const EdgeInsets.only(left: 14, top: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Icon(Icons.download,
                                  color: Colors.grey, size: 20),
                              Text(
                                widget.downloadCount.toString(),
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
                    margin: const EdgeInsets.only(left: 18, right: 18, top: 8),
                    child: Text(
                      desc,
                      style: const TextStyle(color: Colors.grey, fontSize: 24),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 8, left: 18),
                    child: Text(
                      getModpackTypeString(),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
