import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/material.dart';

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
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
      child: ListView(
        children: [
          DrawerHeader(child: Text(AppLocalizations.of(context)!.settings)),
          DropdownMenu(
            width: 275,
            controller: _controller,
            label: Text(AppLocalizations.of(context)!.language),
            dropdownMenuEntries: const [
              DropdownMenuEntry(value: "en", label: "English"),
              DropdownMenuEntry(value: "uk", label: "Українська")
            ],
            onSelected: (value) async {
              debugPrint("Selected value: ${value ?? "en"}");
              widget.setLocale(value ?? "en");
            },
          ),
        ],
      ),
    );
  }
}
