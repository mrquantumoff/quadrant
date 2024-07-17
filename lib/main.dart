import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get_storage_qnt/get_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:quadrant/draggable_appbar.dart';
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
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:http/http.dart' as http;
import 'package:protocol_handler/protocol_handler.dart';
import 'package:dart_rss/dart_rss.dart';
// import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:quadrant/pages/modpack_importer/import_modpacks/import_modpacks_page.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await GetStorage.init();
  WidgetsFlutterBinding.ensureInitialized();
  dataCollectionInit();
  initConfig();
  await localNotifier.setup(
    appName: 'quadrant',
    // The parameter shortcutPolicy only works on Windows
    shortcutPolicy: ShortcutPolicy.requireCreate,
  );

  // Register a custom protocol
  // For macOS platform needs to declare the scheme in ios/Runner/Info.plist

  await trayManager.setIcon(
    Platform.isWindows ? 'assets/icons/tray.ico' : 'assets/icons/tray.png',
  );
  Menu menu = Menu(
    items: [
      MenuItem(
        key: 'show_window',
        label: 'Show Window',
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'exit_app',
        label: 'Exit App',
      ),
    ],
  );
  await trayManager.setContextMenu(menu);

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
  String? token = await storage.read(key: "quadrant_id_token");
  try {
    if (JwtDecoder.isExpired(token ?? "")) {
      await storage.delete(key: "quadrant_id_token");
    }
    if (token != null) {
      Map res = JwtDecoder.decode(token);
      if (!res["sub"].toString().contains("notifications") ||
          !res["sub"].toString().contains("quadrant_sync")) {
        await storage.delete(key: "quadrant_id_token");
      }
    }
  } catch (e) {
    // print(e);
  }
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1366, 768),
    center: false,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    minimumSize: Size(1280, 720),
    fullScreen: false,
  );

  var tempDir = await getTemporaryDirectory();

  for (var file in tempDir.listSync()) {
    if (file.path.split("/").last.split("\\").last.startsWith("modpack-") &&
        file.path.endsWith(".zip")) {
      file.delete();
    }
  }

  debugPrint(await generateUserAgent());

  debugPrint("$args");
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (args.contains("autostart")) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  });
  void accountUpdate(Timer t) async {
    checkAccountUpdates();
  }

  Timer.periodic(
    const Duration(seconds: 10),
    accountUpdate,
  );
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
  void initState() {
    super.initState();
  }

  Future<AppExitResponse> onExit() async {
    return AppExitResponse.cancel;
  }

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

