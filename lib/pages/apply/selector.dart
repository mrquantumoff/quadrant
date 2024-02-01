import 'dart:convert';
import 'dart:io';
import 'package:clipboard/clipboard.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/modpack_creator/modpack_creator.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';
import 'package:universal_feed/universal_feed.dart';
import 'package:url_launcher/url_launcher.dart';

class Selector extends StatefulWidget {
  const Selector({super.key});

  @override
  State<Selector> createState() => _SelectorState();
}

class _SelectorState extends State<Selector> {
  final TextEditingController selectedModpackController =
      TextEditingController();
  List<DropdownMenuEntry<String>> modpackOptions = [];
  String? selectedModpack;
  bool areButtonsActive = true;

  void updateOptions() {
    var newItemsString = getModpacks();
    List<DropdownMenuEntry<String>> newItems = [];
    for (var newItemString in newItemsString) {
      newItems.add(
        DropdownMenuEntry(value: newItemString, label: newItemString),
      );
    }

    setState(() {
      modpackOptions = newItems;
    });
  }

  @override
  void initState() {
    super.initState();
    updateOptions();
  }

  void checkRSS(BuildContext context) async {
    http.Response res =
        await http.get(Uri.parse("https://api.mrquantumoff.dev/blog.rss"));
    if (res.statusCode != 200) return;
    String rawFeed = res.body;

    var feed = UniversalFeed.parseFromString(rawFeed);
    for (var item in feed.items) {
      List<String> categories = [];
      for (var category in item.categories) {
        categories.add(category.value!);
      }
      bool cond1 = !(GetStorage().read<List<dynamic>>("seenItems") ?? [])
          .contains(item.guid!);
      DateTime itemDate = item.published!.parseValue()!;
      bool cond2 =
          itemDate.add(const Duration(days: 14)).isAfter(DateTime.now());
      debugPrint(" Cond2: $cond2");
      bool cond3 = GetStorage().read("rssFeeds") == true;
      bool cond4 = GetStorage().read("devMode") == true;
      if (((cond1 && cond2) || cond4) &&
          cond3 &&
          categories.contains("Minecraft Modpack Manager")) {
        var newSeenItems =
            (GetStorage().read<List<dynamic>>("seenItems") ?? []);
        newSeenItems.add(item.guid!);
        GetStorage().write("seenItems", newSeenItems);
        showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text(item.title!),
                content: Text(item.description!),
                actions: [
                  TextButton(
                      onPressed: () async {
                        await launchUrl(Uri.parse(item.link!.href.toString()));
                      },
                      child: Text(AppLocalizations.of(context)!.read))
                ],
              );
            });
      }
    }
    GetStorage().write("lastRSSfetched", DateTime.now().toIso8601String());
  }

  @override
  Widget build(BuildContext context) {
    checkRSS(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Selector
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 0),
          child: DropdownMenu(
            dropdownMenuEntries: modpackOptions,
            controller: selectedModpackController,
            onSelected: (value) {
              selectedModpack = value;
            },
            enabled: areButtonsActive,
            width: 840,
            hintText: AppLocalizations.of(context)!.modpack,
          ),
        ),

        // Buttons (Actions)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: FilledButton(
                  onPressed: areButtonsActive
                      ? () {
                          setState(
                            () {
                              areButtonsActive = false;
                            },
                          );
                          bool res = applyModpack(selectedModpack);
                          if (res) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                duration: const Duration(seconds: 1),
                                content: Text(AppLocalizations.of(context)!
                                    .setModpackSuccess),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                duration: const Duration(seconds: 1),
                                content: Text(AppLocalizations.of(context)!
                                    .setModpackFailed),
                              ),
                            );
                          }
                          setState(
                            () {
                              areButtonsActive = true;
                            },
                          );
                        }
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              duration: const Duration(seconds: 1),
                              content: Text(AppLocalizations.of(context)!
                                  .buttonsAreDisabled),
                            ),
                          );
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 5, left: 0),
                          child: Icon(Icons.check),
                        ),
                        Text(AppLocalizations.of(context)!.apply)
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: FilledButton.tonal(
                  onPressed: areButtonsActive
                      ? () {
                          setState(
                            () {
                              areButtonsActive = false;
                            },
                          );
                          bool res = clearModpack();
                          if (res) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                duration: const Duration(seconds: 1),
                                content: Text(AppLocalizations.of(context)!
                                    .setModpackSuccess),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                duration: const Duration(seconds: 1),
                                content: Text(AppLocalizations.of(context)!
                                    .setModpackFailed),
                              ),
                            );
                          }
                          setState(
                            () {
                              areButtonsActive = true;
                            },
                          );
                        }
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              duration: const Duration(seconds: 1),
                              content: Text(AppLocalizations.of(context)!
                                  .buttonsAreDisabled),
                            ),
                          );
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 5, left: 0),
                          child: Icon(Icons.delete),
                        ),
                        Text(AppLocalizations.of(context)!.clear)
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: ElevatedButton(
                  onPressed: updateOptions,
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 5, left: 0),
                          child: Icon(Icons.refresh),
                        ),
                        Text(AppLocalizations.of(context)!.reload)
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        // Open modpacks folder / Export selected modpack buttons
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8, right: 5),
              child: ActionChip(
                onPressed: () {
                  debugPrint("Open Modpacks Folder pressed.");
                  openModpacksFolder();
                },
                avatar: const Icon(Icons.folder),
                label: Text(
                    "  ${AppLocalizations.of(context)!.openModpacksFolder}"),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              child: ActionChip(
                onPressed: () async {
                  if (selectedModpack == null) return;
                  File modpackConfig = File(
                      "${getMinecraftFolder().path}/modpacks/$selectedModpack/modConfig.json");
                  if (!modpackConfig.existsSync()) return;
                  String content = await modpackConfig.readAsString();

                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title:
                            Text(AppLocalizations.of(context)!.exportOptions),
                        actions: [
                          TextButton(
                            onPressed: () async {
                              var filePickerResult = await FilePicker.platform
                                  .saveFile(fileName: "$selectedModpack.json");
                              if (filePickerResult == null) return;
                              File selectedFile = File(filePickerResult);
                              if (await selectedFile.exists()) {
                                await selectedFile.delete(recursive: true);
                              }
                              await selectedFile.create(recursive: true);

                              await selectedFile.writeAsString(content);
                            },
                            child: Text(
                              AppLocalizations.of(context)!.referenceFile,
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              if (GetStorage().read("collectUserData") ==
                                  false) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      AppLocalizations.of(context)!
                                          .enableDataSharing,
                                    ),
                                  ),
                                );
                                return;
                              }
                              collectUserInfo();
                              var machineInfo = await getMachineIdAndOs();
                              var res = await http.post(
                                  Uri.parse(
                                      "https://api.mrquantumoff.dev/api/v2/submit/quadrant_share"),
                                  headers: {
                                    "User-Agent": await generateUserAgent(),
                                    "Authorization":
                                        const String.fromEnvironment(
                                            "QUADRANT_QNT_API_KEY")
                                  },
                                  body: json.encode({
                                    "hardware_id": machineInfo.machineId,
                                    "mod_config": content,
                                    "uses_left": 5,
                                  }));

                              if (res.statusCode != 201) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      AppLocalizations.of(context)!
                                          .failedQuadrantShare,
                                    ),
                                  ),
                                );
                                return;
                              }

                              var decoded = json.decode(res.body);

                              await FlutterClipboard.copy(
                                decoded["code"].toString(),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    AppLocalizations.of(context)!
                                        .copiedToClipboard(
                                            decoded["uses_left"]),
                                  ),
                                ),
                              );
                            },
                            child: Text(
                              AppLocalizations.of(context)!.manualInput,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
                label: Text(AppLocalizations.of(context)!.exportMods),
                avatar: const Icon(Icons.upload_file_outlined),
              ),
            ),
          ],
        ),

        // Update/Create/Delete modpack
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              margin: const EdgeInsets.only(right: 5),
              child: ActionChip(
                onPressed: () async {
                  Get.to(
                    () =>
                        ModpackCreator(modpack: selectedModpackController.text),
                    transition: Transition.topLevel,
                  );
                },
                label: Text(AppLocalizations.of(context)!.createModpack),
                avatar: const Icon(Icons.add),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              child: ActionChip(
                onPressed: () async {
                  if (selectedModpackController.text != "") {
                    Get.to(
                      () => ModpackCreator(
                        modpack: selectedModpackController.text,
                        update: true,
                      ),
                      transition: Transition.topLevel,
                    );
                  }
                },
                label: Text(AppLocalizations.of(context)!.update),
                avatar: const Icon(Icons.change_circle),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              child: ActionChip(
                onPressed: () async {
                  if (selectedModpackController.text != "") {
                    Directory mods =
                        Directory("${getMinecraftFolder().path}/mods");
                    Directory modpack = Directory(
                        "${getMinecraftFolder().path}/modpacks/${selectedModpackController.text}");
                    if (mods.existsSync()) {
                      mods.deleteSync(recursive: true);
                    }
                    if (modpack.existsSync()) {
                      modpack.deleteSync(recursive: true);
                    }
                  }
                },
                label: Text(AppLocalizations.of(context)!.delete),
                avatar: const Icon(Icons.delete),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
