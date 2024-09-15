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

  late TextEditingController queryController;

  @override
  void initState() {
    super.initState();
    queryController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      List<ModpackPreview> newPreviews = await getModpackPreviews();
      setState(() {
        currentPreviews = newPreviews;
      });
      refreshTimer =
          Timer.periodic(const Duration(milliseconds: 150), (_) async {
        List<ModpackPreview> newPreviews = await getModpackPreviews(
          searchQuery: queryController.text.trim().isNotEmpty
              ? queryController.text.trim()
              : null,
        );
        if (currentPreviews != newPreviews) {
          setState(() {
            currentPreviews = newPreviews;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    queryController.dispose();
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
      body: Column(
        children: [
          ConstrainedBox(
            constraints:
                const BoxConstraints(maxHeight: 64, minWidth: double.maxFinite),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: SearchBar(
                leading: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: const Icon(
                    Icons.search,
                    color: Colors.grey,
                    size: 24,
                  ),
                ),
                hintText: AppLocalizations.of(context)!.search,
                controller: queryController,
                onChanged: (value) async {
                  List<ModpackPreview> newPreviews = await getModpackPreviews(
                    searchQuery: queryController.text.trim().isNotEmpty
                        ? queryController.text.trim()
                        : null,
                  );
                  setState(() {
                    currentPreviews = newPreviews;
                  });
                },
                trailing: [
                  FilledButton.icon(
                    onPressed: () async {
                      List<ModpackPreview> newPreviews =
                          await getModpackPreviews(
                        searchQuery: queryController.text.trim().isNotEmpty
                            ? queryController.text.trim()
                            : null,
                      );
                      setState(() {
                        currentPreviews = newPreviews;
                      });
                    },
                    label: Text(
                      AppLocalizations.of(context)!.search,
                    ),
                    icon: const Icon(Icons.search),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Expanded(
            child: ListView(
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
                children: currentPreviews,
              ),
            ),
          )
        ],
      ),
    );
  }
}
