import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';

import 'package:mcmodpackmanager_reborn/modpack_installer/install_modpacks_page.dart';

class ModpackInstaller extends StatelessWidget {
  const ModpackInstaller({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          child: ElevatedButton(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.install_desktop_rounded),
                    Text("  ${AppLocalizations.of(context)!.installModpacks}"),
                  ],
                ),
              ),
              onPressed: () {
                Get.to(() => const ModpackInstallerPage(),
                    transition: Transition.rightToLeft);
              }),
        ),
      ],
    );
  }
}
