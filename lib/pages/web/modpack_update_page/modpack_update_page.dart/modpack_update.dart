import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage_qnt/get_storage.dart';
import 'package:quadrant/draggable_appbar.dart';
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
  bool hasGotMods = false;

  Future<List<Mod>> getFullMods() async {
    if (hasGotMods) return [];
    List<Mod> mods = [];
    for (var mod in widget.currentMods) {
      ModSource modSrc = mod["source"].toString().contains("curseForge")
          ? ModSource.curseForge
          : (mod["source"].toString().contains("modRinth")
              ? ModSource.modRinth
              : ModSource.online);
      if (modSrc == ModSource.online) continue;

      // Sadly, this has to use getMod and not the new LoadingMod widget, because it has to know whether there is a new version of a mod.

      Mod completeMod = await getMod(
        mod["id"],
        modSrc,
        (val) => null,
        versionShow: true,
        preVersion: Uri.decodeFull(
          mod["downloadUrl"].toString().trim().split("/").last,
        ),
        versionTarget: widget.targetVersion,
        downloadable: false,
        modLoader: widget.modLoader,
        modpack: widget.name,
      );
      bool isNewVersionUrl = completeMod.newVersionUrl.trim().isEmpty;
      if (((completeMod.showPreVersion && isNewVersionUrl) &&
          GetStorage().read("showUnupgradeableMods") == false)) {
        continue;
      }
      mods.add(completeMod);
    }

    hasGotMods = true;
    setState(() {
      items = mods;
      updateableItems =
          mods.where((mod) => mod.newVersionUrl.isNotEmpty).toList();
    });
    return mods;
  }

  List<Widget> items = [];
  List<Widget> updateableItems = [];

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
          title: Text(
              "${AppLocalizations.of(context)!.update} | ${AppLocalizations.of(context)!.modCount("${updateableItems.length}/${widget.currentMods.length}")}"),
        ),
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
              return GridView.extent(
                maxCrossAxisExtent: 840,
                mainAxisSpacing: 15,
                crossAxisSpacing: 0,
                childAspectRatio: 1.35,
                padding: const EdgeInsets.only(bottom: 120),
                children: items,
              );
            }
          },
          future: getFullMods(),
        ),
      ),
    );
  }
}
