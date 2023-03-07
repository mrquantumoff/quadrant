// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:mcmodpackmanager_reborn/backend.dart';

class UserAgentClient extends http.BaseClient {
  final String userAgent;
  final http.Client _inner;

  UserAgentClient(this.userAgent, this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['user-agent'] = userAgent;
    request.headers['X-API-Key'] =
        const String.fromEnvironment("ETERNAL_API_TOKEN").replaceAll("\"", "");
    return _inner.send(request);
  }
}

class CurseForgePage extends StatefulWidget {
  const CurseForgePage({super.key});

  @override
  State<CurseForgePage> createState() => _CurseForgePageState();
}

class _CurseForgePageState extends State<CurseForgePage> {
  late TextEditingController searchFieldController;
  late List<Widget> searchResults;
  late bool areButtonsEnabled;

  void setSearchResults(List<Widget> newSearchResults) {
    setState(() {
      searchResults = newSearchResults;
    });
  }

  void setAreButtonsEnabled(bool newAreButtonsEnabled) {
    setState(() {
      areButtonsEnabled = newAreButtonsEnabled;
    });
  }

  final String apiKey =
      const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");
  @override
  void initState() {
    areButtonsEnabled = true;
    searchFieldController = TextEditingController();
    super.initState();
    searchResults = [];
  }

  @override
  void dispose() {
    areButtonsEnabled = false;
    searchFieldController.dispose();
    searchResults = [];
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: areButtonsEnabled
              ? () {
                  Get.back();
                }
              : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.of(context)!
                          .downloadIsAlreadyInProgress),
                    ),
                  );
                },
        ),
        title: Text(AppLocalizations.of(context)!.curseforge),
      ),
      body: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: searchFieldController,
                    ),
                  ),
                  IconButton(
                      onPressed: () async {
                        if (searchFieldController.text.trim() == "") return;
                        setSearchResults(
                          searchResults = [const CircularProgressIndicator()],
                        );
                        http.Response gamesResponse = await http.get(
                            Uri.parse("https://api.curseforge.com/v1/games"),
                            headers: {
                              "User-Agent": "MinecraftModpackManager",
                              "X-API-Key": apiKey
                            });
                        int id = -1;
                        Map responseData = json.decode(gamesResponse.body);
                        for (var game in responseData["data"]) {
                          if (game["name"].toString().toLowerCase() ==
                              "minecraft") {
                            id = game["id"];
                          }
                        }
                        if (id == -1) {
                          return;
                        }
                        String searchText = Uri.encodeQueryComponent(
                            searchFieldController.text.trim());
                        debugPrint(searchText);
                        Uri uri = Uri.parse(
                          'https://api.curseforge.com/v1/mods/search?gameId=$id&classId=6&searchFilter=$searchText',
                        );
                        debugPrint(uri.toString());
                        http.Response response = await http.get(uri, headers: {
                          "User-Agent": "MinecraftModpackManager",
                          "X-API-Key": apiKey,
                        });
                        Map responseJson = json.decode(response.body);
                        List<Widget> widgets = [];
                        for (var mod in responseJson["data"]) {
                          try {
                            String name = mod["name"];
                            String summary = mod["summary"];
                            int modId = mod["id"];
                            String modIconUrl =
                                "https://github.com/mrquantumoff/mcmodpackmanager_reborn/raw/master/assets/icons/logo.png";
                            try {
                              modIconUrl = mod["logo"]["url"];
                              // ignore: empty_catches
                            } catch (e) {}
                            widgets.add(
                              Mod(
                                description: summary,
                                name: name,
                                id: modId,
                                modIconUrl: modIconUrl,
                                areButttonsActive: areButtonsEnabled,
                                setAreButtonsActive: setAreButtonsEnabled,
                              ),
                            );
                          } catch (e) {
                            debugPrint("$e");
                          }
                        }
                        setSearchResults(widgets);
                      },
                      icon: const Icon(Icons.search))
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: searchResults,
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ignore: must_be_immutable
class Mod extends StatefulWidget {
  Mod(
      {super.key,
      required this.name,
      required this.description,
      required this.modIconUrl,
      required this.id,
      required this.areButttonsActive,
      required this.setAreButtonsActive});

