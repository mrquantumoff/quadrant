import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:quadrant/other/backend.dart';

class ModpackPreview extends StatefulWidget {
  ModpackPreview({
    super.key,
    required this.name,
    required this.loader,
    required this.modCount,
    required this.lastSynced,
    required this.mcVersion,
    required this.modConfig,
  });

  String name;
  String loader;
  int modCount;
  String mcVersion;
  Map modConfig;
  int lastSynced;

  @override
  State<ModpackPreview> createState() => _ModpackPreviewState();
}

class _ModpackPreviewState extends State<ModpackPreview> {
  bool isApplied = false;

  @override
  Widget build(BuildContext context) {
    var tag = Localizations.maybeLocaleOf(context)?.toLanguageTag();

    String date = DateFormat('EEEE, dd.MM.yy, HH:mm', tag)
        .format(DateTime.fromMillisecondsSinceEpoch(widget.lastSynced));

    File currentModpackInfo =
        File("${getMinecraftFolder().path}/mods/modConfig.json");
    Map modConfig = json.decode(currentModpackInfo.readAsStringSync());
    if (modConfig["name"] == widget.name) {
      isApplied = true;
    }

    return Card(
      child: Container(
        margin: const EdgeInsets.only(left: 24, right: 8, bottom: 24, top: 12),
        child: Column(
          // mainAxisSize: MainAxisSize.max,
          children: [
            Container(
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    style: const TextStyle(fontSize: 36),
                  ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      "${widget.loader} ${widget.mcVersion} | ${AppLocalizations.of(context)!.modCount(widget.modCount)} ${widget.lastSynced > 0 ? "| ${AppLocalizations.of(context)!.localSyncDate(date)}" : ""}",
                      style: const TextStyle(fontSize: 24, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  isApplied
                      ? Container(
                          margin: const EdgeInsets.only(right: 12),
                          child: FilledButton.tonalIcon(
                            onPressed: () async {},
                            label: Text(AppLocalizations.of(context)!.applied),
                            icon: const Icon(Icons.check),
                          ),
                        )
                      : Container(
                          margin: const EdgeInsets.only(right: 12),
                          child: FilledButton.icon(
                            onPressed: () async {
                              if (isApplied) {
                                return;
                              }

                              bool res = await applyModpack(widget.name);
                              switch (res) {
                                case true:
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          AppLocalizations.of(context)!
                                              .setModpackSuccess),
                                    ),
                                  );
                                  break;
                                case false:
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppLocalizations.of(context)!
                                            .setModpackFailed,
                                      ),
                                    ),
                                  );
                                  break;
                              }
                            },
                            label: Text(AppLocalizations.of(context)!.apply),
                            style: FilledButton.styleFrom(
                                // minimumSize: const Size(360, 48),
                                // backgroundColor: Colors.lightGreen,
                                // foregroundColor: Colors.black,
                                ),
                            icon: const Icon(Icons.check),
                          ),
                        ),
                  FilledButton.icon(
                    onPressed: () async {
                      String content = json.encode(widget.modConfig);
                      await shareModpack(context, content);
                    },
                    label: Text(AppLocalizations.of(context)!.share),
                    icon: const Icon(Icons.share),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      // minimumSize: const Size(360, 48),
                    ),
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      String content = json.encode(widget.modConfig);
                      await syncModpack(context, content, true);
                    },
                    label: Text(AppLocalizations.of(context)!.sync),
                    icon: const Icon(Icons.sync),
                    style: FilledButton.styleFrom(
                        // backgroundColor: Colors.blueAccent,
                        // foregroundColor: Colors.white,
                        // minimumSize: const Size(360, 48),
                        ),
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      File modpackConfig = File(
                          "${getMinecraftFolder().path}/modpacks/${widget.name}/modConfig.json");
                      if (!modpackConfig.existsSync()) return;
                      String content = await modpackConfig.readAsString();

                      var filePickerResult = await FilePicker.platform
                          .saveFile(fileName: "${widget.name}.json");
                      if (filePickerResult == null) return;
                      File selectedFile = File(filePickerResult);
                      if (await selectedFile.exists()) {
                        await selectedFile.delete(recursive: true);
                      }
                      await selectedFile.create(recursive: true);

                      await selectedFile.writeAsString(content);
                    },
                    label: Text(AppLocalizations.of(context)!.exportMods),
                    icon: const Icon(Icons.upload_file),
                    style: FilledButton.styleFrom(
                        // backgroundColor: Colors.redAccent,
                        // foregroundColor: Colors.white,
                        // minimumSize: const Size(360, 48),
                        ),
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      Directory mods =
                          Directory("${getMinecraftFolder().path}/mods");
                      Directory modpack = Directory(
                          "${getMinecraftFolder().path}/modpacks/${widget.name}");
                      if (mods.existsSync()) {
                        mods.deleteSync(recursive: true);
                      }
                      if (modpack.existsSync()) {
                        modpack.deleteSync(recursive: true);
                      }
                    },
                    label: Text(AppLocalizations.of(context)!.delete),
                    icon: const Icon(Icons.delete),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      // minimumSize: const Size(360, 48),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
