import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/web/mod/mod.dart';

class UpdateModpackPage extends StatefulWidget {
  const UpdateModpackPage({
    super.key,
    required this.currentMods,
    required this.targetVersion,
    required this.name,
    required this.modLoader,
  });

  final List<dynamic> currentMods;
  final String name;
  final String targetVersion;
  final String modLoader;

  @override
  State<UpdateModpackPage> createState() => _UpdateModpackPageState();
}

class _UpdateModpackPageState extends State<UpdateModpackPage> {
  List<Widget> items = [];

  Future<List<Mod>> getFullMods() async {
    List<Mod> mods = [];

    for (var mod in widget.currentMods) {
      ModSource modSrc = mod["source"].toString().contains("curseForge")
          ? ModSource.curseForge
          : (mod["source"].toString().contains("modRinth")
              ? ModSource.modRinth
              : ModSource.online);
      if (modSrc == ModSource.online) continue;

      Mod completeMod = await getMod(
        mod["id"],
        modSrc,
        (val) => null,
        versionShow: true,
        preVersion: mod["downloadUrl"].toString().trim().split("/").last,
        versionTarget: widget.targetVersion,
        downloadable: false,
        modLoader: widget.modLoader,
        modpack: widget.name,
      );
      // debugPrint(mod["downloadUrl"].toString().trim().split("/").last);
      mods.add(completeMod);
    }

    return mods;
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
        title: Text(AppLocalizations.of(context)!.update),
      ),
      body: Center(
        child: FutureBuilder(
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            } else if (snapshot.hasError) {
              return Column(
                children: [
                  const Icon(Icons.error),
                  Text(AppLocalizations.of(context)!.unknown)
                ],
              );
            } else {
              return ListView(
                children: snapshot.data ?? [],
              );
            }
          },
          future: getFullMods(),
        ),
      ),
    );
  }
}
