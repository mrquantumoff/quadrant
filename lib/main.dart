import 'dart:io';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mcmodpackmanager_reborn/backend.dart';
import 'package:mcmodpackmanager_reborn/modpack_installer/install_modpack_button.dart';
import 'package:mcmodpackmanager_reborn/modpack_installer/web/generate_user_agent.dart';
import 'package:mcmodpackmanager_reborn/selector.dart';
import 'package:mcmodpackmanager_reborn/open_modpacks_folder.dart';
import 'package:mcmodpackmanager_reborn/settings.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';

String isOfficial() {
  final String apiKey = const String.fromEnvironment("ETERNAL_API_KEY")
      .replaceAll("\"", "")
      .trim();
  if (apiKey == "") {
    return "CurseForge/Modrinth disabled";
  }
  return "CurseForge/Modrinth enabled";
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await GetStorage.init();
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  WindowOptions windowOptions = WindowOptions(
      size: const Size(1280, 720),
      center: false,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      minimumSize: const Size(1024, 576),
      fullScreen: false,
      title:
          "Minecraft Modpack Manager Reborn v${packageInfo.version} (${isOfficial()})");
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

  runApp(const MyApp());
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

  late String locale;

  @override
  void initState() {
    super.initState();
    setLocale(GetStorage().read("locale") ?? "native");
    debugPrint("Initiated $locale");
  }

  void setLocale(String value) {
    for (var loc in AppLocalizations.supportedLocales) {
      if (loc.languageCode == value) {
        GetStorage().write("locale", value);
        setState(() {
          locale = value;
          debugPrint("Locale set");
        });
        return;
      }
      if (value == "native") {
        final String defaultLocale = Platform.localeName
            .split("_")
            .first; // Returns locale string in the form 'en_US'
        debugPrint("System locale is \"$defaultLocale\"");
        setLocale(defaultLocale);
      }
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

class _MinecraftModpackManagerState extends State<MinecraftModpackManager> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          // title: Text(AppLocalizations.of(context)!.productName),
          ),
      endDrawer: Drawer(
        width: 350,
        child: Settings(
          setLocale: widget.setLocale,
        ),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 15),
                child: SvgPicture.asset(
                  "assets/icons/logo.svg",
                  height: 128,
                ),
              ),
              // Container(
              //   margin: const EdgeInsets.only(bottom: 15),
              //   child: Text(
              //     AppLocalizations.of(context)!.productName,
              //     style: const TextStyle(fontSize: 24),
              //   ),
              // ),
              const Selector(),
              const OpenModpacksFolder(),
              const ModpackInstaller()
            ],
          )
        ],
      ),
    );
  }
}
