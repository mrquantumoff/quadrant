import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class OpenModpacksFolder extends StatefulWidget {
  const OpenModpacksFolder({super.key});

  @override
  State<OpenModpacksFolder> createState() => _OpenModpacksFolderState();
}

class _OpenModpacksFolderState extends State<OpenModpacksFolder> {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ElevatedButton(
        onPressed: () {
          debugPrint("Open Modpacks Folder pressed.");
        },
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [Text(AppLocalizations.of(context)!.openModpacksFolder)],
          ),
        ),
      ),
    );
  }
}
