import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
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
    required this.username,
    this.getMods,
  });

  final String modpackId;
  final String name;
  final String mods;
  final String mcVersion;
  final String modLoader;
  final int lastSynced;
  final Function(String) reload;
  final String username;
  Function(String rawFile, {bool switchTabs, int newTimestamp})? getMods;
  final String token;

  @override
  State<SyncedModpack> createState() => _SyncedModpackState();
}

class _SyncedModpackState extends State<SyncedModpack> {
  bool invitedAdmin = false;

  @override
  Widget build(BuildContext context) {
    var tag = Localizations.maybeLocaleOf(context)?.toLanguageTag();

    String date = DateFormat('EEEE, dd.MM.yy, HH:mm', tag)
        .format(DateTime.fromMillisecondsSinceEpoch(widget.lastSynced));

    String localSyncedLocalDate = "-";
    int localSyncDateMillis = 0;

    File modpackSyncFile = File(
        "${getMinecraftFolder().path}/modpacks/${widget.name}/quadrantSync.json");
    if (modpackSyncFile.existsSync()) {
      try {
        localSyncedLocalDate = DateFormat('EEEE, dd.MM.yy, HH:mm', tag).format(
            DateTime.fromMillisecondsSinceEpoch(json
                .decode(modpackSyncFile.readAsStringSync())["last_synced"]));
        localSyncDateMillis =
            json.decode(modpackSyncFile.readAsStringSync())["last_synced"];
      } catch (e) {
        debugPrint("$e");
      }
    }

    Future<dynamic> getOwners() async {
      http.Response res = await http.get(
        Uri.parse(
            "https://api.mrquantumoff.dev/api/v3/quadrant/sync/get?show_owners=true&modpack_id=${widget.modpackId}"),
        headers: {
          "User-Agent": await generateUserAgent(),
          "Authorization": "Bearer ${widget.token}"
        },
      );

      return res;
    }

    return Visibility(
      maintainAnimation: true,
      maintainState: true,
      maintainSize: true,
      child: Animate(
        effects: [
          MoveEffect(
              begin: const Offset(0, 850), duration: 200.ms, delay: 100.ms),
          BlurEffect(
            end: const Offset(0, 0),
            begin: const Offset(10, 10),
            delay: 200.ms,
          ),
        ],
        child: Card(
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
                                  await widget.getMods!(
                                    json.encode(modConfig),
                                    switchTabs: true,
                                    newTimestamp: widget.lastSynced,
                                  );
                                }
                              },
                              icon: (localSyncDateMillis < widget.lastSynced &&
                                      localSyncDateMillis != 0)
                                  ? const Icon(Icons.update)
                                  : const Icon(Icons.download),
                              label: (localSyncDateMillis < widget.lastSynced &&
                                      localSyncDateMillis != 0)
                                  ? Text(AppLocalizations.of(context)!.update)
                                  : Text(
                                      AppLocalizations.of(context)!.download),
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
                    collapsedShape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(24),
                      ),
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(24),
                      ),
                    ),
                    title: Text(
                      AppLocalizations.of(context)!.details,
                      style: const TextStyle(fontSize: 24),
                    ),
                    children: [
                      Container(
                        margin: const EdgeInsets.only(left: 32),
                        child: FutureBuilder(
                          future: getOwners(),
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
                            List<dynamic> modpackRaw = json
                                .decode(utf8.decode(snapshot.data!.bodyBytes));
                            Map modpack = modpackRaw[0];
                            List<dynamic> owners = modpack["owners"];
                            String modpackId = modpack["modpack_id"];
                            List<Widget> ownersWidgets = [];
                            debugPrint(widget.username);
                            bool isAdmin = false;
                            for (var owner in owners) {
                              if (owner["username"] == widget.username &&
                                  owner["admin"] == true) {
                                isAdmin = true;
                              }
                            }
                            for (var owner in owners) {
                              ownersWidgets.add(
                                Row(
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: Text(
                                        owner["admin"]
                                            ? AppLocalizations.of(context)!
                                                .owner(owner["username"])
                                            : owner["username"],
                                        style: const TextStyle(fontSize: 18),
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 12,
                                    ),
                                    isAdmin &&
                                            owner["username"] != widget.username
                                        ? TextButton.icon(
                                            onPressed: () async {
                                              http.Response res =
                                                  await http.delete(
                                                Uri.parse(
                                                    "https://api.mrquantumoff.dev/api/v3/quadrant/sync/kick"),
                                                headers: {
                                                  "User-Agent":
                                                      await generateUserAgent(),
                                                  "Authorization":
                                                      "Bearer ${widget.token}",
                                                  "Content-Type":
                                                      "application/json",
                                                },
                                                body: json.encode(
                                                  {
                                                    "modpack_id":
                                                        widget.modpackId,
                                                    "username":
                                                        owner["username"],
                                                  },
                                                ),
                                              );
                                              debugPrint(
                                                  "${res.body} (${res.statusCode})");
                                              if (res.statusCode == 200) {
                                                widget.reload(res.body);
                                              } else {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(res.body),
                                                  ),
                                                );
                                              }
                                              setState(() {});
                                            },
                                            label: Text(
                                              AppLocalizations.of(context)!
                                                  .kick,
                                            ),
                                            icon:
                                                const Icon(Icons.person_remove),
                                            style: FilledButton.styleFrom(
                                              foregroundColor: Colors.redAccent,
                                            ),
                                            // style:
                                          )
                                        : Container()
                                  ],
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
                                      const SizedBox(
                                        height: 12,
                                      ),
                                      Row(
                                        children: [
                                          FilledButton.icon(
                                            onPressed: () async {
                                              http.Response res =
                                                  await http.delete(
                                                Uri.parse(
                                                    "https://api.mrquantumoff.dev/api/v3/quadrant/sync/delete"),
                                                headers: {
                                                  "User-Agent":
                                                      await generateUserAgent(),
                                                  "Authorization":
                                                      "Bearer ${widget.token}"
                                                },
                                                body: json.encode(
                                                  {
                                                    "modpack_id": modpackId,
                                                  },
                                                ),
                                              );
                                              if (res.statusCode != 200) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                        "${res.body} (${res.statusCode})"),
                                                  ),
                                                );
                                              }
                                              File modpackSyncFile = File(
                                                  "${getMinecraftFolder().path}/modpacks/${widget.name}/quadrantSync.json");
                                              if (modpackSyncFile
                                                  .existsSync()) {
                                                await modpackSyncFile.delete();
                                              }
                                              widget.reload("asdafaf");
                                            },
                                            label: Text(
                                              isAdmin
                                                  ? AppLocalizations.of(
                                                          context)!
                                                      .delete
                                                  : AppLocalizations.of(
                                                          context)!
                                                      .leave,
                                            ),
                                            icon: const Icon(Icons.delete),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: Colors.redAccent,
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(
                                            width: 12,
                                          ),
                                          isAdmin
                                              ? FilledButton.icon(
                                                  onPressed: () async {
                                                    showDialog(
                                                      context: context,
                                                      builder: (context) {
                                                        TextEditingController
                                                            usernameController =
                                                            TextEditingController();
                                                        return Dialog(
                                                          child:
                                                              StatefulBuilder(
                                                            builder: (context,
                                                                setState) {
                                                              return SizedBox(
                                                                height: 240,
                                                                width: 540,
                                                                child: Column(
                                                                  children: [
                                                                    Container(
                                                                      margin: const EdgeInsets
                                                                          .only(
                                                                          top:
                                                                              24),
                                                                      child:
                                                                          SizedBox(
                                                                        width:
                                                                            500,
                                                                        child:
                                                                            TextField(
                                                                          controller:
                                                                              usernameController,
                                                                          decoration:
                                                                              InputDecoration(
                                                                            border:
                                                                                const OutlineInputBorder(),
                                                                            labelText:
                                                                                AppLocalizations.of(context)!.username,
                                                                            icon:
                                                                                const Icon(Icons.person),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    Container(
                                                                      margin: const EdgeInsets
                                                                          .symmetric(
                                                                          vertical:
                                                                              12,
                                                                          horizontal:
                                                                              12),
                                                                      child:
                                                                          Row(
                                                                        children: [
                                                                          Switch(
                                                                            value:
                                                                                invitedAdmin,
                                                                            onChanged: (value) =>
                                                                                {
                                                                              setState(
                                                                                () {
                                                                                  invitedAdmin = value;
                                                                                },
                                                                              ),
                                                                            },
                                                                          ),
                                                                          const SizedBox(
                                                                            width:
                                                                                12,
                                                                          ),
                                                                          Text(
                                                                            AppLocalizations.of(context)!.admin,
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                    Container(
                                                                      margin: const EdgeInsets
                                                                          .only(
                                                                          right:
                                                                              24,
                                                                          top:
                                                                              48),
                                                                      child:
                                                                          Row(
                                                                        crossAxisAlignment:
                                                                            CrossAxisAlignment.end,
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.end,
                                                                        children: [
                                                                          FilledButton
                                                                              .tonalIcon(
                                                                            onPressed:
                                                                                Get.back,
                                                                            icon:
                                                                                const Icon(
                                                                              Icons.cancel,
                                                                            ),
                                                                            label:
                                                                                Text(
                                                                              AppLocalizations.of(context)!.cancel,
                                                                            ),
                                                                          ),
                                                                          const SizedBox(
                                                                            width:
                                                                                12,
                                                                          ),
                                                                          FilledButton
                                                                              .icon(
                                                                            onPressed:
                                                                                () async {
                                                                              http.Response result = await http.post(
                                                                                Uri.parse("https://api.mrquantumoff.dev/api/v3/quadrant/sync/invite"),
                                                                                headers: {
                                                                                  "User-Agent": await generateUserAgent(),
                                                                                  "Authorization": "Bearer ${widget.token}",
                                                                                  "Content-Type": "application/json",
                                                                                },
                                                                                body: json.encode(
                                                                                  {
                                                                                    "modpack_id": widget.modpackId,
                                                                                    "username": usernameController.text,
                                                                                    "admin": invitedAdmin,
                                                                                  },
                                                                                ),
                                                                              );
                                                                              debugPrint("${result.body} ${result.statusCode}");

                                                                              if (result.statusCode != 200) {
                                                                                Get.back();

                                                                                ScaffoldMessenger.of(context).showSnackBar(
                                                                                  SnackBar(
                                                                                    content: Text(result.body),
                                                                                  ),
                                                                                );
                                                                              }
                                                                              Get.back();
                                                                            },
                                                                            icon:
                                                                                const Icon(
                                                                              Icons.send,
                                                                            ),
                                                                            label:
                                                                                Text(
                                                                              AppLocalizations.of(context)!.invite,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        );
                                                      },
                                                    );
                                                  },
                                                  label: Text(
                                                    AppLocalizations.of(
                                                            context)!
                                                        .invite,
                                                  ),
                                                  icon: const Icon(
                                                      Icons.person_add),
                                                  // style:
                                                )
                                              : Container(),
                                        ],
                                      )
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
        ),
      ),
    );
  }
}
