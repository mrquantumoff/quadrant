import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';
import 'package:get/get.dart';

import 'package:http/http.dart' as http;
import 'package:mcmodpackmanager_reborn/modpack_installer/web/filter_mods.dart';
import 'package:mcmodpackmanager_reborn/modpack_installer/web/generate_user_agent.dart';
import 'package:mcmodpackmanager_reborn/modpack_installer/web_sources.dart';

class ModpackInstaller extends StatelessWidget {
  const ModpackInstaller({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          margin: const EdgeInsets.all(12),
          child: ElevatedButton(
            onPressed: (const String.fromEnvironment("ETERNAL_API_KEY") == "")
                ? () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text(AppLocalizations.of(context)!.noEternalKey),
                      ),
                    );
                  }
                : () async {
                    final String apiKey =
                        const String.fromEnvironment("ETERNAL_API_KEY")
                            .replaceAll("\"", "");
                    http.Response res = await http.get(
                      Uri.parse("https://api.curseforge.com/v1/games"),
                      headers: {
                        "User-Agent": await generateUserAgent(),
                        "X-API-Key": apiKey
                      },
                    );

                    if (res.statusCode == 200) {
                      var data = json.decode(res.body);
                      bool isValid = false;
                      for (var game in data["data"]) {
                        if (game["id"] == 432) {
                          final clickedButton =
                              await FlutterPlatformAlert.showAlert(
                            windowTitle:
                                AppLocalizations.of(context)!.productName,
                            text: AppLocalizations.of(context)!.filterModpacksQ,
                            alertStyle: AlertButtonStyle.yesNo,
                            iconStyle: IconStyle.question,
                          );
                          if (clickedButton == AlertButton.yesButton) {
                            Get.to(
                              () => const FilterMods(),
                              transition: Transition.rightToLeft,
                            );
                          } else {
                            Get.to(
                              () => const WebSourcesPage(),
                              transition: Transition.rightToLeft,
                            );
                          }
                          isValid = true;
                        }
                      }
                      if (!isValid) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                AppLocalizations.of(context)!.noEternalKey),
                          ),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text(AppLocalizations.of(context)!.noEternalKey),
                        ),
                      );
                    }
                  },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.download_sharp),
                  Text("  ${AppLocalizations.of(context)!.web}"),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
