import 'dart:convert';
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/modpack_creator/modpack_creator.dart';
import 'package:quadrant/pages/modpack_view/modpack_view.dart';

class ModpackPreview extends StatefulWidget {
  ModpackPreview({
    super.key,
    required this.name,
    required this.loader,
    required this.modCount,
    required this.lastSynced,
    required this.mcVersion,
    required this.modConfig,
    required this.isApplied,
  });

  String name;
  String loader;
  int modCount;
  String mcVersion;
  Map modConfig;
  int lastSynced;
  bool isApplied;

  @override
  State<ModpackPreview> createState() => _ModpackPreviewState();
}

class _ModpackPreviewState extends State<ModpackPreview> {
  @override
  Widget build(BuildContext context) {
    var tag = Localizations.maybeLocaleOf(context)?.toLanguageTag();

    String date = DateFormat('EEEE, dd.MM.yy, HH:mm', tag)
        .format(DateTime.fromMillisecondsSinceEpoch(widget.lastSynced));

    return OpenContainer(
      closedBuilder: (context, action) => Card(
        child: Container(
          margin:
              const EdgeInsets.only(left: 24, right: 8, bottom: 24, top: 12),
          child: Column(
            // mainAxisSize: MainAxisSize.max,
            children: [
              Container(
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.name,
                          style: const TextStyle(fontSize: 36),
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        FilledButton.tonalIcon(
                          onPressed: action,
                          label: Text(AppLocalizations.of(context)!.details),
                          icon: const Icon(Icons.info),
                        )
                      ],
                    ),
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        "${widget.loader} ${widget.mcVersion} | ${AppLocalizations.of(context)!.modCount(widget.modCount)} ${widget.lastSynced > 0 ? "| ${AppLocalizations.of(context)!.localSyncDate(date)}" : ""}",
                        style:
                            const TextStyle(fontSize: 24, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 32),
                // margin: const EdgeInsets.only(right: 12),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  dragStartBehavior: DragStartBehavior.down,
                  children: [
                    widget.isApplied
                        ? Container(
                            margin: const EdgeInsets.only(right: 12),
                            child: FilledButton.tonalIcon(
                              onPressed: () async {},
                              label:
                                  Text(AppLocalizations.of(context)!.applied),
                              icon: const Icon(Icons.check),
                            ),
                          )
                        : Container(
                            margin: const EdgeInsets.only(right: 12),
                            child: FilledButton.icon(
                              onPressed: () async {
                                if (widget.isApplied) {
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
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        Get.to(
                          () => ModpackCreator(
                            modpack: widget.name,
                            update: true,
                          ),
                          transition: Transition.topLevel,
                        );
                      },
                      label: Text(AppLocalizations.of(context)!.update),
                      icon: const Icon(Icons.edit),
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
      ),
      openBuilder: (context, action) => ModpackView(
        modpack: widget.modConfig,
      ),
      tappable: false,
      closedColor: Colors.transparent,
      openColor: Colors.transparent,
    );
  }
}
