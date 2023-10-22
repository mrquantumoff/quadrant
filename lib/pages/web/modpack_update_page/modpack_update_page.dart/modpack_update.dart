import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:quadrant/pages/web/mod/mod.dart';

class UpdateModpackPage extends StatefulWidget {
  const UpdateModpackPage(
      {super.key,
      required this.currentMods,
      required this.targetVersion,
      required this.name});

  final List<dynamic> currentMods;
  final String name;
  final String targetVersion;

  @override
  State<UpdateModpackPage> createState() => _UpdateModpackPageState();
}

class _UpdateModpackPageState extends State<UpdateModpackPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Get.back();
          },
        ),
        title: Text(AppLocalizations.of(context)!.update),
      ),
      body: Center(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: []),
      ),
    );
  }
}
