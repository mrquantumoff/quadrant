import 'dart:convert';
import 'dart:io';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:quadrant/draggable_appbar.dart';
import 'package:quadrant/other/backend.dart';

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
    if (widget.update) {
      modpackFieldController.text = widget.modpack;
    }
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

  @override
  Widget build(BuildContext context) {
    getVersions();
    return Scaffold(
      appBar: DraggableAppBar(
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
                      label: Text(AppLocalizations.of(context)!.downloadFail),
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
                    label: Text(AppLocalizations.of(context)!.chooseVersion),
                    width: 640,
                    menuHeight: 240,
                  );
                }),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              child: DropdownMenu(
                dropdownMenuEntries: const [
                  DropdownMenuEntry(label: "Fabric", value: "Fabric"),
                  DropdownMenuEntry(label: "Forge", value: "Forge"),
                  DropdownMenuEntry(label: "NeoForge", value: "NeoForge"),
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
                    // enabled: !widget.update,
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
                          modpackFieldController.text == "free"))) {
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
                    String oldModpackName = widget.update
                        ? widget.modpack
                        : modpackFieldController.text;
                    String modpackName = modpackFieldController.text;
                    Directory modpackDir = Directory(
                        "${getMinecraftFolder().path}/modpacks/$oldModpackName");
                    if ((await modpackDir.exists() && !widget.update) ||
                        (Directory("${getMinecraftFolder().path}/modpacks/$modpackName")
                                .existsSync() &&
                            widget.update)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppLocalizations.of(context)!.invalidData,
                          ),
                        ),
                      );
                      return;
                    }
                    if (oldModpackName != modpackName) {
                      File currentModpackConf = File(
                          "${getMinecraftFolder().path}/mods/modConfig.json");
                      if (currentModpackConf.existsSync()) {
                        String rawIndexFile =
                            await currentModpackConf.readAsString();
                        Map currentModpackInfo = json.decode(rawIndexFile);
                        if (currentModpackInfo["name"] == oldModpackName) {
                          clearModpack();
                        }
                        modpackDir = await modpackDir.rename(modpackDir.path
                            .replaceAll(oldModpackName, modpackName));
                        applyModpack(modpackName);
                      } else {
                        modpackDir = await modpackDir.rename(modpackDir.path
                            .replaceAll(oldModpackName, modpackName));
                      }
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
