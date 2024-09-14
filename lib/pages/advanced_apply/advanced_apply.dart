import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/advanced_apply/modpack_preview.dart';

class AdvancedApplyPage extends StatefulWidget {
  const AdvancedApplyPage({super.key});

  @override
  State<AdvancedApplyPage> createState() => _AdvancedApplyPageState();
}

class _AdvancedApplyPageState extends State<AdvancedApplyPage> {
  int refreshDate = DateTime.now().millisecondsSinceEpoch;
  Timer? refreshTimer;
  List<ModpackPreview> currentPreviews = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      refreshTimer = Timer.periodic(
        const Duration(seconds: 5),
        (Timer t) async {
          List<ModpackPreview> previews = await getModpackPreviews(refreshDate);
          if (previews == currentPreviews) {
            return;
          }
          setState(
            () {
              refreshDate = DateTime.now().millisecondsSinceEpoch;
            },
          );
        },
      );
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.apply,
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: ActionChip(
              label: Text(
                AppLocalizations.of(context)!.openModpacksFolder,
              ),
              avatar: const Icon(Icons.folder),
              onPressed: openModpacksFolder,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: ActionChip(
              label: Text(
                AppLocalizations.of(context)!.clear,
              ),
              avatar: const Icon(Icons.clear),
              onPressed: () async {
                bool res = await clearModpack();
                switch (res) {
                  case true:
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            AppLocalizations.of(context)!.setModpackSuccess),
                      ),
                    );
                    break;
                  case false:
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            AppLocalizations.of(context)!.setModpackFailed),
                      ),
                    );
                    break;
                }
              },
            ),
          ),
        ],
      ),
      body: FutureBuilder(
        future: getModpackPreviews(refreshDate),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                children: [const Icon(Icons.error), Text("${snapshot.error}")],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          currentPreviews = snapshot.data!;
          return ListView(
            children: AnimateList(
              effects: [
                MoveEffect(
                    begin: const Offset(0, 850),
                    duration: 200.ms,
                    delay: 100.ms),
                BlurEffect(
                  end: const Offset(0, 0),
                  begin: const Offset(10, 10),
                  delay: 200.ms,
                ),
              ],
              children: snapshot.data!,
            ),
          );
        },
      ),
    );
  }
}
