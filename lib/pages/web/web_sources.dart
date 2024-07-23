// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage_qnt/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:quadrant/draggable_appbar.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/web/filter_mods.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';
import 'dart:convert';
import 'package:quadrant/pages/web/mod/mod.dart';
import 'package:quadrant/pages/web/modpack_update_page/modpack_update_page.dart/update_modpack.dart';

enum SortBy {
  name,
  downloads,
  sourceModrinth,
  sourceCurseforge,
}

class UserAgentClient extends http.BaseClient {
  final String userAgent;
  final http.Client _inner;

  UserAgentClient(this.userAgent, this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['user-agent'] = userAgent;
    request.headers['X-API-Key'] =
        const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");
    return _inner.send(request);
  }
}

class WebSourcesPage extends StatefulWidget {
  const WebSourcesPage({
    super.key,
    this.filterOn = false,
    this.shadersOn = true,
    this.modsOn = true,
    this.resourcePacksOn = true,
  });

  final bool filterOn;

  final bool shadersOn;
  final bool resourcePacksOn;
  final bool modsOn;

  @override
  State<WebSourcesPage> createState() => _WebSourcesPageState();
}

class _WebSourcesPageState extends State<WebSourcesPage> {
  TextEditingController searchFieldController = TextEditingController();
  List<Mod> searchResults = [];
  bool areButtonsEnabled = true;
  bool isLoading = false;
  bool isSearched = false;

  void setIsLoading(bool value) {
    if (isSearched = false) {
      isSearched = true;
    }
    setState(() {
      isLoading = value;
    });
  }

  void setSearchResults(List<Mod> newSearchResults) {
    setState(() {
      searchResults = newSearchResults;
    });
  }

  void setAreButtonsEnabled(bool newAreButtonsEnabled) {
    setState(() {
      areButtonsEnabled = newAreButtonsEnabled;
    });
  }

  Future<List<Mod>> searchMods(
      String query, ModClass modsClass, ModSource modSource) async {
    List<Mod> widgets = [];

    if (modSource == ModSource.curseForge) {
      String rawUri =
          'https://api.curseforge.com/v1/mods/search?gameId=432&searchFilter=$query&sortOrder=desc&classId=${modsClass.value}';

      if (modsClass == ModClass.shaderPack) {
        rawUri = '$rawUri&categoryId=4547';
      }

      if (widget.filterOn) {
        rawUri = '$rawUri&gameVersion=${GetStorage().read("lastUsedVersion")}';
      }
      if (widget.filterOn && modsClass == ModClass.mod) {
        rawUri = '$rawUri&modLoaderType=${GetStorage().read("lastUsedAPI")}';
      }

      Uri uri = Uri.parse(rawUri);
      debugPrint(uri.toString());
      http.Response response = await http.get(uri, headers: {
        "User-Agent": await generateUserAgent(),
        "X-API-Key": apiKey,
      });
      Map responseJson = json.decode(utf8.decode(response.bodyBytes));
      for (Map mod in responseJson["data"]) {
        try {
          String name = mod["name"];
          String summary = mod["summary"];
          int modId = mod["id"];

          String modIconUrl =
              "https://github.com/mrquantumoff/quadrant/raw/master/assets/icons/logo.png";
          int downloadCount = mod["downloadCount"];
          try {
            String mModIconUrl = mod["logo"]["thumbnailUrl"].toString().trim();
            if (mModIconUrl == "") {
              throw Exception("No proper icon");
            }
            Uri.parse(mModIconUrl);
            modIconUrl = mModIconUrl;
            // ignore: empty_catches
          } catch (e) {}
          List<String> screenshots = [];
          for (dynamic screenshot in mod["screenshots"]) {
            screenshots.add(screenshot["thumbnailUrl"]);
          }
          String slug = mod["slug"];
          widgets.add(
            Mod(
              description: summary,
              name: name,
              id: modId.toString(),
              modIconUrl: modIconUrl,
              slug: slug,
              rawMod: mod,
              setAreParentButtonsActive: setAreButtonsEnabled,
              downloadCount: downloadCount,
              source: ModSource.curseForge,
              modClass: modsClass,
              autoInstall: GetStorage().read("experimentalFeatures") == true &&
                  widget.filterOn,
              thumbnailUrl: screenshots,
            ),
          );
        } catch (e) {
          debugPrint("$e");
        }
      }
    } else {
      String modType = modsClass.name.toLowerCase();
      modType = modType.replaceAll("shaderpack", "shader");
      debugPrint(modType);
      String facets = '["project_type:$modType"]';

      if (widget.filterOn) {
        facets =
            '$facets, ["versions:${GetStorage().read("lastUsedVersion")}"]';
      }
      if (widget.filterOn && modsClass == ModClass.mod) {
        facets = '$facets, ["categories:${GetStorage().read("lastUsedAPI")}"]';
      }
      String rawUri =
          'https://api.modrinth.com/v2/search?query=$query&limit=100&facets=[$facets]';
      Uri uri = Uri.parse(
        rawUri,
      );
      debugPrint(uri.toString());
      http.Response response = await http.get(uri, headers: {
        "User-Agent": await generateUserAgent(),
        "X-API-Key": apiKey,
      });
      Map responseJson = json.decode(utf8.decode(response.bodyBytes));
      if (responseJson["hits"] != null) {
        for (var mod in responseJson["hits"]) {
          String name = mod["title"];
          String desc = mod["description"];
          int downloadCount = mod["downloads"];
          String id = mod["project_id"];
          String slug = mod["slug"];
          String icon =
              "https://github.com/mrquantumoff/quadrant/raw/master/assets/icons/logo256.png";
          // Not all mods have icons
          List<String> screenshots = [];

          for (dynamic screenshot in mod["gallery"] ?? []) {
            screenshots.add(screenshot.toString());
          }
          try {
            String mModIconUrl = mod["icon_url"].toString().trim();
            if (mModIconUrl == "") {
              throw Exception("No proper icon");
            }
            Uri.parse(mModIconUrl);
            icon = mModIconUrl;
            // ignore: empty_catches
          } catch (e) {}

          widgets.add(
            Mod(
              description: desc,
              name: name,
              id: id,
              rawMod: mod,
              slug: slug,
              modIconUrl: icon,
              setAreParentButtonsActive: setAreButtonsEnabled,
              downloadCount: downloadCount,
              source: ModSource.modRinth,
              modClass: modsClass,
              autoInstall: widget.filterOn,
              thumbnailUrl: screenshots,
            ),
          );
        }
      }
    }

    widgets.sort((a, b) {
      int aCount = a.downloadCount;
      int bCount = b.downloadCount;

      return bCount - aCount;
    });

    return widgets;
  }

