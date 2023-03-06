import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CurseForgePage extends StatefulWidget {
  const CurseForgePage({super.key});

  @override
  State<CurseForgePage> createState() => _CurseForgePageState();
}

class _CurseForgePageState extends State<CurseForgePage> {
  late TextEditingController searchFieldController;
  late List<Widget> searchResults;

  void setSearchResults(List<Widget> newSearchResults) {
    setState(() {
      searchResults = newSearchResults;
    });
  }

  final String apiKey =
      const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");
  @override
  void initState() {
    searchFieldController = TextEditingController();
    super.initState();
    searchResults = [];
  }

  @override
  void dispose() {
    searchFieldController.dispose();
    searchResults = [];
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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

class Mod extends StatefulWidget {
  const Mod({
    super.key,
    required this.name,
    required this.description,
    required this.modIconUrl,
    required this.id,
  });

  final String name;
  final String description;
  final String modIconUrl;
  final int id;

  @override
  State<Mod> createState() => _ModState();
}

class _ModState extends State<Mod> {
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
          List<double> versions = [];
          for (var v in vrs) {
            int dotCount = 0;
            for (var c in v.toString().characters) {
              if (c == ".") dotCount++;
            }
            if (dotCount == 3 &&
                v.toString().replaceAll("Update ", "").startsWith("1.")) {
              var finVerFormat = double.parse(
                  "${v.toString().replaceAll("Update ", "").split(".").first}.${v.toString().replaceAll("Update ", "").split(".")[1]}");
              if (!versions.contains(finVerFormat)) {
                versions.add(finVerFormat);
                versions.sort(
                  (a, b) {
                    if (double.parse(a.toString().split(".").last) >
                        double.parse(b.toString().split(".").last)) {
                      return 0;
                    } else {
                      return 1;
                    }
                  },
                );
              }
            }
          }
          // double selectedVersion = 1.12;

          List<DropdownMenuItem> versionItems = [];

          for (var version in versions) {
            versionItems.add(
              DropdownMenuItem(
                child: Text(
                  version.toString(),
                ),
              ),
            );
          }

          debugPrint("$versions");
          // ignore: use_build_context_synchronously
          showDialog(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: Text(AppLocalizations.of(context)!.installModpacks),
              content: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton(
                    items: versionItems,
                    onChanged: (value) {},
                  ),
                ],
              ),
              actions: [
                TextButton.icon(
                  onPressed: () async {},
                  icon: const Icon(Icons.file_download),
                  label: Text(AppLocalizations.of(context)!.download),
                )
              ],
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