class _QuadrantState extends State<Quadrant>
    with ProtocolListener, TrayListener {
  Timer? checkRSSTimer;
  Timer? clearBanners;
  Timer? checkAccountTimer;

  @override
  void dispose() {
    protocolHandler.removeListener(this);

    checkRSSTimer?.cancel();
    clearBanners?.cancel();
    pages = [];
    trayManager.removeListener(this);
    super.dispose();
  }

  int currentPage = (GetStorage().read("lastPage") ?? 0) <= 3
      ? GetStorage().read("lastPage")
      : 0;
  List<Widget> pages = [];

  int accountNotifications = 0;

  @override
  void initState() {
    trayManager.addListener(this);
    super.initState();

    checkAccountTimer = Timer.periodic(
      const Duration(seconds: 10),
      (Timer t) async {
        try {
          await checkAccountUpdates(context);
        } catch (e) {
          debugPrint("$e");
        }
      },
    );
    checkRSSTimer = Timer.periodic(
      const Duration(seconds: 180),
      (Timer t) async {
        if (GetStorage().read("devMode")) {
          debugPrint("checkingRSSUpdates!");
        }
        await checkRSS(context);
      },
    );
    clearBanners = Timer.periodic(const Duration(seconds: 15), (Timer t) async {
      await clearUselessBanners();
    });

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
  void onTrayIconRightMouseDown() async {
    // do something, for example pop up the menu
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconMouseDown() async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.center();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show_window') {
      windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      exit(0);
    }
    switch (menuItem.key) {
      case "show_window":
        windowManager.show();
        windowManager.focus();
        break;
      case "exit_app":
        windowManager.close();
        break;
    }
  }

  Future<void> clearUselessBanners() async {
    if (!areAnyUpdates && !areAnyNews) {
      ScaffoldMessenger.of(context).clearMaterialBanners();
    }
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
          exit(1);
        }

        http.Response res = await http.post(
          Uri.parse(
              "https://api.mrquantumoff.dev/api/v3/account/oauth2/token/access"),
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
          exit(2);
        }
        String token = jsonDecode(res.body)["access_token"];
        String scope = jsonDecode(res.body)["scope"];

        if (!scope.contains("user_data") ||
            !scope.contains("quadrant_sync") ||
            !scope.contains("notifications")) {
          debugPrint("Scope mismatch");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.invalidData),
            ),
          );
          exit(3);
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
  bool areAnyUpdates = false;
  bool areAnyNews = false;

  Future<void> checkAccountUpdates(BuildContext context) async {
    const storage = FlutterSecureStorage();
    String? token = await storage.read(key: "quadrant_id_token");
    if (token == null) {
      return;
    }
    http.Response res = await http.get(
        Uri.parse("https://api.mrquantumoff.dev/api/v3/quadrant/sync/get"),
        headers: {
          "User-Agent": await generateUserAgent(),
          "Authorization": "Bearer $token"
        });
    http.Response userInfoRes = await http.get(
      Uri.parse("https://api.mrquantumoff.dev/api/v3/account/info/get"),
      headers: {
        "User-Agent": await generateUserAgent(),
        "Authorization": "Bearer $token"
      },
    );
    if (userInfoRes.statusCode != 200) {
      return;
    }
    Map userInfo = json.decode(userInfoRes.body);

    if (userInfoRes.statusCode != 200) {
      debugPrint(
          "ACCOUNT UPDATE ERROR: ${userInfoRes.body} (${userInfoRes.statusCode})");
      return;
    }
    if (res.statusCode != 200) {
      debugPrint("ACCOUNT UPDATE ERROR: ${res.body} (${res.statusCode})");
      return;
    }
    List<dynamic> notifications = userInfo["notifications"];
    accountNotifications = 0;
    for (dynamic notification in notifications) {
      if (notification["read"] == false) {
        setState(() {
          accountNotifications = accountNotifications + 1;
        });
      }
    }

    List<SyncedModpack> syncedModpacks = [];
    List<dynamic> data = json.decode(res.body);
    for (var modpack in data) {
      syncedModpacks.add(
        SyncedModpack(
          modpackId: modpack["modpack_id"],
          name: modpack["name"],
          mods: modpack["mods"],
          mcVersion: modpack["minecraft_version"],
          modLoader: modpack["mod_loader"],
          lastSynced: modpack["last_synced"],
          reload: (value) {},
          token: token,
          username: userInfo["login"],
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

        bool notification = !areAnyUpdates;

        areAnyUpdates = false;
        if (lastRemoteSync > lastLocalSync) {
          areAnyUpdates = true;

          if (notification != areAnyUpdates) {}

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
          break;
        }
      } catch (e) {
        debugPrint("$e");
      }
    }
  }

  Future<void> checkRSS(BuildContext context) async {
    try {
      http.Response res =
          await http.get(Uri.parse("https://blog.mrquantumoff.dev/rss/"));
      if (res.statusCode != 200) return;
      String rawFeed = res.body;

      var feed = RssFeed.parse(rawFeed);
      List<RssItem> items = feed.items;
      // items = items.reversed.toList();
      for (var item in items) {
        // debugPrint(item.title);
        List<String> categories = [];
        for (var category in item.categories) {
          categories.add(category.value!);
        }
        bool cond1 = !(GetStorage().read<List<dynamic>>("seenItems") ?? [])
            .contains(item.guid!);
        areAnyNews = false;
        String itemTimestamp = item.pubDate!;
        var format = DateFormat("E, dd MMM y H:m:s");
        DateTime itemDate = format.parse(itemTimestamp);
        bool cond2 =
            itemDate.add(const Duration(days: 14)).isAfter(DateTime.now());
        bool cond3 = GetStorage().read("rssFeeds") == true;
        bool cond4 = GetStorage().read("devMode") == true;
        if (GetStorage().read("devMode")) {
          debugPrint(
              "\n\nName: ${item.title}\n\nDate: $itemTimestamp\n\nSeen: $cond1\nIs within last 2 weeks: $cond2\nAre RSS feeds enabled: $cond3\nIs DevMode Enabled:  $cond4\n\n");
        }
        if (((cond1 && cond2) || cond4) &&
            cond3 &&
            categories.contains("Minecraft Modpack Manager")) {
          var newSeenItems =
              (GetStorage().read<List<dynamic>>("seenItems") ?? []);
          newSeenItems.add(item.guid!);
          GetStorage().write("seenItems", newSeenItems);
          if (GetStorage().read("silentNews") == true) {
            areAnyNews = true;
            ScaffoldMessenger.of(context).showMaterialBanner(
              MaterialBanner(
                content: Text(item.title!),
                actions: [
                  FilledButton.icon(
                    onPressed: () async {
                      await launchUrl(
                        Uri.parse(
                          item.link!.toString(),
                        ),
                      );
                      ScaffoldMessenger.of(context).clearMaterialBanners();
                      try {
                        checkAccountUpdates(context);
                      } catch (e) {
                        debugPrint("$e");
                      }
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: Text(AppLocalizations.of(context)!.read),
                  )
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
                          await launchUrl(Uri.parse(item.link!.toString()));
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        checkDataCollection(context);
        checkRSS(context);
        try {
          checkAccountUpdates(context);
        } catch (e) {
          debugPrint("$e");
        }
      } catch (e) {
        debugPrint("Failed to check for something: $e");
      }
    });

    if (GetStorage().read("protocolArgument") != null && Platform.isLinux) {
      debugPrint("Protocol received");
      onProtocolUrlReceived(
        GetStorage().read("protocolArgument"),
      );
      debugPrint("Protocol protocol removed");
      GetStorage().remove("protocolArgument");
    }

    return Scaffold(
      appBar: DraggableAppBar(
        appBar: AppBar(
          toolbarHeight: 56,
          primary: true,
          title: Text(AppLocalizations.of(context)!.productName),
        ),
      ),
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
                icon: Badge(
                  label: Text(accountNotifications.toString()),
                  isLabelVisible: accountNotifications > 0,
                  child: const Icon(Icons.account_circle_outlined),
                ),
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
