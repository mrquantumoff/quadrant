import 'dart:convert';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mcmodpackmanager_reborn/backend.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class Settings extends StatefulWidget {
  const Settings({super.key, required this.setLocale});

  final Function(String locale) setLocale;

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  late TextEditingController _controller;
  late String mcFolder;
  late String latestVersion;

  @override
  void dispose() {
    super.dispose();
  }

  void updateMinecraftFolderText() {
    setState(() {
      mcFolder = getMinecraftFolder().path;
    });
  }

  @override
  void initState() {
    mcFolder = getMinecraftFolder().path;
    super.initState();
    _controller = TextEditingController();
  }

  Uri githubGet = Uri.parse(
      "https://api.github.com/repos/mrquantumoff/mcmodpackmanager_reborn/releases");

  Map<String, String> headers = {
    "Authentication":
        "Bearer ${const String.fromEnvironment("GITHUB_RELEASE_KEY")}"
  };

  Future<Map<String, String>> getReleaseInfo() async {
    http.Response latestReleaseResponse =
        await http.get(githubGet, headers: headers);
    List<dynamic> response = json.decode(latestReleaseResponse.body);
    Map latestRelease = response[0];
    PackageInfo packageInfo = await PackageInfo.fromPlatform();

    return {
      "latestRelease": latestRelease["tag_name"],
      "currentRelease": packageInfo.version,
      "url": latestRelease["html_url"]
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
      child: ListView(
        children: [
          DrawerHeader(
            child: Column(
              children: [
                Text(AppLocalizations.of(context)!.settings),
                Text(
                  AppLocalizations.of(context)!.someSettingsRequireReload,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
          Center(
            child: DropdownMenu(
              width: 300,
              controller: _controller,
              label: Text(AppLocalizations.of(context)!.language),
              dropdownMenuEntries: [
                const DropdownMenuEntry(value: "en", label: "English"),
                const DropdownMenuEntry(value: "uk", label: "Українська"),
                DropdownMenuEntry(
                    value: "native",
                    label: AppLocalizations.of(context)!.systemLocale),
              ],
              onSelected: (value) async {
                debugPrint("Selected value: ${value ?? "en"}");
                widget.setLocale(value ?? "en");
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            child: FutureBuilder(
              future: getReleaseInfo(),
              builder: (ctx, snapshot) {
                // Checking if future is resolved
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData) {
                  return Column(
                    children: [
                      Text(
                        AppLocalizations.of(context)!.currentVersion(
                            "v${snapshot.data!["currentRelease"].toString()}"),
                        style: const TextStyle(fontSize: 16),
                      ),
                      Text(
                        AppLocalizations.of(context)!.latestVersion(
                            snapshot.data!["latestRelease"].toString()),
                        style: const TextStyle(fontSize: 16),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        child: TextButton.icon(
                          onPressed: () {
                            Uri uri = Uri.parse(snapshot.data!["url"]!);
                            launchUrl(uri);
                          },
                          icon: const Icon(Icons.open_in_browser),
                          label: Text(
                            AppLocalizations.of(context)!.openLatestRelease,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  );
                } else if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasError) {
                  return Container();
                } else {
                  return const LinearProgressIndicator();
                }
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            child: Column(
              children: [
                Text(mcFolder),
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  child: TextButton(
                    onPressed: () =>
                        overwriteMinecraftFolder(updateMinecraftFolderText),
                    child: Text(
                        AppLocalizations.of(context)!.overwriteMinecraftFolder),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  child: TextButton(
                    onPressed: () => clearMinecraftFolderOverwrite(
                        updateMinecraftFolderText),
                    child: Text(
                        AppLocalizations.of(context)!.resetMinecraftFolder),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
