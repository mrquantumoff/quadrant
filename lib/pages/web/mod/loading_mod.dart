import 'package:flutter/material.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/web/mod/mod.dart';

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
        (val) => {
          setState(
            () {},
          )
        },
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

        return const Visibility.maintain(
          child:
              //   child: widget.downloadable
              //       ? const Divider(
              //           height: 1.5,
              //           thickness: 1,
              //         )
              //       : null,
              // ),
              Card.outlined(
            // elevation: 12,
            margin: EdgeInsets.symmetric(vertical: 0, horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [CircularProgressIndicator()],
            ),
          ),
        );
      }),
    );
  }
}
