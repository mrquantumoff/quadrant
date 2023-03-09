// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:mcmodpackmanager_reborn/backend.dart';
import 'package:mcmodpackmanager_reborn/modpack_installer/web/generate_user_agent.dart';

import '../web_sources.dart';

enum ModSource { curseForge, modRinth }

enum ModClass {
  mod(6),
  resourcePack(12);

  const ModClass(this.value);
  final int value;
}

class ModFile {
  ModFile(
      {required this.downloadUrl,
      required this.fileName,
      required this.gameVersions,
      required this.fileDate});
  String downloadUrl = "";
  String fileName = "";
  List<dynamic> gameVersions = [];
  DateTime fileDate = DateTime.now();
}

// ignore: must_be_immutable
class Mod extends StatefulWidget {
  Mod({
    super.key,
    required this.name,
    required this.description,
    required this.modIconUrl,
    required this.id,
    required this.areButttonsActive,
    required this.downloadCount,
    required this.setAreButtonsActive,
    required this.source,
    required this.modClass,
  });

  final String name;
  final String description;
  final String modIconUrl;
  final int downloadCount;
  final int id;
  final ModSource source;
  final ModClass modClass;
  bool areButttonsActive;
  Function(bool) setAreButtonsActive;

  @override
  State<Mod> createState() => _ModState();
}

class _ModState extends State<Mod> {
  late TextEditingController versionFieldController;
  late TextEditingController apiFieldController;
  late TextEditingController modpackFieldController;
  late double progressValue;

  @override
  void initState() {
    super.initState();
    progressValue = 0;

    versionFieldController = TextEditingController();
    apiFieldController = TextEditingController();
    modpackFieldController = TextEditingController();
  }

  String getModpackTypeString() {
    if (widget.modClass == ModClass.mod) {
      return AppLocalizations.of(context)!.mod;
    } else if (widget.modClass == ModClass.resourcePack) {
      return AppLocalizations.of(context)!.resourcePack;
    } else {
      return "Unknown";
    }
  }

  @override
  void dispose() {
    super.dispose();
    progressValue = 0;
  }

  setProgressValue(double newValue) {
    setState(() {
      progressValue = newValue;
    });
  }

  final String apiKey =
      const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");

  @override
  Widget build(BuildContext context) {
    String desc = widget.description.length >= 48
        ? widget.description.replaceRange(48, null, "...")
        : widget.description;
    String displayName = widget.name.length >= 36
        ? widget.name.replaceRange(36, null, "...")
        : widget.name;
    return Container(
      margin: const EdgeInsets.all(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          Uri uri = Uri.parse(
            'https://api.curseforge.com/v1/games/423/versions',
          );
          List<dynamic> vrs = json.decode((await http.get(
            uri,
            headers: {
              "User-Agent": await generateUserAgent(),
              "X-API-Key": apiKey,
            },
          ))
              .body)["data"][0]["versions"];
          List<String> versions = [];
          for (var v in vrs) {
            int dotCount = 0;
            for (var c in v.toString().characters) {
              if (c == ".") dotCount++;
            }
            if (dotCount == 3 &&
                v.toString().replaceAll("Update ", "").startsWith("1.")) {
              var finVerFormat =
                  "${v.toString().replaceAll("Update ", "").split(".").first}.${v.toString().replaceAll("Update ", "").split(".")[1]}.${v.toString().replaceAll("Update ", "").split(".").last}";
              if (!versions.contains(finVerFormat)) {
                versions.add(finVerFormat);
                versions.sort(
                  (a, b) {
                    if (double.parse(a.toString().split(".")[1]) >
                        double.parse(b.toString().split(".")[1])) {
                      return 0;
                    } else {
                      return 1;
                    }
                  },
                );
              }
            }
          }
          List<DropdownMenuEntry> versionItems = [];
          List<DropdownMenuEntry> modpackItems = [];

          for (var version in versions) {
            versionItems.add(
              DropdownMenuEntry(label: version.toString(), value: version),
            );
          }

          List<String> modpacks = getModpacks(hideFree: false);

          for (var modpack in modpacks) {
            modpackItems.add(
              DropdownMenuEntry(label: modpack, value: modpack),
            );
          }

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) => AlertDialog(
              title: Text(AppLocalizations.of(context)!.installModpacks),
              actions: [
                TextButton.icon(
                    onPressed: widget.areButttonsActive
                        ? () {
                            Get.back(closeOverlays: true);
                            Get.back();
                          }
                        : () {},
                    icon: const Icon(Icons.cancel),
                    label: Text(AppLocalizations.of(context)!.cancel)),
                TextButton.icon(
                  onPressed: widget.areButttonsActive
                      ? () async {
                          String version = versionFieldController.value.text;
                          String api = apiFieldController.value.text;
                          String modpack = modpackFieldController.value.text;
                          debugPrint(api);
                          if (version.endsWith(".0")) {
                            debugPrint(version);
                            version = version.replaceRange(
                                version.length - 2, null, "");
                            debugPrint(version);
                          }
                          Uri getFilesUri = Uri.parse(
                              "https://api.curseforge.com/v1/mods/${widget.id}/files?gameVersion=${version.trim()}&sortOrder=desc&modLoaderType=${api.trim()}");
                          if (widget.modClass == ModClass.resourcePack) {
                            getFilesUri = Uri.parse(
                                "https://api.curseforge.com/v1/mods/${widget.id}/files?gameVersion=${version.trim()}&sortOrder=desc");
                          }
                          debugPrint("Installing mods url: $getFilesUri");
                          widget.setAreButtonsActive(false);
                          http.Response response =
                              await http.get(getFilesUri, headers: {
                            "User-Agent": await generateUserAgent(),
                            "X-API-Key": apiKey,
                          });
                          Map responseJson = json.decode(response.body);
                          debugPrint(responseJson.toString());
                          List<ModFile> fileMod = [];
                          if ((responseJson["data"] as List<dynamic>) == []) {
                            widget.setAreButtonsActive(true);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.of(context)!.noVersion,
                                ),
                              ),
                            );
                            Get.back(closeOverlays: true);
                            Get.back();
                          }
                          debugPrint(responseJson.toString());
                          for (var mod in responseJson["data"]) {
                            DateTime fileDate = DateTime.parse(mod["fileDate"]);
                            List<dynamic> gameVersions = mod["gameVersions"];
                            String fileName = mod["fileName"];
                            String downloadUrl = mod["downloadUrl"];

                            fileMod.add(
                              ModFile(
                                fileDate: fileDate,
                                gameVersions: gameVersions,
                                fileName: fileName,
                                downloadUrl: downloadUrl,
                              ),
                            );
                          }
                          fileMod.sort(
                            (a, b) => b.fileDate.compareTo(a.fileDate),
                          );
                          debugPrint(fileMod.toString());
                          if (fileMod.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    AppLocalizations.of(context)!.noVersion),
                              ),
                            );
                            widget.setAreButtonsActive(true);
                            Get.back(closeOverlays: true);
                            Get.back();

                            return;
                          }
                          var mod = fileMod[0];
                          // http.Response res = await http
                          //     .get(Uri.parse(mod.downloadUrl), headers: {
                          //   "User-Agent": "MinecraftModpackManager",
                          //   "X-API-Key": apiKey,
                          // });
                          var request = http.Request(
                            "GET",
                            Uri.parse(mod.downloadUrl),
                          );
                          final http.StreamedResponse streamedResponse =
                              await UserAgentClient(
                                      await generateUserAgent(), http.Client())
                                  .send(request);
                          final contentLength = streamedResponse.contentLength;

