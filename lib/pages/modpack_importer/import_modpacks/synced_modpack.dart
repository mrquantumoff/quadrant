import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';

class SyncedModpack extends StatefulWidget {
  const SyncedModpack({
    super.key,
    required this.modpackId,
    required this.name,
    required this.mods,
    required this.mcVersion,
    required this.modLoader,
    required this.lastSynced,
    required this.reload,
    required this.token,
    required this.getMods,
  });

  final String modpackId;
  final String name;
  final String mods;
  final String mcVersion;
  final String modLoader;
  final int lastSynced;
  final Function reload;
  final Function(String rawFile, {bool switchTabs}) getMods;
  final String token;

  @override
  State<SyncedModpack> createState() => _SyncedModpackState();
}

class _SyncedModpackState extends State<SyncedModpack> {
  @override
  Widget build(BuildContext context) {
    var tag = Localizations.maybeLocaleOf(context)?.toLanguageTag();

    String date = DateFormat('EEEE, dd.MM.yy, HH:mm', tag)
        .format(DateTime.fromMillisecondsSinceEpoch(widget.lastSynced));

    return SizedBox(
      width: 640,
      height: 128,
      child: Card(
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Container(
              margin: const EdgeInsets.only(left: 12, top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    style: const TextStyle(fontSize: 36),
                  ),
                  Text(
                    "${widget.modLoader} ${widget.mcVersion}",
                    style: const TextStyle(fontSize: 18),
                  ),
                  Text(
                    AppLocalizations.of(context)!.lastSyncedOn(date),
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
                        List mods = json.decode(widget.mods);
                        debugPrint(mods.toString());
                        Map modConfig = {
                          "name": widget.name,
                          "version": widget.mcVersion,
                          "mods": mods,
                          "modLoader": widget.modLoader
                        };
                        await widget.getMods(json.encode(modConfig),
                            switchTabs: true);
                      },
                      icon: const Icon(Icons.download),
                      label: Text(AppLocalizations.of(context)!.download),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(360, 48),
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    FilledButton.icon(
                      onPressed: () async {
                        http.Response res = await http.delete(
                          Uri.parse(
                              "https://api.mrquantumoff.dev/api/v2/delete/quadrant_sync"),
                          headers: {
                            "User-Agent": await generateUserAgent(),
                            "Authorization": "Bearer ${widget.token}"
                          },
                          body: json.encode(
                            {
                              "modpack_id": widget.modpackId,
                              "name": widget.name,
                            },
                          ),
                        );
                        if (res.statusCode != 200) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(res.body),
                            ),
                          );
                        }
                        widget.reload();
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
