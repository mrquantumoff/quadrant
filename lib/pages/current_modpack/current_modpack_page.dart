import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/web/mod/loading_mod.dart';
import 'package:quadrant/pages/web/mod/mod.dart';
import 'package:quadrant/pages/web/modpack_update_page/modpack_update_page.dart/update_modpack.dart';

class CurrentModpackPage extends StatefulWidget {
  const CurrentModpackPage({super.key});

  @override
  State<CurrentModpackPage> createState() => _CurrentModpackPageState();
}

class _CurrentModpackPageState extends State<CurrentModpackPage> {
  @override
  void initState() {
    super.initState();
  }

  void getCurrentModpack() {
    File currentModConfig =
        File("${getMinecraftFolder().path}/mods/modConfig.json");
    if (!currentModConfig.existsSync()) {
      setState(() {
        currentModpack = {};
      });
      return;
    }
    String currentModConfigRaw = currentModConfig.readAsStringSync();
    setState(() {
      currentModpack = json.decode(currentModConfigRaw);
    });
  }

  Future<List<LoadingMod>> fetchMods() async {
    List<dynamic> rawMods = currentModpack["mods"] ?? [];
    // rawMods.sort();
    List<LoadingMod> mods = [];
    for (var rawMod in rawMods) {
      ModSource modSrc = ModSource.online;
      if (rawMod["source"].toString().toLowerCase().contains("curseforge")) {
        modSrc = ModSource.curseForge;
      } else if (rawMod["source"]
          .toString()
          .toLowerCase()
          .contains("modrinth")) {
        modSrc = ModSource.modRinth;
      }
      LoadingMod mod = LoadingMod(
        modId: rawMod["id"].toString(),
        source: modSrc,
        downloadable: false,
        showPreVersion: false,
        modpack: currentModpack["name"],
        preVersion: rawMod["downloadUrl"].toString().split("/").last,
        deletable: true,
      );
      mods.add(mod);
      // debugPrint(mod.id);
    }

    return mods;
  }

  Map currentModpack = {};

  @override
  Widget build(BuildContext context) {
    getCurrentModpack();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "${AppLocalizations.of(context)!.currentModpack}: ${currentModpack["name"] ?? "-"} | ${currentModpack["modLoader"] ?? "-"} | ${currentModpack["version"] ?? "-"} | ${AppLocalizations.of(context)!.modCount(((currentModpack["mods"] ?? []) as List<dynamic>).length)}",
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              onPressed: () {
                Get.to(
                  () => UpdateModpack(
                    preSelectedModpack: currentModpack["name"],
                  ),
                );
              },
              icon: const Icon(Icons.update),
              label: Text(AppLocalizations.of(context)!.update),
            ),
          ),
        ],
      ),
      body: Center(
        child: FutureBuilder(
          future: fetchMods(),
          builder: ((context, snapshot) {
            if (snapshot.hasData) {
              return GridView.extent(
                maxCrossAxisExtent: 565,
                mainAxisSpacing: 15,
                crossAxisSpacing: 0,
                childAspectRatio: 1.25,
                padding: const EdgeInsets.only(bottom: 15),
                children: snapshot.data ?? [],
              );
            }
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }
            return const Icon(Icons.error);
          }),
        ),
      ),
    );
  }
}