  final String apiKey =
      const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");
  @override
  void initState() {
    super.initState();
    isLoading = true;
    // searchModsFunction(forceSearch: true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      List<Mod> curseForgeMods =
          await searchMods("", ModClass.mod, ModSource.curseForge);
      List<Mod> modRinthMods =
          await searchMods("", ModClass.mod, ModSource.modRinth);
      List<Mod> finalMods = curseForgeMods + modRinthMods;
      finalMods.shuffle();
      if (!isSearched && context.mounted) {
        setState(() {
          isLoading = false;
          searchResults = finalMods;
        });
      }
    });
  }

  @override
  void dispose() {
    areButtonsEnabled = false;
    searchFieldController.dispose();
    searchResults = [];
    isSearched = true;
    super.dispose();
  }

  void searchModsFunction({bool forceSearch = false}) async {
    bool isCurseForgeAllowed = await checkCurseForge();
    setIsLoading(true);

    String searchText =
        Uri.encodeQueryComponent(searchFieldController.text.trim());
    debugPrint(searchText);
    List<Mod> mods = [];
    List<Mod> resourcePacks = [];
    List<Mod> shaderPacks = [];
    List<Mod> modsModrinth = [];
    List<Mod> resourcePacksModrinth = [];
    List<Mod> shaderPacksModrinth = [];
    if (GetStorage().read("curseForge") && isCurseForgeAllowed) {
      if (widget.modsOn) {
        mods = await searchMods(searchText, ModClass.mod, ModSource.curseForge);
      }
      if (widget.resourcePacksOn) {
        resourcePacks = await searchMods(
            searchText, ModClass.resourcePack, ModSource.curseForge);
      }
      if (widget.shadersOn) {
        shaderPacks = await searchMods(
            searchText, ModClass.shaderPack, ModSource.curseForge);
      }
    }
    if (GetStorage().read("modrinth")) {
      if (widget.modsOn) {
        modsModrinth =
            await searchMods(searchText, ModClass.mod, ModSource.modRinth);
      }
      if (widget.resourcePacksOn) {
        resourcePacksModrinth = await searchMods(
            searchText, ModClass.resourcePack, ModSource.modRinth);
      }
      if (widget.shadersOn) {
        shaderPacksModrinth = await searchMods(
            searchText, ModClass.shaderPack, ModSource.modRinth);
      }
    }
    List<Mod> widgets = mods +
        resourcePacks +
        modsModrinth +
        resourcePacksModrinth +
        shaderPacksModrinth +
        shaderPacks;
    widgets.sort((a, b) {
      return b.downloadCount.compareTo(a.downloadCount);
    });
    setIsLoading(false);
    setSearchResults(widgets);
  }

  Future<bool> checkCurseForge() async {
    final String apiKey =
        const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");
    http.Response res = await http.get(
      Uri.parse("https://api.curseforge.com/v1/games"),
      headers: {"User-Agent": await generateUserAgent(), "X-API-Key": apiKey},
    );
    bool isValid = false;

    if (res.statusCode == 200 && GetStorage().read("curseForge")) {
      var data = json.decode(res.body);
      for (var game in data["data"]) {
        if (game["id"] == 432) {
          isValid = true;
        }
      }

      if (!isValid && GetStorage().read("curseForge")) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.noEternalKey),
          ),
        );
      }
    }

    return isValid;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.filterOn
          ? DraggableAppBar(
              appBar: AppBar(
                leading: Container(),
                title: Text(AppLocalizations.of(context)!.web),
              ),
            )
          : AppBar(
              title: Text(AppLocalizations.of(context)!.web),
            ),
      body: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 16),
            ),
            Container(
              margin: const EdgeInsets.only(right: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      widget.filterOn && areButtonsEnabled
                          ? Container(
                              margin: const EdgeInsets.only(left: 15),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => Get.back(),
                              ),
                            )
                          : Container(),
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.only(
                              right: (widget.filterOn ? 20 : 10),
                              left: (widget.filterOn ? 15 : 10)),
                          child: SearchBar(
                            controller: searchFieldController,
                            leading: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              child: const Icon(
                                Icons.search,
                                color: Colors.grey,
                                size: 24,
                              ),
                            ),
                            trailing: [
                              Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: PopupMenuButton(
                                  icon: const Icon(Icons.sort),
                                  tooltip: AppLocalizations.of(context)!.sortBy,
                                  onSelected: (value) {
                                    List<Mod> newResults =
                                        List.from(searchResults);
                                    switch (value) {
                                      case SortBy.downloads:
                                        newResults.sort(
                                          (a, b) =>
                                              b.downloadCount - a.downloadCount,
                                        );
                                        break;
                                      case SortBy.name:
                                        newResults.sort(
                                          (a, b) => a.name.compareTo(b.name),
                                        );
                                        break;
                                      case SortBy.sourceModrinth:
                                        newResults.sort(
                                          (a, b) => b.source.name
                                              .compareTo(a.source.name),
                                        );
                                        break;
                                      case SortBy.sourceCurseforge:
                                        newResults.sort(
                                          (a, b) => a.source.name
                                              .compareTo(b.source.name),
                                        );
                                        break;
                                    }
                                    setSearchResults(newResults);
                                  },
                                  itemBuilder: (context) {
                                    return [
                                      PopupMenuItem(
                                        value: SortBy.downloads,
                                        child: Text(
                                            AppLocalizations.of(context)!
                                                .downloadCount),
                                      ),
                                      PopupMenuItem(
                                        value: SortBy.name,
                                        child: Text(
                                            AppLocalizations.of(context)!.name),
                                      ),
                                      PopupMenuItem(
                                        value: SortBy.sourceModrinth,
                                        child: Text(
                                          AppLocalizations.of(context)!
                                              .sourceModrinth,
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: SortBy.sourceCurseforge,
                                        child: Text(
                                          AppLocalizations.of(context)!
                                              .sourceCurseforge,
                                        ),
                                      ),
                                    ];
                                  },
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: searchModsFunction,
                                label:
                                    Text(AppLocalizations.of(context)!.search),
                                icon: const Icon(Icons.search),
                              ),
                            ],
                            onSubmitted: (String val) => searchModsFunction(),
                            hintText:
                                AppLocalizations.of(context)!.searchForMods,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(left: 10, right: 4),
                          child: !widget.filterOn
                              ? ActionChip(
                                  onPressed: () async {
                                    File currentModpackFile = File(
                                        "${getMinecraftFolder().path}/mods/modConfig.json");
                                    if (!await currentModpackFile.exists()) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(context)!
                                                .chooseModpack,
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    Map modpackConfig = json.decode(
                                      await currentModpackFile.readAsString(),
                                    );
                                    String name = modpackConfig["name"];
                                    String version = modpackConfig["version"];
                                    String api = modpackConfig["modLoader"];

                                    GetStorage().writeInMemory(
                                        "lastUsedVersion", version);
                                    GetStorage()
                                        .writeInMemory("lastUsedAPI", api);
                                    GetStorage()
                                        .writeInMemory("lastUsedModpack", name);
                                    Get.to(
                                      () => const WebSourcesPage(
                                        filterOn: true,
                                      ),
                                      transition: Transition.topLevel,
                                    );
                                  },
                                  avatar: const Icon(Icons.filter_alt),
                                  label: Text(AppLocalizations.of(context)!
                                      .filterBySelectedModpack),
                                )
                              : Container(),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          child: !widget.filterOn
                              ? ActionChip(
                                  onPressed: () async {
                                    Get.to(
                                      () => const FilterMods(),
                                      transition: Transition.topLevel,
                                    );
                                  },
                                  avatar: const Icon(Icons.filter_alt_outlined),
                                  label: Text(
                                    AppLocalizations.of(context)!.filter,
                                  ),
                                )
                              : Container(),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          child: !widget.filterOn
                              ? ActionChip(
                                  onPressed: () async {
                                    Get.to(
                                      () => UpdateModpack(),
                                      transition: Transition.topLevel,
                                    );
                                  },
                                  avatar: const Icon(Icons.update),
                                  label: Text(
                                      AppLocalizations.of(context)!.update),
                                )
                              : Container(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 15),
            ),
            isLoading
                ? Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 28),
                      child: const LinearProgressIndicator(),
                    ),
                  )
                : Expanded(
                    child: GridView.extent(
                      maxCrossAxisExtent: 565,
                      mainAxisSpacing: 15,
                      crossAxisSpacing: 0,
                      childAspectRatio: 1.35,
                      padding: const EdgeInsets.only(bottom: 15),
                      children: searchResults,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