                          File modDestFile = File(
                              "${getMinecraftFolder().path}/modpacks/$modpack/${mod.fileName}");
                          if (widget.modClass == ModClass.resourcePack) {
                            modDestFile = File(
                                "${getMinecraftFolder().path}/resourcepacks/${mod.fileName}");
                          }
                          if (await modDestFile.exists()) {
                            modDestFile.delete();
                          }
                          await modDestFile.create(recursive: true);
                          debugPrint(modDestFile.path);
                          List<int> bytes = [];
                          streamedResponse.stream.listen(
                            (List<int> newBytes) {
                              bytes.addAll(newBytes);
                              final downloadedLength = bytes.length;
                              setProgressValue(
                                  downloadedLength / (contentLength ?? 1));
                              debugPrint(progressValue.toString());
                            },
                            onDone: () async {
                              await modDestFile.writeAsBytes(bytes,
                                  flush: true);
                              setProgressValue(1);
                              debugPrint("Downloaded");
                              widget.setAreButtonsActive(true);

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(AppLocalizations.of(context)!
                                      .downloadSuccess),
                                ),
                              );
                              Get.back(closeOverlays: true);
                              Get.back();
                            },
                            onError: (e) {
                              debugPrint(e);
                            },
                            cancelOnError: true,
                          );
                        }
                      : () {},
                  icon: const Icon(Icons.file_download),
                  label: Text(AppLocalizations.of(context)!.download),
                )
              ],
              content: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: DropdownMenu(
                      controller: versionFieldController,
                      dropdownMenuEntries: versionItems,
                      label: Text(AppLocalizations.of(context)!.chooseVersion),
                      width: 240,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: DropdownMenu(
                      label: Text(
                          AppLocalizations.of(context)!.choosePreferredAPI),
                      controller: apiFieldController,
                      dropdownMenuEntries: const [
                        DropdownMenuEntry(label: "Fabric", value: "Fabric"),
                        DropdownMenuEntry(label: "Forge", value: "Forge"),
                        DropdownMenuEntry(label: "Quilt", value: "Quilt"),
                        DropdownMenuEntry(label: "Rift", value: "Rift"),
                      ],
                      width: 240,
                      enabled: widget.modClass == ModClass.mod,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: DropdownMenu(
                      label: Text(AppLocalizations.of(context)!.chooseModpack),
                      controller: modpackFieldController,
                      dropdownMenuEntries: modpackItems,
                      width: 240,
                      enabled: widget.modClass == ModClass.mod,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: CircularProgressIndicator(
                      value: progressValue,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: Card(
          elevation: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsetsDirectional.only(start: 12, top: 6.5),
                child: Image(
                  image: NetworkImage(widget.modIconUrl),
                  alignment: Alignment.centerRight,
                  height: 84,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(fontSize: 32),
                        ),
                        const Divider(thickness: 50),
                        Container(
                          margin: const EdgeInsets.only(left: 14, top: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Icon(Icons.download,
                                  color: Colors.grey, size: 20),
                              Text(
                                widget.downloadCount.toString(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 18, right: 18, top: 8),
                    child: Text(
                      desc,
                      style: const TextStyle(color: Colors.grey, fontSize: 24),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 8, left: 18),
                    child: Text(
                      getModpackTypeString(),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
