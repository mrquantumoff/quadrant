import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';

// ignore: must_be_immutable
class SyncedModpack extends StatefulWidget {
  SyncedModpack({
    super.key,
    required this.modpackId,
    required this.name,
    required this.mods,
    required this.mcVersion,
    required this.modLoader,
    required this.lastSynced,
    required this.reload,
    required this.token,
    this.getMods,
  });

  final String modpackId;
  final String name;
  final String mods;
  final String mcVersion;
  final String modLoader;
  final int lastSynced;
  final Function reload;
  Function(String rawFile, {bool switchTabs})? getMods;
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

    String localSyncedLocalDate = "-";

    File modpackSyncFile = File(
        "${getMinecraftFolder().path}/modpacks/${widget.name}/quadrantSync.json");
    if (modpackSyncFile.existsSync()) {
      try {
        localSyncedLocalDate = DateFormat('EEEE, dd.MM.yy, HH:mm', tag).format(
            DateTime.fromMillisecondsSinceEpoch(json
                .decode(modpackSyncFile.readAsStringSync())["last_synced"]));
      } catch (e) {
        debugPrint("$e");
      }
    }

    return Card(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  margin: const EdgeInsets.only(left: 12, top: 0),
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
                        AppLocalizations.of(context)!.cloudSyncDate(date),
                      ),
                      Text(
                        AppLocalizations.of(context)!
                            .localSyncDate(localSyncedLocalDate),
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
                            if (widget.getMods != null) {
                              await widget.getMods!(json.encode(modConfig),
                                  switchTabs: true);
                            }
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
                        const SizedBox(
                          height: 12,
                        ),
                        FilledButton.icon(
                          onPressed: () async {
                            Map modConfig = {
                              "name": widget.name,
                              "version": widget.mcVersion,
                              "mods": json.decode(widget.mods),
                              "modLoader": widget.modLoader
                            };
                            String content = json.encode(modConfig);
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
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Container(
              margin: const EdgeInsets.only(
                top: 16,
              ),
              child: ExpansionTile(
                maintainState: true,
                expandedAlignment: Alignment.centerLeft,
                title: Text(
                  AppLocalizations.of(context)!.details,
                  style: const TextStyle(fontSize: 24),
                ),
                children: [
                  Container(
                    margin: const EdgeInsets.only(left: 32),
                    child: FutureBuilder(
                      future: () async {
                        http.Response res = await http.get(
                          Uri.parse(
                              "https://api.mrquantumoff.dev/api/v3/quadrant/sync/get?show_owners=true&modpack_id=${widget.modpackId}"),
                          headers: {
                            "User-Agent": await generateUserAgent(),
                            "Authorization": "Bearer ${widget.token}"
                          },
                        );
                        return res;
                      }(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              snapshot.error.toString(),
                            ),
                          );
                        }
                        List<dynamic> modpackRaw =
                            json.decode(snapshot.data!.body);
                        Map modpack = modpackRaw[0];
                        List<dynamic> owners = modpack["owners"];
                        List<Widget> ownersWidgets = [];
                        for (var owner in owners) {
                          ownersWidgets.add(
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                owner["admin"]
                                    ? AppLocalizations.of(context)!
                                        .owner(owner["username"])
                                    : owner["username"],
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          );
                        }

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: <Widget>[
                                  Text(
                                    "${AppLocalizations.of(context)!.owners}:",
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ] +
                                ownersWidgets +
                                [
                                  FilledButton.icon(
                                    onPressed: () async {
                                      http.Response res = await http.delete(
                                        Uri.parse(
                                            "https://api.mrquantumoff.dev/api/v2/delete/quadrant_sync"),
                                        headers: {
                                          "User-Agent":
                                              await generateUserAgent(),
                                          "Authorization":
                                              "Bearer ${widget.token}"
                                        },
                                        body: json.encode(
                                          {
                                            "modpack_id": widget.modpackId,
                                            "name": widget.name,
                                          },
                                        ),
                                      );
                                      if (res.statusCode != 200) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(res.body),
                                          ),
                                        );
                                      }
                                      File modpackSyncFile = File(
                                          "${getMinecraftFolder().path}/modpacks/${widget.name}/quadrantSync.json");
                                      if (modpackSyncFile.existsSync()) {
                                        await modpackSyncFile.delete();
                                      }
                                      widget.reload();
                                    },
                                    label: Text(AppLocalizations.of(context)!
                                        .leaveOrDelete),
                                    icon: const Icon(Icons.delete),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(360, 48),
                                    ),
                                  ),
                                ],
                          ),
                        );
                      },
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
