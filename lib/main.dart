import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:mcmodpackmanager_reborn/install_modpack.dart';
import 'package:mcmodpackmanager_reborn/selector.dart';
import 'package:mcmodpackmanager_reborn/open_modpacks_folder.dart';
import 'package:window_manager/window_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  WindowOptions windowOptions = WindowOptions(
      size: const Size(1024, 576),
      center: false,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      minimumSize: const Size(1024, 576),
      fullScreen: false,
      title: "Minecraft Modpack Manager Reborn v${packageInfo.version}");
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

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
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const MinecraftModpackManager(),
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
  const MinecraftModpackManager({super.key});

  @override
  State<MinecraftModpackManager> createState() =>
      _MinecraftModpackManagerState();
}

class _MinecraftModpackManagerState extends State<MinecraftModpackManager> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                child: Text(
                  AppLocalizations.of(context)!.productName,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
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
