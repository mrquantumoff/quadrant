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
import 'package:quadrant/pages/web/generate_user_agent.dart';
import 'package:quadrant/pages/web/mod/install_mod_page.dart';
import 'package:quadrant/pages/web/mod/mod.dart';
import 'package:quadrant/pages/web/web_sources.dart';
import 'package:quadrant/pages/settings/settings.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:http/http.dart' as http;
import 'package:protocol_handler/protocol_handler.dart';
// import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:quadrant/pages/modpack_importer/import_modpacks/import_modpacks_page.dart';

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
    await protocolHandler.register('mcmodpackmanager');
  } else {
    // Linux can use arguments from the cli
    for (String arg in args) {
      if (arg.startsWith("curseforge://install") ||
          arg.startsWith("mcmodpackmanager://")) {
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
      home: MinecraftModpackManager(
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

class MinecraftModpackManager extends StatefulWidget {
  const MinecraftModpackManager({super.key, required this.setLocale});

  final Function(String locale) setLocale;

  @override
  State<MinecraftModpackManager> createState() =>
      _MinecraftModpackManagerState();
}

class _MinecraftModpackManagerState extends State<MinecraftModpackManager>
    with ProtocolListener {
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
      const ShareModpacksPage(),
      const AccountPage(),
      Settings(setLocale: widget.setLocale)
    ];

    protocolHandler.addListener(this);
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
      } else if (url.startsWith("mcmodpackmanager://modrinthopen")) {
        // Example: mcmodpackmanager://modrinthopen?id=AANobbMI
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

  @override
  Widget build(BuildContext context) {
    if (GetStorage().read("protocolArgument") != null && Platform.isLinux) {
      debugPrint("curseforge protocol received");
      onProtocolUrlReceived(GetStorage().read("protocolArgument"));
      debugPrint("curseforge protocol removed");
      GetStorage().remove("protocolArgument");
    }

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
