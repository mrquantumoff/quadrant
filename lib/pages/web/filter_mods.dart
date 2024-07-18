import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage_qnt/get_storage.dart';
import 'package:quadrant/draggable_appbar.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/web/web_sources.dart';

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

  late bool modsOn;
  late bool shadersOn;
  late bool resourcePacksOn;

  @override
  void initState() {
    apiFieldEnabled = true;
    versionFieldEnabled = true;

    versionFieldController = TextEditingController();
    apiFieldController = TextEditingController();
    modpackFieldController = TextEditingController();

    modsOn = true;
    shadersOn = true;
    resourcePacksOn = true;

    super.initState();
    getModpacksList();
  }

  List<DropdownMenuEntry> versionItems = [];
  List<DropdownMenuEntry> modpackItems = [];
  void getModpacksList() async {
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
      appBar: DraggableAppBar(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Get.back();
            },
          ),
          title: Text(AppLocalizations.of(context)!.search),
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
                      width: 840,
                    );
                  } else if (!snapshot.hasData) {
                    return const SizedBox(
                      width: 840,
                      child: LinearProgressIndicator(),
                    );
                  }
                  return DropdownMenu(
                    dropdownMenuEntries: snapshot.data!,
                    controller: versionFieldController,
                    label: Text(AppLocalizations.of(context)!.chooseVersion),
                    width: 840,
                    menuHeight: 240,
                  );
                }),
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
                enabled: apiFieldEnabled,
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 12),
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
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Checkbox(
                      value: modsOn,
                      onChanged: (bool? newValue) {
                        setState(() {
                          modsOn = newValue ?? modsOn;
                        });
                      }),
                  Text(AppLocalizations.of(context)!.mods),
                  Checkbox(
                      value: resourcePacksOn,
                      onChanged: (bool? newValue) {
                        setState(() {
                          resourcePacksOn = newValue ?? resourcePacksOn;
                        });
                      }),
                  Text(AppLocalizations.of(context)!.resourcePacks),
                  Checkbox(
                      value: shadersOn,
                      onChanged: (bool? newValue) {
                        setState(() {
                          shadersOn = newValue ?? shadersOn;
                        });
                      }),
                  Text(AppLocalizations.of(context)!.shaderPacks),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () async {
                String version = versionFieldController.value.text;
                String api = apiFieldController.value.text;
                String modpack = modpackFieldController.value.text;

                GetStorage().writeInMemory("lastUsedVersion", version);
                GetStorage().writeInMemory("lastUsedAPI", api);
                GetStorage().writeInMemory("lastUsedModpack", modpack);

                debugPrint(
                    "\nLast used version : $version\nLast used API: $api\nLast used modpack: $modpack\n");

                Get.to(
                  () => WebSourcesPage(
                    filterOn: true,
                    modsOn: modsOn,
                    resourcePacksOn: resourcePacksOn,
                    shadersOn: shadersOn,
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
