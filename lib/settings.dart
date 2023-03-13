import 'dart:convert';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  Widget build(BuildContext context) {
    const githubApiToken = String.fromEnvironment("GITHUB_RELEASE_KEY");
    Uri githubGet = Uri.parse(
        "https://api.github.com/repos/mrquantumoff/mcmodpackmanager_reborn/releases");

    Map<String, String> headers = {"Authentication": githubApiToken};

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
          DropdownMenu(
            width: 275,
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
          Container(
            margin: const EdgeInsets.only(top: 12),
            child: FutureBuilder(
              future: getReleaseInfo(),
              builder: (ctx, snapshot) {
                // Checking if future is resolved
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData) {
                  return Column(
                    children: [
                      Text(
                        "${AppLocalizations.of(context)!.currentVersion}v${snapshot.data!["currentRelease"].toString()}",
                        style: const TextStyle(fontSize: 16),
                      ),
                      Text(
                        "${AppLocalizations.of(context)!.latestVersion}${snapshot.data!["latestRelease"].toString()}",
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
        ],
      ),
    );
  }
}
