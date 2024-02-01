import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/web/modpack_update_page/modpack_update_page.dart/modpack_update.dart';

// ignore: must_be_immutable
class UpdateModpack extends StatefulWidget {
  UpdateModpack({super.key, this.preSelectedModpack});

  String? preSelectedModpack;

  @override
  State<UpdateModpack> createState() => _UpdateModpackState();
}

class _UpdateModpackState extends State<UpdateModpack> {
  late TextEditingController versionFieldController;
  late TextEditingController modpackFieldController;
  late bool apiFieldEnabled;
  late bool versionFieldEnabled;
  @override
  void initState() {
    apiFieldEnabled = true;
    versionFieldEnabled = true;

    versionFieldController = TextEditingController();
    modpackFieldController =
        TextEditingController(text: widget.preSelectedModpack);
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
            widget.preSelectedModpack == null
                ? Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: DropdownMenu(
                      dropdownMenuEntries: modpackItems,
                      controller: modpackFieldController,
                      label: Text(AppLocalizations.of(context)!.chooseModpack),
                      width: 840,
                      onSelected: (dynamic newValue) async {
                        String latestVersion = (await getVersions())[0].value;
                        setState(() {
                          versionFieldController.text = latestVersion;
                          apiFieldEnabled = false;
                          versionFieldEnabled = false;
                        });
                      },
                    ),
                  )
                : Container(),
            FilledButton.icon(
              onPressed: () async {
                String version = versionFieldController.value.text;
                String modpack = widget.preSelectedModpack ??
                    modpackFieldController.value.text;
                if (version == "" || modpack == "") return;
                GetStorage().writeInMemory("lastUsedVersion", version);
                GetStorage().writeInMemory("lastUsedModpack", modpack);

                String value = modpack;
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

                Get.to(
                  () => UpdateModpackPage(
                    currentMods: modpackConf["mods"],
                    targetVersion: version,
                    name: modpackConf["name"],
                    modLoader: modpackConf["modLoader"],
                  ),
                  transition: Transition.downToUp,
                );
              },
              icon: const Icon(Icons.update),
              label: Text(AppLocalizations.of(context)!.update),
            )
          ],
        ),
      ),
    );
  }
}
