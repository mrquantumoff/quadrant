import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/web/mod/mod.dart';

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

  Future<List<Mod>> fetchMods() async {
    List<dynamic> rawMods = currentModpack["mods"];
    List<Mod> mods = [];
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
      Mod mod = await getMod(
        rawMod["id"],
        modSrc,
        (val) => null,
        downloadable: false,
      );
      mods.add(mod);
      debugPrint(mod.id);
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
          "${AppLocalizations.of(context)!.currentModpack}: ${currentModpack["name"] ?? "-"}",
        ),
      ),
      body: Center(
        child: FutureBuilder(
          future: fetchMods(),
          builder: ((context, snapshot) {
            if (snapshot.hasData) {
              return GridView.extent(
                maxCrossAxisExtent: 540,
                mainAxisSpacing: 15,
                crossAxisSpacing: 0,
                childAspectRatio: 1.35,
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
