import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
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
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
        child: Row(
          mainAxisSize: MainAxisSize.max,
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
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      "${widget.loader} ${widget.mcVersion} | ${AppLocalizations.of(context)!.modCount(widget.modCount)}",
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      onPressed: () async {
                        bool res = await applyModpack(widget.name);
                        switch (res) {
                          case true:
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(AppLocalizations.of(context)!
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
                        minimumSize: const Size(360, 48),
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.check),
                    ),
                    const SizedBox(
                      height: 12,
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
                        minimumSize: const Size(360, 48),
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    FilledButton.icon(
                      onPressed: () async {
                        String content = json.encode(widget.modConfig);
                        await syncModpack(context, content, true);
                      },
                      label: Text(AppLocalizations.of(context)!.sync),
                      icon: const Icon(Icons.sync),
                      style: FilledButton.styleFrom(
                        // backgroundColor: Colors.blueAccent,
                        // foregroundColor: Colors.white,
                        minimumSize: const Size(360, 48),
                      ),
                    ),
                    const SizedBox(
                      height: 12,
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
                        minimumSize: const Size(360, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
