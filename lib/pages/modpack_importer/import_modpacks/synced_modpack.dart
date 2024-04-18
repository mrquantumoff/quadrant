import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SyncedModpack extends StatefulWidget {
  const SyncedModpack({
    super.key,
    required this.modpackId,
    required this.name,
    required this.mods,
    required this.mcVersion,
    required this.modLoader,
    required this.lastSynced,
  });

  final String modpackId;
  final String name;
  final String mods;
  final String mcVersion;
  final String modLoader;
  final int lastSynced;

  @override
  State<SyncedModpack> createState() => _SyncedModpackState();
}

class _SyncedModpackState extends State<SyncedModpack> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 640,
      height: 96,
      child: Card(
        child: Column(
          children: [
            Text("${widget.name} (${widget.modLoader}, ${widget.mcVersion})"),
          ],
        ),
      ),
    );
  }
}
