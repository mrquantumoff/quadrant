import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:mcmodpackmanager_reborn/other/backend.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mcmodpackmanager_reborn/pages/web/mod/mod.dart';

import 'package:mcmodpackmanager_reborn/pages/web/generate_user_agent.dart';

class ShareModpacksPage extends StatefulWidget {
  const ShareModpacksPage({super.key});

  @override
  State<ShareModpacksPage> createState() => _ShareModpacksPageState();
}

class DownloadedMod {
  DownloadedMod({required this.bytes, required this.file});
  List<int> bytes = [];
  File file;
}

class _ShareModpacksPageState extends State<ShareModpacksPage> {
  List<Widget> mods = [];
  List<String> modDownloadUrls = [];
  String modLoader = "";
  String version = "";
  String modpack = "";
  double progressValue = 0;
  int otherModCount = 0;
  bool isLoading = false;
  String modConfig = "";
  void setProgressValue(double value) {
    setState(() {
      progressValue = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.importMods),
      ),
      body: Center(
        child: ListView(
          shrinkWrap: true,
          children: isLoading
              ? [const LinearProgressIndicator()]
              : (mods.isEmpty || otherModCount <= 0)
                  ? []
                  : [
                      Container(
                        height: 360,
                        margin: const EdgeInsets.only(
                            bottom: 24, left: 120, right: 120),
                        child: ListView(
                          shrinkWrap: true,
                          children: mods,
                        ),
                      ),
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            AppLocalizations.of(context)!.otherMods(
                              otherModCount,
                            ),
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              List<DownloadedMod> downloadedMods = [];
                              debugPrint("$modDownloadUrls");
                              for (var downloadUrl in modDownloadUrls) {
                                int modIndex =
                                    modDownloadUrls.indexOf(downloadUrl);
                                final http.Response res = await http.get(
                                  Uri.parse(downloadUrl),
                                  headers: {
                                    "User-Agent": await generateUserAgent(),
                                  },
                                );
                                File modDestFile = File(
                                    "${getMinecraftFolder().path}/modpacks/$modpack/${Uri.parse(downloadUrl).pathSegments.last}");
                                List<int> bytes = res.bodyBytes;
                                setProgressValue(
                                    modIndex / modDownloadUrls.length);
                                downloadedMods.add(
                                  DownloadedMod(
                                      bytes: bytes, file: modDestFile),
                                );
                              }
                              Directory modpackDir = Directory(
                                  "${getMinecraftFolder().path}/modpacks/$modpack");
                              if (await modpackDir.exists()) {
                                await modpackDir.delete(recursive: true);
                              }
                              await modpackDir.create(recursive: true);
                              bool success = true;
                              for (DownloadedMod dlMod in downloadedMods) {
                                try {
                                  if (dlMod.file.existsSync()) {
                                    await dlMod.file.delete();
                                  }
                                  await dlMod.file.create(recursive: true);
                                  await dlMod.file.writeAsBytes(dlMod.bytes);
                                  setProgressValue(
                                      downloadedMods.indexOf(dlMod) +
                                          1 / downloadedMods.length);
                                } catch (e) {
                                  debugPrint(e.toString());
                                  success = false;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppLocalizations.of(context)!
                                            .downloadFail,
                                      ),
                                    ),
                                  );
                                }
                              }
                              if (success) {
                                File modpackConfig =
                                    File("${modpackDir.path}/modConfig.json");
                                debugPrint(modpackConfig.path);
                                if (modpackConfig.existsSync()) {
                                  await modpackConfig.delete();
                                }
                                await modpackConfig.create();

                                await modpackConfig.writeAsString(modConfig);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      AppLocalizations.of(context)!
                                          .downloadSuccess,
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.download),
                            label: Text(
                              AppLocalizations.of(context)!.download,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(
                            vertical: 25, horizontal: 48),
                        child: LinearProgressIndicator(
                          value: progressValue,
                        ),
                      ),
                    ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          setState(() {
            modDownloadUrls = [];
            mods = [];
            isLoading = true;
            otherModCount = 0;
          });
          FilePickerResult? filePickerResult =
              await FilePicker.platform.pickFiles(
            allowMultiple: false,
            allowedExtensions: ["json"],
            withData: true,
            lockParentWindow: true,
          );
          if (filePickerResult == null) {
            setState(() {
              isLoading = false;
            });
            return;
          }
          PlatformFile platformFile = filePickerResult.files[0];
          if (platformFile.path == null ||
              !platformFile.name.endsWith(".json")) {
            setState(() {
              isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context)!.invalidData,
                ),
              ),
            );
            return;
          }
          File file = File(platformFile.path!);
          String rawFile = await file.readAsString();
          setState(() {
            modConfig = rawFile;
          });
          try {
            Map jsonFile = json.decode(rawFile);
            if (jsonFile["modLoader"] == null ||
                jsonFile["version"] == null ||
                jsonFile["mods"] == null ||
                jsonFile["name"] == null) {
              setState(() {
                isLoading = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context)!.invalidData,
                  ),
                ),
              );
              return;
            }
            modLoader = jsonFile["modLoader"];
            version = jsonFile["version"];
            modpack = jsonFile["name"];
            List<dynamic> sourceMods = jsonFile["mods"];
            List<Widget> newMods = [];
            try {
              for (var mod in sourceMods) {
                String id = mod["id"];
                String downloadUrl = mod["downloadUrl"];
                String rawSource = mod["source"];
                late ModSource source;
                if (rawSource == "ModSource.curseForge") {
                  source = ModSource.curseForge;
                } else if (rawSource == "ModSource.modRinth") {
                  source = ModSource.modRinth;
                } else {
                  source = ModSource.online;
                }
                if (source == ModSource.curseForge ||
                    source == ModSource.modRinth) {
                  Mod mod = await getMod(id, source, (val) => null,
                      downloadAble: false);
                  newMods.add(mod);
                }
                if (source == ModSource.online) {
                  otherModCount += 1;
                }
                modDownloadUrls.add(downloadUrl);
              }
            } catch (e) {
              debugPrint(e.toString());
              setState(() {
                isLoading = false;
              });
              return;
            }
            setState(() {
              isLoading = false;

              mods = newMods;
            });
          } catch (e) {
            setState(() {
              isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context)!.invalidData,
                ),
              ),
            );
          }
        },
        icon: const Icon(Icons.file_open),
        label: Text(
          AppLocalizations.of(context)!.openFile,
        ),
      ),
    );
  }
}
