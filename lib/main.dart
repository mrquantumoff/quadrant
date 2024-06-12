import 'dart:convert';
import 'dart:io';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get_storage_qnt/get_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/other/restart_app.dart';
import 'package:quadrant/pages/account/account.dart';
import 'package:quadrant/pages/current_modpack/current_modpack_page.dart';
import 'package:quadrant/pages/main_page.dart';
import 'package:quadrant/pages/modpack_importer/import_modpacks/synced_modpack.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';
import 'package:quadrant/pages/web/mod/install_mod_page.dart';
import 'package:quadrant/pages/web/mod/mod.dart';
import 'package:quadrant/pages/web/web_sources.dart';
import 'package:quadrant/pages/settings/settings.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_feed/universal_feed.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:http/http.dart' as http;
import 'package:protocol_handler/protocol_handler.dart';
// import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:quadrant/pages/modpack_importer/import_modpacks/import_modpacks_page.dart';
import 'package:intl/date_symbol_data_local.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await GetStorage.init();
  WidgetsFlutterBinding.ensureInitialized();
  dataCollectionInit();
  // Register a custom protocol
  // For macOS platform needs to declare the scheme in ios/Runner/Info.plist
  if (Platform.isWindows || Platform.isMacOS) {
    await protocolHandler.register('curseforge');
    await protocolHandler.register('quadrant');
  } else {
    // Linux can use arguments from the cli
    for (String arg in args) {
      if (arg.startsWith("curseforge://install") ||
          arg.startsWith("quadrant://")) {
        GetStorage().writeInMemory("protocolArgument", arg);
      }
    }
  }
  const storage = FlutterSecureStorage();
  try {
    if (JwtDecoder.isExpired(
        await storage.read(key: "quadrant_id_token") ?? "")) {
      await storage.delete(key: "quadrant_id_token");
    }
  } catch (e) {
    // print(e);
  }
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1366, 768),
    center: false,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    minimumSize: Size(1280, 720),
    fullScreen: false,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  var tempDir = await getTemporaryDirectory();

  for (var file in tempDir.listSync()) {
    if (file.path.split("/").last.split("\\").last.startsWith("modpack-") &&
        file.path.endsWith(".zip")) {
      file.delete();
    }
  }

  debugPrint(await generateUserAgent());

  if (GetStorage().read("clipIcons") == null) {
    GetStorage().writeInMemory("clipIcons", true);
  }
  if (GetStorage().read("lastRSSfetched") == null) {
    GetStorage().writeInMemory("lastRSSfetched",
        DateTime.now().subtract(const Duration(days: 14)).toIso8601String());
  }
  if (GetStorage().read("curseforge") == null) {
    GetStorage().writeInMemory("curseForge", true);
  }
  if (GetStorage().read("modrinth") == null) {
    GetStorage().writeInMemory("modrinth", true);
  }
  if (GetStorage().read("devMode") == null) {
    GetStorage().writeInMemory("devMode", false);
  }
  if (GetStorage().read("rssFeeds") == null) {
    GetStorage().writeInMemory("rssFeeds", true);
  }
  if (GetStorage().read("silentNews") == null) {
    GetStorage().writeInMemory("silentNews", false);
  }
  if (GetStorage().read("autoQuadrantSync") == null) {
    GetStorage().writeInMemory("autoQuadrantSync", true);
  }
  if (GetStorage().read("showUnupgradeableMods") == null) {
    GetStorage().writeInMemory("showUnupgradeableMods", false);
  }
  if (GetStorage().read("lastPage") == null) {
    GetStorage().writeInMemory("lastPage", 0);
  }
  if (GetStorage().read("extendedNavigation") == null) {
    GetStorage().writeInMemory("extendedNavigation", false);
  }
  if (GetStorage().read("experimentalFeatures") == null) {
    GetStorage().writeInMemory("experimentalFeatures", false);
  }
  if (GetStorage().read("dontShowUserDataRecommendation") == null) {
    GetStorage().writeInMemory("dontShowUserDataRecommendation", false);
  }
  runApp(
    const RestartWidget(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
      return ThemeProvider(darkTheme: darkDynamic, lightTheme: lightDynamic);
    });
  }
}

class ThemeProvider extends StatefulWidget {
  const ThemeProvider(
      {super.key, required this.darkTheme, required this.lightTheme});

  final ColorScheme? darkTheme;
  final ColorScheme? lightTheme;

  @override
  State<ThemeProvider> createState() => _ThemeProviderState();
}

class _ThemeProviderState extends State<ThemeProvider> {
  bool shouldUseMaterial3 = true;

  String locale = GetStorage().read("locale") ?? "native";

  @override
  void initState() {
    super.initState();

    setLocale(GetStorage().read("locale") ?? "native");
    debugPrint("Initiated $locale");
  }