  final String name;
  final String description;
  final String modIconUrl;
  final int id;
  bool areButttonsActive;
  Function(bool) setAreButtonsActive;

  @override
  State<Mod> createState() => _ModState();
}

class ModFile {
  ModFile(
      {required this.downloadUrl,
      required this.fileName,
      required this.gameVersions,
      required this.fileDate});
  String downloadUrl = "";
  String fileName = "";
  List<dynamic> gameVersions = [];
  DateTime fileDate = DateTime.now();
}

class _ModState extends State<Mod> {
  late TextEditingController versionFieldController;
  late TextEditingController apiFieldController;
  late TextEditingController modpackFieldController;
  late double progressValue;

  @override
  void initState() {
    super.initState();
    progressValue = 0;

    versionFieldController = TextEditingController();
    apiFieldController = TextEditingController();
    modpackFieldController = TextEditingController();
  }

  @override
  void dispose() {
    super.dispose();
    progressValue = 0;
  }

  setProgressValue(double newValue) {
    setState(() {
      progressValue = newValue;
    });
  }

  final String apiKey =
      const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");

  @override
  Widget build(BuildContext context) {
    String desc = widget.description.characters.length >= 48
        ? widget.description.replaceRange(48, null, "...")
        : widget.description;
    return Container(
      margin: const EdgeInsets.all(12),
      child: InkWell(
        onTap: () async {
          Uri uri = Uri.parse(
            'https://api.curseforge.com/v1/games/423/versions',
          );
          List<dynamic> vrs = json.decode((await http.get(
            uri,
            headers: {
              "User-Agent": "MinecraftModpackManager",
              "X-API-Key": apiKey,
            },
          ))
              .body)["data"][0]["versions"];
          List<String> versions = [];
          for (var v in vrs) {
            int dotCount = 0;
            for (var c in v.toString().characters) {
              if (c == ".") dotCount++;
            }
            if (dotCount == 3 &&
                v.toString().replaceAll("Update ", "").startsWith("1.")) {
              var finVerFormat =
                  "${v.toString().replaceAll("Update ", "").split(".").first}.${v.toString().replaceAll("Update ", "").split(".")[1]}.${v.toString().replaceAll("Update ", "").split(".").last}";
              if (!versions.contains(finVerFormat)) {
                versions.add(finVerFormat);
                versions.sort(
                  (a, b) {
                    if (double.parse(a.toString().split(".")[1]) >
                        double.parse(b.toString().split(".")[1])) {
                      return 0;
                    } else {
                      return 1;
                    }
                  },
                );
              }
            }
          }
          List<DropdownMenuEntry> versionItems = [];
          List<DropdownMenuEntry> modpackItems = [];

          for (var version in versions) {
            versionItems.add(
              DropdownMenuEntry(label: version.toString(), value: version),
            );
          }

          List<String> modpacks = getModpacks();

          for (var modpack in modpacks) {
            modpackItems.add(
              DropdownMenuEntry(label: modpack, value: modpack),
            );
          }

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) => AlertDialog(
              title: Text(AppLocalizations.of(context)!.installModpacks),
              actions: [
                TextButton.icon(
                    onPressed: widget.areButttonsActive
                        ? () {
                            Get.back(closeOverlays: true);
                            Get.back();
                          }
                        : () {},
                    icon: const Icon(Icons.cancel),
                    label: Text(AppLocalizations.of(context)!.cancel)),
                TextButton.icon(
                  onPressed: widget.areButttonsActive
                      ? () async {
                          String version = versionFieldController.value.text;
                          String api = apiFieldController.value.text;
                          String modpack = modpackFieldController.value.text;
                          debugPrint(api);
                          Uri getFilesUri = Uri.parse(
                              "https://api.curseforge.com/v1/mods/${widget.id}/files?gameVersion=${version.trim()}&modLoaderType=${api.trim()}");
                          debugPrint("Installing mods url: $getFilesUri");
                          widget.setAreButtonsActive(false);
                          http.Response response =
                              await http.get(getFilesUri, headers: {
                            "User-Agent": "MinecraftModpackManager",
                            "X-API-Key": apiKey,
                          });
                          Map responseJson = json.decode(response.body);
                          debugPrint(responseJson.toString());
                          List<ModFile> fileMod = [];
                          if ((responseJson["data"] as List<dynamic>) == []) {
                            widget.setAreButtonsActive(true);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.of(context)!.noVersion,
                                ),
                              ),
                            );
                            Get.back(closeOverlays: true);
                            Get.back();
                          }
                          debugPrint(responseJson.toString());
                          for (var mod in responseJson["data"]) {
                            DateTime fileDate = DateTime.parse(mod["fileDate"]);
                            List<dynamic> gameVersions = mod["gameVersions"];
                            String fileName = mod["fileName"];
                            String downloadUrl = mod["downloadUrl"];

                            fileMod.add(
                              ModFile(
                                fileDate: fileDate,
                                gameVersions: gameVersions,
                                fileName: fileName,
                                downloadUrl: downloadUrl,
                              ),
                            );
                          }
                          fileMod.sort(
                            (a, b) => b.fileDate.compareTo(a.fileDate),
                          );
                          debugPrint(fileMod.toString());
                          if (fileMod.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    AppLocalizations.of(context)!.noVersion),
                              ),
                            );
                            widget.setAreButtonsActive(true);
                            Get.back(closeOverlays: true);
                            Get.back();

                            return;
                          }
                          var mod = fileMod[0];
                          // http.Response res = await http
                          //     .get(Uri.parse(mod.downloadUrl), headers: {
                          //   "User-Agent": "MinecraftModpackManager",
                          //   "X-API-Key": apiKey,
                          // });
                          var request = http.Request(
                            "GET",
                            Uri.parse(mod.downloadUrl),
                          );
                          final http.StreamedResponse streamedResponse =
                              await UserAgentClient(
                                      "MinecraftModpackManager", http.Client())
                                  .send(request);
                          final contentLength = streamedResponse.contentLength;

                          File modDestFile = File(
                              "${getMinecraftFolder().path}/modpacks/$modpack/${mod.fileName}");

                          if (await modDestFile.exists()) {
                            modDestFile.delete();
                          }
                          debugPrint(modDestFile.path);
                          List<int> bytes = [];
                          streamedResponse.stream.listen(
                            (List<int> newBytes) {
                              bytes.addAll(newBytes);
                              final downloadedLength = bytes.length;
                              setProgressValue(
                                  downloadedLength / (contentLength ?? 1));
                              debugPrint(progressValue.toString());
                            },
                            onDone: () async {
                              await modDestFile.writeAsBytes(bytes,
                                  flush: true);
                              setProgressValue(1);
                              debugPrint("Downloaded");
                              widget.setAreButtonsActive(true);

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(AppLocalizations.of(context)!
                                      .downloadSuccess),
                                ),
                              );
                              Get.back(closeOverlays: true);
                              Get.back();
                            },
                            onError: (e) {
                              debugPrint(e);
                            },
                            cancelOnError: true,
                          );
                        }
                      : () {},
                  icon: const Icon(Icons.file_download),
                  label: Text(AppLocalizations.of(context)!.download),
                )
              ],
              content: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: DropdownMenu(
                      controller: versionFieldController,
                      dropdownMenuEntries: versionItems,
                      label: Text(AppLocalizations.of(context)!.chooseVersion),
                      width: 240,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: DropdownMenu(
                      label: Text(
                          AppLocalizations.of(context)!.choosePreferredAPI),
                      controller: apiFieldController,
                      dropdownMenuEntries: const [
                        DropdownMenuEntry(label: "Fabric", value: "Fabric"),
                        DropdownMenuEntry(label: "Forge", value: "Forge"),
                        DropdownMenuEntry(label: "Quilt", value: "Quilt"),
                        DropdownMenuEntry(label: "Rift", value: "Rift"),
                      ],
                      width: 240,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: DropdownMenu(
                      label: Text(AppLocalizations.of(context)!.chooseModpack),
                      controller: modpackFieldController,
                      dropdownMenuEntries: modpackItems,
                      width: 240,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: CircularProgressIndicator(
                      value: progressValue,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: Card(
          elevation: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsetsDirectional.only(start: 12, top: 6.5),
                child: Image(
                  image: NetworkImage(widget.modIconUrl),
                  alignment: Alignment.centerRight,
                  height: 84,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 15),
                    child: Text(
                      widget.name,
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    child: Text(
                      desc,
                      style: const TextStyle(color: Colors.grey, fontSize: 24),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
