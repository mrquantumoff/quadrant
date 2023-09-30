import 'dart:convert';
import 'dart:io';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';

class ModpackCreator extends StatefulWidget {
  const ModpackCreator({super.key, this.update = false, required this.modpack});

  final bool update;
  final String modpack;

  @override
  State<ModpackCreator> createState() => _ModpackCreatorState();
}

class _ModpackCreatorState extends State<ModpackCreator> {
  late bool areButttonsActive;
  TextEditingController versionFieldController = TextEditingController();
  TextEditingController apiFieldController = TextEditingController();
  TextEditingController modpackFieldController = TextEditingController();
  @override
  void initState() {
    super.initState();
    areButttonsActive = true;
  }

  final String apiKey =
      const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");

  @override
  void dispose() {
    super.dispose();
    areButttonsActive = false;
  }

  void setAreButtonsActive(bool value) {
    setState(() {
      areButttonsActive = value;
    });
  }

  bool hasGetVersionsBeenRun = false;

  Future<List<DropdownMenuEntry>> getVersions() async {
    List<DropdownMenuEntry> items = [];
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
      items.add(
        DropdownMenuEntry(label: version.toString(), value: version),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    getVersions();
    return Scaffold(
      appBar: AppBar(
        title: widget.update
            ? Text(AppLocalizations.of(context)!.update)
            : Text(AppLocalizations.of(context)!.createModpack),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: areButttonsActive
              ? () {
                  Get.back();
                }
              : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context)!.buttonsAreDisabled,
                      ),
                    ),
                  );
                },
        ),
      ),
      body: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                child: FutureBuilder(
                    future: getVersions(),
                    builder: ((BuildContext context, snapshot) {
                      if (snapshot.hasError) {
                        return DropdownMenu(
                          dropdownMenuEntries: const [],
                          enabled: false,
                          errorText: AppLocalizations.of(context)!.downloadFail,
                          label:
                              Text(AppLocalizations.of(context)!.downloadFail),
                          width: 640,
                        );
                      } else if (!snapshot.hasData) {
                        return const SizedBox(
                          width: 640,
                          child: LinearProgressIndicator(),
                        );
                      }
                      return DropdownMenu(
                        dropdownMenuEntries: snapshot.data!,
                        controller: versionFieldController,
                        label:
                            Text(AppLocalizations.of(context)!.chooseVersion),
                        width: 640,
                        menuHeight: 240,
                      );
                    }))),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              child: DropdownMenu(
                dropdownMenuEntries: const [
                  DropdownMenuEntry(label: "Fabric", value: "Fabric"),
                  DropdownMenuEntry(label: "Forge", value: "Forge"),
                  DropdownMenuEntry(label: "Quilt", value: "Quilt"),
                  DropdownMenuEntry(label: "Rift", value: "Rift"),
                ],
                controller: apiFieldController,
                label: Text(AppLocalizations.of(context)!.choosePreferredAPI),
                width: 640,
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                width: 640,
                child: TextField(
                  controller: modpackFieldController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: AppLocalizations.of(context)!.name,
                    enabled: !widget.update,
                  ),
                ),
              ),
            ),
            Container(
              margin:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 312.5),
              child: TextButton.icon(
                onPressed: () async {
                  if (versionFieldController.text == "" ||
                      apiFieldController.text == "" ||
                      ((modpackFieldController.text == "" ||
                              modpackFieldController.text == "free") &&
                          !widget.update)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(context)!.invalidData,
                        ),
                      ),
                    );
                    return;
                  }
                  try {
                    String modpackName = widget.update
                        ? widget.modpack
                        : modpackFieldController.text;

                    Directory modpackDir = Directory(
                        "${getMinecraftFolder().path}/modpacks/$modpackName");
                    if (await modpackDir.exists() && !widget.update) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppLocalizations.of(context)!.invalidData,
                          ),
                        ),
                      );
                      return;
                    }
                    List<dynamic> mods = [];
                    File indexFile = File("${modpackDir.path}/modConfig.json");
                    if (widget.update) {
                      try {
                        String rawIndexFile = await indexFile.readAsString();
                        Map indexFileConts = json.decode(rawIndexFile);
                        mods = indexFileConts["mods"];
                      } catch (e) {}
                    }
                    if (await indexFile.exists() && widget.update) {
                      await indexFile.delete();
                    }
                    await indexFile.create(recursive: true);
                    Map modConfig = {
                      "modLoader": apiFieldController.text,
                      "version": versionFieldController.text,
                      "name": modpackName,
                      "mods": mods
                    };
                    await indexFile.writeAsString(
                      json.encode(modConfig),
                    );
                    Get.back();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          e.toString(),
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.add),
                label: widget.update
                    ? Text(AppLocalizations.of(context)!.update)
                    : Text(AppLocalizations.of(context)!.createModpack),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
