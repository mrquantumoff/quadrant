import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:mcmodpackmanager_reborn/backend.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mcmodpackmanager_reborn/modpack_installer/web/mod.dart';

import 'package:mcmodpackmanager_reborn/modpack_installer/web/generate_user_agent.dart';
import 'package:mcmodpackmanager_reborn/modpack_installer/web_sources.dart';

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

  void setProgressValue(double value) {
    setState(() {
      progressValue = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.shareModpacks),
      ),
      body: Center(
        child: ListView(
          children: [
            Container(
              height: 360,
              width: 840,
              margin: const EdgeInsets.only(bottom: 24),
              child: ListView(
                shrinkWrap: true,
                children: mods,
              ),
            ),
            Column(
              children: mods.isEmpty
                  ? []
                  : [
                      TextButton.icon(
                        onPressed: () async {
                          List<DownloadedMod> downloadedMods = [];
                          for (var downloadUrl in modDownloadUrls) {
                            http.Request request = http.Request(
                              "GET",
                              Uri.parse(downloadUrl),
                            );
                            final http.StreamedResponse streamedResponse =
                                await UserAgentClient(await generateUserAgent(),
                                        http.Client())
                                    .send(request);
                            int? contentLength = streamedResponse.contentLength;
                            File modDestFile = File(
                                "${getMinecraftFolder().path}/modpacks/$modpack/${streamedResponse.request!.url.pathSegments.last}");
                            List<int> bytes = [];
                            streamedResponse.stream.listen(
                              (List<int> newBytes) {
                                bytes.addAll(newBytes);
                                final downloadedLength = bytes.length;
                                setProgressValue(
                                    downloadedLength / (contentLength ?? 1));
                              },
                              onDone: () {
                                downloadedMods.add(
                                  DownloadedMod(
                                      bytes: bytes, file: modDestFile),
                                );
                              },
                            );
                            final downloadedLength = bytes.length;
                            setProgressValue(
                                downloadedLength / (contentLength ?? 1));
                          }
                          Directory modpackDir = Directory(
                              "${getMinecraftFolder().path}/$modpack");
                          if (await modpackDir.exists()) {
                            await modpackDir.delete(recursive: true);
                          }
                          await modpackDir.create(recursive: true);
                          bool success = true;
                          for (DownloadedMod dlMod in downloadedMods) {
                            try {
                              if (!dlMod.file.existsSync()) {
                                await dlMod.file.create(recursive: true);
                                await dlMod.file.writeAsBytes(dlMod.bytes);
                              }
                              setProgressValue(downloadedMods.indexOf(dlMod) +
                                  1 / downloadedMods.length);
                            } catch (e) {
                              debugPrint(e.toString());
                              success = false;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    AppLocalizations.of(context)!.downloadFail,
                                  ),
                                ),
                              );
                            }
                          }
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.of(context)!.downloadSuccess,
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
                      Container(
                        margin: const EdgeInsets.symmetric(
                            vertical: 50, horizontal: 48),
                        child: LinearProgressIndicator(
                          value: progressValue,
                        ),
                      ),
                    ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          setState(() {
            modDownloadUrls = [];
            mods = [];
          });
          FilePickerResult? filePickerResult =
              await FilePicker.platform.pickFiles(
            allowMultiple: false,
            allowedExtensions: ["json"],
            withData: true,
            lockParentWindow: true,
          );
          if (filePickerResult == null) {
            return;
          }
          PlatformFile platformFile = filePickerResult.files[0];
          if (platformFile.path == null ||
              !platformFile.name.endsWith(".json")) {
            return;
          }
          File file = File(platformFile.path!);
          String rawFile = await file.readAsString();
          Map jsonFile = json.decode(rawFile);
          if (jsonFile["modLoader"] == null ||
              jsonFile["version"] == null ||
              jsonFile["mods"] == null ||
              jsonFile["name"] == null) {
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
                modDownloadUrls.add(downloadUrl);
              }
            }
          } catch (e) {
            debugPrint(e.toString());
            return;
          }
          setState(() {
            mods = newMods;
          });
        },
        icon: const Icon(Icons.file_open),
        label: Text(
          AppLocalizations.of(context)!.openFile,
        ),
      ),
    );
  }
}
