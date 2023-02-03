import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ModpackInstaller extends StatefulWidget {
  const ModpackInstaller({super.key});

  @override
  State<ModpackInstaller> createState() => _ModpackInstallerState();
}

class _ModpackInstallerState extends State<ModpackInstaller> {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      // width: 165,
      // height: 40,
      child: ElevatedButton(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(Icons.install_desktop_rounded),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(AppLocalizations.of(context)!.installModpacks),
              )
            ],
          ),
          onPressed: () {}),
    );
  }
}
