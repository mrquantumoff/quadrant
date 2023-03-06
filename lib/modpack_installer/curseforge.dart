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
  @override
  void initState() {
    super.initState();
    searchResults = [];
    searchFieldController = TextEditingController();
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
                        setState(() {
                          searchResults = [const CircularProgressIndicator()];
                        });
                        http.Response gamesResponse = await http.get(
                            Uri.parse("https://api.curseforge.com/v1/games"),
                            headers: {
                              "User-Agent": "MinecraftModpackManager",
                              "X-Api-Key": const String.fromEnvironment(
                                      "ETERNAL_API_KEY")
                                  .replaceAll("\"", "")
                            });
                        int id = -1;
                        Map responseData = json.decode(gamesResponse.body);
                        for (var game in responseData["data"]) {
                          if (game["name"].toString().toLowerCase() ==
                              "minecraft") {
                            id = game["id"];
                            debugPrint("$id");
                          }
                        }
                        if (id == -1) {
                          return;
                        }
                        http.Response response = await http.get(
                            Uri.parse(
                                "https://api.curseforge.com/v1/mods/search?gameId=$id?searchFilter=${searchFieldController.text}"),
                            headers: {
                              "User-Agent": "MinecraftModpackManager",
                              "X-Api-Key": const String.fromEnvironment(
                                      "ETERNAL_API_KEY")
                                  .replaceAll("\"", "")
                            });
                        Map responseJson = json.decode(response.body);
                        List<Widget> widgets = [];

                        for (var mod in responseJson["data"]) {
                          String name = mod["name"];
                          String summary = mod["summary"];
                          int modId = mod["id"];
                          String modIconUrl = mod["logo"]["url"];
                          widgets.add(
                            Mod(
                              description: summary,
                              name: name,
                              id: modId,
                              modIconUrl: modIconUrl,
                            ),
                          );
                          setState(() {
                            debugPrint("Modified search results");
                            searchResults = widgets;
                          });
                        }
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
  @override
  Widget build(BuildContext context) {
    String desc = widget.description.characters.length >= 48
        ? widget.description.replaceRange(48, null, "...")
        : widget.description;
    return Container(
      margin: const EdgeInsets.all(12),
      child: InkWell(
        child: Card(
          elevation: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
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
              Container(
                margin: const EdgeInsetsDirectional.only(start: 220, top: 6.5),
                child: Image(
                  image: NetworkImage(widget.modIconUrl),
                  alignment: Alignment.centerRight,
                  height: 84,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