  void setLocale(String value) async {
    debugPrint((await getApplicationSupportDirectory()).path);
    bool hasBeenSet = false;
    for (var loc in AppLocalizations.supportedLocales) {
      if (loc.languageCode == value && value != "native") {
        GetStorage().write("locale", value);
        setState(() {
          locale = value;
          debugPrint("Locale set");
          hasBeenSet = true;
        });
      }
    }
    if (!hasBeenSet && value != "native") {
      GetStorage().write("locale", "en");
      setState(() {
        locale = "en";
        debugPrint("Locale set");
        hasBeenSet = true;
      });
    } else if (value == "native") {
      final String defaultLocale = Platform.localeName
          .split("_")
          .first; // Returns locale string in the form 'en_US'
      debugPrint("System locale is \"$defaultLocale\"");
      setLocale(defaultLocale);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (GetStorage().read("minecraftFolder") == null) {
      debugPrint("Mc folder is null");
      GetStorage()
          .write("minecraftFolder", getMinecraftFolder(onInit: true).path);
    }

    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale.fromSubtags(languageCode: locale),
      defaultTransition: Transition.rightToLeft,
      home: Quadrant(
        setLocale: setLocale,
      ),
      darkTheme: ThemeData.from(
        useMaterial3: shouldUseMaterial3,
        colorScheme: (widget.darkTheme ?? const ColorScheme.dark()),
      ),
      theme: ThemeData.from(
        useMaterial3: shouldUseMaterial3,
        colorScheme: (widget.lightTheme ?? const ColorScheme.light()),
      ),
    );
  }
}

class Quadrant extends StatefulWidget {
  const Quadrant({super.key, required this.setLocale});

  final Function(String locale) setLocale;

  @override
  State<Quadrant> createState() => _QuadrantState();
}

class _QuadrantState extends State<Quadrant> with ProtocolListener {
  @override
  void dispose() {
    protocolHandler.removeListener(this);

    pages = [];
    super.dispose();
  }

  int currentPage = (GetStorage().read("lastPage") ?? 0) <= 3
      ? GetStorage().read("lastPage")
      : 0;
  List<Widget> pages = [];
  @override
  void initState() {
    super.initState();

    pages = [
      const MainPage(),
      const CurrentModpackPage(),
      const WebSourcesPage(),
      ImportModpacksPage(),
      const AccountPage(),
      Settings(setLocale: widget.setLocale)
    ];

    protocolHandler.addListener(this);

    initializeDateFormatting();
  }

  @override
  void onProtocolUrlReceived(String url) async {
    String log = 'Url received: $url)';
    debugPrint(log);

    Uri uri = Uri.parse(url);
    try {
      if (url.startsWith("curseforge://")) {
        // Example: curseforge://install?addonId=238222&fileId=4473386
        int modId = int.parse(uri.queryParameters["addonId"]!);
        int fileId = int.parse(uri.queryParameters["fileId"]!);
        installModByProtocol(modId, fileId, protocolFail);
      } else if (url.startsWith("quadrant://modrinthopen")) {
        // Example: quadrant://modrinthopen?id=AANobbMI
        String id = uri.queryParameters["id"]!;
        Mod mod = await getMod(id, ModSource.modRinth, (val) => null);
        Uri vrsuri = Uri.parse(
          'https://api.modrinth.com/v2/tag/game_version',
        );
        List<dynamic> vrs = json.decode((await http.get(
          vrsuri,
          headers: {
            "User-Agent": await generateUserAgent(),
          },
        ))
            .body);
        List<String> versions = [];
        for (var v in vrs) {
          if (v["version_type"] == "release") {
            versions.add(v["version"].toString());
          }
        }
        List<DropdownMenuEntry> versionItems = [];
        List<DropdownMenuEntry> modpackItems = [];

        for (var version in versions) {
          versionItems.add(
            DropdownMenuEntry(label: version.toString(), value: version),
          );
        }

        List<String> modpacks = getModpacks(hideFree: false);

        for (var modpack in modpacks) {
          modpackItems.add(
            DropdownMenuEntry(label: modpack, value: modpack),
          );
        }
        Get.to(
          () => InstallModPage(
            versions: versionItems,
            mod: mod,
            modpacks: modpackItems,
            source: ModSource.modRinth,
            modClass: mod.modClass,
          ),
          preventDuplicates: false,
          transition: Transition.upToDown,
        );
      } else if (url.startsWith("quadrant://login")) {
        // Example: quadrant://login?code=AANobbMI
        String code = uri.queryParameters["code"]!;
        String state = uri.queryParameters["state"]!;

        if (state != GetStorage().read("oauth2_state")) {
          debugPrint("State mismatch");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.invalidData),
            ),
          );
          return;
        }

