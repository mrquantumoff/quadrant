// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'web/mod.dart';

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

  Future<List<Mod>> searchMods(String searchText, ModClass modsClass) async {
    Uri uri = Uri.parse(
      'https://api.curseforge.com/v1/mods/search?gameId=432&classId=${modsClass.value}&searchFilter=$searchText&sortOrder=desc',
    );
    debugPrint(uri.toString());
    http.Response response = await http.get(uri, headers: {
      "User-Agent": "MinecraftModpackManager",
      "X-API-Key": apiKey,
    });
    Map responseJson = json.decode(response.body);
    List<Mod> widgets = [];
    for (var mod in responseJson["data"]) {
      try {
        String name = mod["name"];
        String summary = mod["summary"];
        int modId = mod["id"];

        String modIconUrl =
            "https://github.com/mrquantumoff/mcmodpackmanager_reborn/raw/master/assets/icons/logo.png";
        int downloadCount = mod["downloadCount"];
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
            downloadCount: downloadCount,
            source: ModSource.curseForge,
            modClass: modsClass,
          ),
        );
      } catch (e) {
        debugPrint("$e");
      }
    }
    widgets.sort((a, b) {
      return (a.downloadCount > b.downloadCount) ? 0 : 1;
    });
    return widgets;
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
        title: Text(AppLocalizations.of(context)!.web),
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
                    child: Container(
                      margin: const EdgeInsets.only(right: 20),
                      child: TextField(
                        decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            hintText:
                                AppLocalizations.of(context)!.searchForMods),
                        controller: searchFieldController,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      if (searchFieldController.text.trim() == "") return;
                      setSearchResults(
                        searchResults = [
                          Container(
                              margin: const EdgeInsets.only(
                                  top: 50, left: 20, right: 20),
                              child: const LinearProgressIndicator())
                        ],
                      );

                      String searchText = Uri.encodeQueryComponent(
                          searchFieldController.text.trim());
                      debugPrint(searchText);
                      List<Mod> mods =
                          await searchMods(searchText, ModClass.mod);
                      List<Mod> resourcePacks =
                          await searchMods(searchText, ModClass.resourcePack);
                      List<Mod> widgets = mods + resourcePacks;
                      widgets.sort((a, b) {
                        return (a.downloadCount > b.downloadCount) ? 0 : 1;
                      });
                      setSearchResults(widgets);
                    },
                    icon: const Icon(Icons.search),
                    label: Text(AppLocalizations.of(context)!.search),
                  )
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
