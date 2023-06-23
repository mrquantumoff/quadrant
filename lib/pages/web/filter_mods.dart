import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:mcmodpackmanager_reborn/other/backend.dart';
import 'package:mcmodpackmanager_reborn/pages/web/web_sources.dart';
import 'package:mcmodpackmanager_reborn/pages/web/generate_user_agent.dart';

class FilterMods extends StatefulWidget {
  const FilterMods({super.key});

  @override
  State<FilterMods> createState() => _FilterModsState();
}

class _FilterModsState extends State<FilterMods> {
  late TextEditingController versionFieldController;
  late TextEditingController apiFieldController;
  late TextEditingController modpackFieldController;
  late bool apiFieldEnabled;
  late bool versionFieldEnabled;
  @override
  void initState() {
    apiFieldEnabled = true;
    versionFieldEnabled = true;

    versionFieldController = TextEditingController();
    apiFieldController = TextEditingController();
    modpackFieldController = TextEditingController();
    super.initState();
    getModpacksList();
  }

  List<DropdownMenuEntry> versionItems = [];
  List<DropdownMenuEntry> modpackItems = [];
  void getModpacksList() async {
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

  @override
  void dispose() {
    super.dispose();
    // versionFieldController.dispose();
    // apiFieldController.dispose();
    // modpackFieldController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Get.back();
          },
        ),
        title: Text(AppLocalizations.of(context)!.search),
      ),
      body: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              child: DropdownMenu(
                dropdownMenuEntries: versionItems,
                controller: versionFieldController,
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
                enabled: apiFieldEnabled,
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              child: DropdownMenu(
                dropdownMenuEntries: modpackItems,
                controller: modpackFieldController,
                label: Text(AppLocalizations.of(context)!.chooseModpack),
                width: 840,
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
            TextButton.icon(
              onPressed: () async {
                String version = versionFieldController.value.text;
                String api = apiFieldController.value.text;
                String modpack = modpackFieldController.value.text;

                GetStorage().writeInMemory("lastUsedVersion", version);
                GetStorage().writeInMemory("lastUsedAPI", api);
                GetStorage().writeInMemory("lastUsedModpack", modpack);
                Get.to(
                  () => const WebSourcesPage(
                    filterOn: true,
                  ),
                  transition: Transition.downToUp,
                );
              },
              icon: const Icon(Icons.search),
              label: Text(AppLocalizations.of(context)!.apply),
            )
          ],
        ),
      ),
    );
  }
}
