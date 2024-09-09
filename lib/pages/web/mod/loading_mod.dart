import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get_storage_qnt/get_storage.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/web/mod/mod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// ignore: must_be_immutable
class LoadingMod extends StatefulWidget {
  LoadingMod({
    super.key,
    required this.modId,
    required this.source,
    required this.setAreParentButtonsActive,
    this.downloadable = true,
    this.showPreVersion = false,
    this.deletable = false,
    this.preVersion = "",
    this.versionTarget = "",
    this.modLoader = "Forge",
    this.modpack = "free",
  });

  final String modId;
  final ModSource source;
  bool downloadable = true;
  // These 3 parameters MUST be used together
  bool showPreVersion = false;
  bool deletable = false;
  String preVersion = "";
  String versionTarget = "";
  String modLoader = "Forge";
  String modpack = "free";
  Function(bool) setAreParentButtonsActive;

  @override
  State<LoadingMod> createState() => _LoadingModState();
}

class _LoadingModState extends State<LoadingMod> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: getMod(
        widget.modId,
        widget.source,
        widget.setAreParentButtonsActive,
        deletable: widget.deletable,
        preVersion: widget.preVersion,
        versionShow: widget.showPreVersion,
        downloadable: widget.downloadable,
        modLoader: widget.modLoader,
        modpack: widget.modpack,
        versionTarget: widget.versionTarget,
      ),
      builder: ((context, snapshot) {
        if (snapshot.hasData) {
          return snapshot.data!;
        }
        if (snapshot.hasError) {
          return Text("${snapshot.error}");
        }

        return Visibility.maintain(
          child: Animate(
            effects: const [
              BlurEffect(
                begin: Offset(10, 10),
                end: Offset(10, 10),
              ),
            ],
            child: Card.outlined(
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 0, vertical: 0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                              GetStorage().read("clipIcons") == true ? 80 : 0),
                          child: const CircularProgressIndicator(),
                        ),
                      ),
                      Container(
                        margin: EdgeInsets.only(
                            left: 0, top: widget.showPreVersion ? 24 : 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                FittedBox(
                                  fit: BoxFit.cover,
                                  child: Text(
                                    "...",
                                    style: TextStyle(
                                      fontSize: 24,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              margin: const EdgeInsets.only(
                                  top: 6, left: 0, bottom: 0),
                              child: const Text(
                                "...",
                                style:
                                    TextStyle(color: Colors.grey, fontSize: 16),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(
                                  top: 4, bottom: 8, left: 0, right: 16),
                              child: const Text(
                                "...",
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            const Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.download,
                                    color: Colors.grey, size: 16.5),
                                Text(
                                  "...",
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        margin:
                            const EdgeInsets.only(top: 8, bottom: 8, right: 8),
                        child: widget.downloadable
                            ? FilledButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.download),
                                label: Text(
                                    AppLocalizations.of(context)!.download),
                              )
                            : null,
                      ),
                      Container(
                        margin:
                            const EdgeInsets.only(top: 8, bottom: 8, right: 8),
                        child: FilledButton.icon(
                          onPressed: () async {},
                          icon: const Icon(Icons.file_download),
                          label: Text(AppLocalizations.of(context)!.download),
                        ),
                      ),
                      Container(
                        margin:
                            const EdgeInsets.only(top: 8, bottom: 8, right: 8),
                        child: widget.deletable
                            ? FilledButton.icon(
                                onPressed: () async {},
                                icon: const Icon(Icons.delete),
                                label:
                                    Text(AppLocalizations.of(context)!.delete),
                              )
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