        http.Response res = await http.post(
          Uri.parse(
              "https://api.mrquantumoff.dev/api/v2/get/account/oauth2/token/compliant"),
          body: {
            "client_id":
                const String.fromEnvironment("QUADRANT_OAUTH2_CLIENT_ID"),
            "client_secret":
                const String.fromEnvironment("QUADRANT_OAUTH2_CLIENT_SECRET"),
            "code": code,
            "grant_type": "authorization_code"
          },
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
        );

        if (res.statusCode != 200) {
          debugPrint("${res.statusCode} ${res.body}");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.invalidData),
            ),
          );
          return;
        }
        String token = jsonDecode(res.body)["access_token"];
        String scope = jsonDecode(res.body)["scope"];

        if (!scope.contains("user_data") || !scope.contains("quadrant_sync")) {
          debugPrint("Scope mismatch");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.invalidData),
            ),
          );
          return;
        }

        const storage = FlutterSecureStorage();
        if (JwtDecoder.isExpired(token)) {
          return;
        }
        await storage.write(key: "quadrant_id_token", value: token);
        setState(() {
          currentPage = 4;
          GetStorage().write("lastPage", 4);
        });
        RestartWidget.restartApp(context);
      }
    } catch (e) {
      protocolFail();
    }
  }

  void protocolFail() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Text(AppLocalizations.of(context)!.unsupportedDownload),
      ),
    );
  }

  // void checkConnectivity(
  //     ConnectivityResult connectivityResult, BuildContext context) async {
  //   if (connectivityResult == ConnectivityResult.wifi ||
  //       connectivityResult == ConnectivityResult.ethernet) {
  //     return;
  //   }
  //   showDialog(
  //     context: context,
  //     builder: (BuildContext context) {
  //       return AlertDialog(
  //         title: Text(
  //           AppLocalizations.of(context)!.noConnectivity,
  //         ),
  //         content: Text(
  //           AppLocalizations.of(context)!.noConnectivityDetailed,
  //         ),
  //       );
  //     },
  //   );
  // }

  void checkModpackUpdates(context) async {
    const storage = FlutterSecureStorage();
    String? token = await storage.read(key: "quadrant_id_token");
    if (token == null) {
      throw Exception(AppLocalizations.of(context)!.noQuadrantID);
    }
    http.Response res = await http.get(
        Uri.parse("https://api.mrquantumoff.dev/api/v2/get/quadrant_sync"),
        headers: {
          "User-Agent": await generateUserAgent(),
          "Authorization": "Bearer $token"
        });

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
    List<SyncedModpack> syncedModpacks = [];
    List<dynamic> data = json.decode(res.body);
    for (var modpack in data) {
      syncedModpacks.add(
        SyncedModpack(
          modpackId: modpack["modpack_id"],
          name: modpack["name"],
          mods: modpack["mods"],
          mcVersion: modpack["mc_version"],
          modLoader: modpack["mod_loader"],
          lastSynced: modpack["last_synced"],
          reload: () {},
          token: token,
        ),
      );
    }

    syncedModpacks.sort(((a, b) {
      return b.lastSynced.compareTo(a.lastSynced);
    }));

    List<String> localModpacks = getModpacks();
    List<SyncedModpack> localSyncedModpacks = [];
    for (SyncedModpack modpack in syncedModpacks) {
      if (localModpacks.contains(modpack.name)) {
        localSyncedModpacks.add(modpack);
      }
    }
    for (SyncedModpack modpack in localSyncedModpacks) {
      File localSyncedModpackFile = File(
          "${getMinecraftFolder().path}/modpacks/${modpack.name}/quadrantSync.json");

      if (!localSyncedModpackFile.existsSync()) {
        continue;
      }
      try {
        int lastLocalSync = json
            .decode(localSyncedModpackFile.readAsStringSync())["last_synced"];
        int lastRemoteSync = modpack.lastSynced;

        if (lastRemoteSync > lastLocalSync) {
          ScaffoldMessenger.of(context).showMaterialBanner(
            MaterialBanner(
              content: Text(
                AppLocalizations.of(context)!
                    .newerVersionOfModpackUpdateAvailable,
              ),
              actions: [
                FilledButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).clearMaterialBanners();

                    Get.to(() => ImportModpacksPage(page: 1));
                    checkRSS(context);
                  },
                  icon: const Icon(Icons.update),
                  label: Text(AppLocalizations.of(context)!.update),
                )
              ],
            ),
          );
          return;
        }
      } catch (e) {
        debugPrint("$e");
      }
    }
  }

  void checkRSS(BuildContext context) async {
    try {
      http.Response res =
          await http.get(Uri.parse("https://api.mrquantumoff.dev/blog.rss"));
      if (res.statusCode != 200) return;
      String rawFeed = res.body;

      var feed = UniversalFeed.parseFromString(rawFeed);
      List<Item> items = feed.items;
      items = items.reversed.toList();
      for (var item in items) {
        debugPrint(item.title);
        List<String> categories = [];
        for (var category in item.categories) {
          categories.add(category.value!);
        }
        bool cond1 = !(GetStorage().read<List<dynamic>>("seenItems") ?? [])
            .contains(item.guid!);

        DateTime itemDate = item.published!.parseValue() ??
            DateTime.now().subtract(const Duration(days: 28));
        bool cond2 =
            itemDate.add(const Duration(days: 14)).isAfter(DateTime.now());
        bool cond3 = GetStorage().read("rssFeeds") == true;
        bool cond4 = GetStorage().read("devMode") == true;
        debugPrint(
            "\n\nSeen: $cond1\nIs within last 2 weeks: $cond2\nAre RSS feeds enabled: $cond3\nIs DevMode Enabled:  $cond4\n\n");

        if (((cond1 && cond2) || cond4) &&
            cond3 &&
            categories.contains("Minecraft Modpack Manager")) {
          var newSeenItems =
              (GetStorage().read<List<dynamic>>("seenItems") ?? []);
          newSeenItems.add(item.guid!);
          GetStorage().write("seenItems", newSeenItems);
          if (GetStorage().read("silentNews") == true) {
            ScaffoldMessenger.of(context).showMaterialBanner(
              MaterialBanner(
                content: Text(item.title!),
                actions: [
                  FilledButton.icon(
                      onPressed: () async {
                        await launchUrl(Uri.parse(item.link!.href.toString()));
                        ScaffoldMessenger.of(context).clearMaterialBanners();
                        checkModpackUpdates(context);
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: Text(AppLocalizations.of(context)!.read))
                ],
              ),
            );
          } else {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(item.title!),
                  content: Text(item.description!),
                  actions: [
                    TextButton(
                        onPressed: () async {
                          await launchUrl(
                              Uri.parse(item.link!.href.toString()));
                        },
                        child: Text(AppLocalizations.of(context)!.read))
                  ],
                );
              },
            );
          }
          GetStorage()
              .write("lastRSSfetched", DateTime.now().toIso8601String());

          return;
        }
      }
    } catch (e) {
      debugPrint("$e");
    }
  }

  void checkDataCollection(BuildContext context) async {
    if (GetStorage().read("collectUserData") == true ||
        GetStorage().read("dontShowTelemetryRecommendation") == true) {
      return;
    }
    // try {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: Container(
          alignment: Alignment.bottomLeft,
          child: Text(
            AppLocalizations.of(context)!
                .enableDataCollectionForAdvancedFeatures,
            style: const TextStyle(
              fontSize: 18,
            ),
          ),
        ),
        actions: [
          FilledButton.icon(
            onPressed: () {
              GetStorage().write("collectUserData", true);
              collectUserInfo();
              ScaffoldMessenger.of(context).clearMaterialBanners();
            },
            label: const Text("OK"),
            icon: const Icon(Icons.check),
          ),
          FilledButton.tonalIcon(
            onPressed: () {
              GetStorage().write("dontShowTelemetryRecommendation", true);
              ScaffoldMessenger.of(context).clearMaterialBanners();
            },
            label: Text(AppLocalizations.of(context)!.dontBotherMeAgain),
            icon: const Icon(Icons.close),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (GetStorage().read("protocolArgument") != null && Platform.isLinux) {
      debugPrint("curseforge protocol received");
      onProtocolUrlReceived(GetStorage().read("protocolArgument"));
      debugPrint("curseforge protocol removed");
      GetStorage().remove("protocolArgument");
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        checkRSS(context);
        checkModpackUpdates(context);
        checkDataCollection(context);
      } catch (e) {
        debugPrint("Failed to check for something: $e");
      }
    });
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: currentPage,
            extended: GetStorage().read("extendedNavigation"),
            labelType: GetStorage().read("extendedNavigation")
                ? null
                : NavigationRailLabelType.none,
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.check_outlined),
                label: Text(AppLocalizations.of(context)!.apply),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.file_open_outlined),
                label: Text(AppLocalizations.of(context)!.currentModpack),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.download_rounded),
                label: Text(AppLocalizations.of(context)!.web),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.import_export_rounded),
                label: Text(AppLocalizations.of(context)!.importMods),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.account_circle_outlined),
                label: Text(AppLocalizations.of(context)!.account),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.settings_rounded),
                label: Text(AppLocalizations.of(context)!.settings),
              ),
            ],
            onDestinationSelected: (int value) {
              setState(() {
                currentPage = value;
              });

              GetStorage().write("lastPage", value);
            },
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: pages[currentPage])
        ],
      ),
    );
  }
}
