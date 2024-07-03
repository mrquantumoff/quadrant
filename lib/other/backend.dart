import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:clipboard/clipboard.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:get_storage_qnt/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';
import 'package:quadrant/pages/web/mod/install_mod_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:quadrant/pages/web/mod/mod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

Directory getMinecraftFolder({bool onInit = false}) {
  if (GetStorage().read("minecraftFolder") != null && !onInit) {
    String res = GetStorage().read("minecraftFolder").toString();
    return Directory(res);
  }
  String userHome =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']!;
  if (Platform.isLinux) {
    return Directory("$userHome/.minecraft");
  } else if (Platform.isMacOS) {
    return Directory("$userHome/Library/Application Support/minecraft");
  } else {
    return Directory("$userHome\\AppData\\Roaming\\.minecraft");
  }
}

List<String> getModpacks({bool hideFree = true}) {
  getMinecraftFolder().createSync(recursive: true);
  Directory modpackFolder = Directory("${getMinecraftFolder().path}/modpacks");
  modpackFolder.createSync(recursive: true);
  List<String> modpacks = [];
  for (var entity
      in modpackFolder.listSync(recursive: false, followLinks: false)) {
    if (entity.statSync().type == FileSystemEntityType.directory &&
        (!(entity.path.endsWith("modpacks/free") ||
                entity.path.endsWith("modpacks\\free")) ||
            !hideFree)) {
      modpacks.add(entity.path.split("/").last.split("\\").last);
    }
  }
  return modpacks;
}

bool applyModpack(String? modpack) {
  var minecraftFolder = getMinecraftFolder();

  if (modpack == null) return false;

  Directory modpackFolder =
      Directory("${minecraftFolder.path}/modpacks/$modpack");
  if (!modpackFolder.existsSync()) return false;

  Directory modsFolder = Directory("${minecraftFolder.path}/mods");
  Link link = Link(modsFolder.path);

  if (modsFolder.existsSync() &&
      modsFolder.resolveSymbolicLinksSync() != modsFolder.path) {
    try {
      link.updateSync(
        modpackFolder.path,
      );
      return true;
    } catch (e) {
      debugPrint("Error ${e.toString()}");
      return false;
    }
  } else if (modsFolder.existsSync()) {
    modsFolder.deleteSync(recursive: true);

    try {
      link.createSync(
        modpackFolder.path,
        recursive: true,
      );
      return true;
    } catch (e) {
      debugPrint("Error ${e.toString()}");
      return false;
    }
  } else {
    try {
      link.createSync(
        modpackFolder.path,
        recursive: true,
      );
      return true;
    } catch (e) {
      debugPrint("Error ${e.toString()}");
      return false;
    }
  }
}

bool clearModpack() {
  Directory minecraftFolder = getMinecraftFolder();
  Directory freeModpacks = Directory("${minecraftFolder.path}/modpacks/free");
  try {
    freeModpacks.createSync(recursive: true);
    return applyModpack("free");
  } catch (e) {
    return false;
  }
}

void openModpacksFolder() {
  if (Platform.isLinux) {
    Process.runSync("xdg-open", ["."],
        workingDirectory: "${getMinecraftFolder().path}/modpacks",
        runInShell: true);
  } else if (Platform.isWindows) {
    Process.runSync("explorer", ["."],
        workingDirectory:
            "${getMinecraftFolder().path.replaceAll("/", "\\")}\\modpacks",
        runInShell: true);
  } else {
    Process.runSync("open", ["."],
        workingDirectory: "${getMinecraftFolder().path}/modpacks",
        runInShell: true);
  }
}

void overwriteMinecraftFolder(Function() updateText) async {
  String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
  if (selectedDirectory == null) {
    return;
  }
  GetStorage().write("minecraftFolder", selectedDirectory);
  updateText();
}

void clearMinecraftFolderOverwrite(Function() updateText) async {
  GetStorage().write(
    "minecraftFolder",
    getMinecraftFolder(onInit: true).path,
  );
  updateText();
}

Future<Map<String, String>> getReleaseInfo() async {
  Uri apiLink = Uri.parse(
      "https://api.github.com/repos/mrquantumoff/quadrant/releases/latest");

  Map<String, String> headers = {
    "User-Agent": await generateUserAgent(),
  };
  try {
    final result = await InternetAddress.lookup('google.com');
    if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {}
  } on SocketException catch (_) {
    return {
      "latestRelease": "v",
      "currentRelease": "",
      "url": "https://github.com/mrquantumoff/quadrant/releases/latest"
    };
  }
  http.Response latestReleaseResponse =
      await http.get(apiLink, headers: headers);
  Map response = json.decode(latestReleaseResponse.body);
  dynamic latestRelease = response["tag_name"].toString();
  PackageInfo packageInfo = await PackageInfo.fromPlatform();

  return {
    "latestRelease": latestRelease,
    "currentRelease": packageInfo.version,
    "url": "https://github.com/mrquantumoff/quadrant/releases/latest"
  };
}

Future<void> shareModpack(BuildContext context, String content) async {
  if (GetStorage().read("collectUserData") == false) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.enableDataSharing,
        ),
      ),
    );
    return;
  }
  collectUserInfo();
  var machineInfo = await getMachineIdAndOs();
  const storage = FlutterSecureStorage();
  String? token = await storage.read(key: "quadrant_id_token");
  if (token != null) {
    var res = await http.post(
        Uri.parse(
            "https://api.mrquantumoff.dev/api/v3/quadrant/share/submit/id"),
        headers: {
          "User-Agent": await generateUserAgent(),
          "Authorization": "Bearer $token"
        },
        body: json.encode({
          "hardware_id": machineInfo.machineId,
          "mod_config": content,
        }));
    if (res.statusCode == 201) {
      var decoded = json.decode(res.body);

      await FlutterClipboard.copy(
        decoded["code"].toString(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            AppLocalizations.of(context)!
                .copiedToClipboard(decoded["uses_left"]),
          ),
        ),
      );
      return;
    }
  }
  var res = await http.post(
      Uri.parse("https://api.mrquantumoff.dev/api/v3/quadrant/share/submit"),
      headers: {
        "User-Agent": await generateUserAgent(),
        "Authorization": const String.fromEnvironment("QUADRANT_QNT_API_KEY")
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
          AppLocalizations.of(context)!.failedQuadrantShare,
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
      duration: const Duration(seconds: 5),
      content: Text(
        AppLocalizations.of(context)!.copiedToClipboard(decoded["uses_left"]),
      ),
    ),
  );
}

Future<Mod> getMod(
  String modId,
  ModSource source,
  Function(bool val) setAreParentButtonsActive, {
  bool downloadable = true,
  // These 3 parameters MUST be used together
  bool versionShow = false,
  bool deletable = false,
  String preVersion = "",
  String versionTarget = "",
  String modLoader = "Forge",
  String modpack = "free",
}) async {
  if (source == ModSource.curseForge) {
    try {
      final String apiKey =
          const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");
      final Map<String, String> headers = {
        "User-Agent": await generateUserAgent(),
        "X-API-Key": apiKey,
      };
      http.Response res = await http.get(
        Uri.parse("https://api.curseforge.com/v1/mods/$modId"),
        headers: headers,
      );

      final resJSON = json.decode(res.body)["data"];

      int modClassId = resJSON["classId"];

      late ModClass modClass;

      if (modClassId == 6) {
        modClass = ModClass.mod;
      } else if (modClassId == 12) {
        modClass = ModClass.resourcePack;
      } else {
        modClass = ModClass.shaderPack;
      }

      String latestVersionUrl = "";

      if (versionShow) {
        try {
          http.Response res = await http.get(
            Uri.parse(
                "https://api.curseforge.com/v1/mods/$modId/files?gameVersion=$versionTarget"),
            headers: headers,
          );

          Map parsed = json.decode(res.body);
          // debugPrint("\n\n${res.body}\n\n");
          List<Map> gameVersions = [];
          for (Map item in parsed["data"]) {
            if (item["gameVersions"].contains(modLoader)) {
              gameVersions.add(item);
            }
          }
          gameVersions.sort(
            (a, b) {
              return DateTime.parse(a["fileDate"])
                  .compareTo(DateTime.parse(b["fileDate"]));
            },
          );

          latestVersionUrl = Uri.decodeFull(gameVersions.last["downloadUrl"]);
          if (preVersion == gameVersions.last["fileName"]) {
            latestVersionUrl = "";
          } else {
            debugPrint(json.encode(gameVersions));
          }
        } catch (e) {
          debugPrint("$e");
        }
      }

      String logo =
          "https://raw.githubusercontent.com/mrquantumoff/quadrant/master/assets/icons/logo.png";
      if (resJSON["logo"] != null) {
        logo = resJSON["logo"]["thumbnailUrl"];
      }

      debugPrint("Mod ID gotten: ${resJSON["id"]}");
      return Mod(
        name: resJSON["name"].toString(),
        description: resJSON["summary"].toString(),
        downloadCount: int.parse(resJSON["downloadCount"].toString()),
        modIconUrl: logo,
        id: resJSON["id"].toString(),
        setAreParentButtonsActive: setAreParentButtonsActive,
        slug: resJSON["slug"].toString(),
        modClass: modClass,
        source: ModSource.curseForge,
        downloadable: downloadable,
        preVersion: preVersion,
        showPreVersion: versionShow,
        versionTarget: versionTarget,
        modpackToUpdate: modpack,
        newVersionUrl: latestVersionUrl,
        deletable: deletable,
      );
    } catch (e) {
      debugPrint("$e");
      rethrow;
    }
  } else {
    Map<String, String> headers = {
      "User-Agent": await generateUserAgent(),
    };

    http.Response res = await http.get(
      Uri.parse("https://api.modrinth.com/v2/project/$modId"),
      headers: headers,
    );

    final resJSON = json.decode(res.body);
    late ModClass modClass;
    final modClassString = resJSON["project_type"];
    if (modClassString == "mod") {
      modClass = ModClass.mod;
    } else if (modClassString == "resourcepack") {
      modClass = ModClass.resourcePack;
    } else if (modClassString == "shader") {
      modClass = ModClass.shaderPack;
    } else {
      throw Exception("Unsupported Mod Type: $modClassString");
    }

    String latestVersionUrl = "";

    if (versionShow) {
      http.Response res = await http.get(
        Uri.parse(
            "https://api.modrinth.com/v2/project/$modId/version?loaders=[\"${modLoader.toLowerCase()}\"]&game_versions=[\"$versionTarget\"]&featured=true"),
        headers: headers,
      );

      List parsed = json.decode(res.body);
      try {
        for (dynamic item in parsed) {
          dynamic primaryFile;
          for (dynamic file in item["files"]) {
            if (file["primary"] == true) {
              primaryFile = file;
              break;
            }
          }
          primaryFile ??= item["files"][0];
          if (primaryFile["filename"].toString().trim() == preVersion.trim()) {
            latestVersionUrl = "";
          } else {
            latestVersionUrl = Uri.decodeFull(primaryFile["url"]);
          }
        }
      } catch (e) {
        debugPrint("$e");
      }
    }

    return Mod(
      name: resJSON["title"],
      description: resJSON["description"],
      modIconUrl: resJSON["icon_url"],
      id: resJSON["id"],
      downloadCount: resJSON["downloads"],
      setAreParentButtonsActive: setAreParentButtonsActive,
      source: ModSource.modRinth,
      slug: resJSON["slug"],
      modClass: modClass,
      downloadable: downloadable,
      preVersion: preVersion,
      showPreVersion: versionShow,
      versionTarget: versionTarget,
      modpackToUpdate: modpack,
      newVersionUrl: latestVersionUrl,
      deletable: deletable,
    );
  }
}

Future<void> syncModpack(
    BuildContext context, String modConfigRaw, bool overwrite) async {
  Map modConfig = json.decode(modConfigRaw);
  String selectedModpack = modConfig["name"];
  File selectedModpackSyncFile = File(
    "${getMinecraftFolder().path}/modpacks/$selectedModpack/quadrantSync.json",
  );

  if (!selectedModpackSyncFile.existsSync()) {
    await selectedModpackSyncFile.create(recursive: true);
  }
  const storage = FlutterSecureStorage();
  String? token = await storage.read(key: "quadrant_id_token");
  if (token == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.noQuadrantID,
        ),
      ),
    );
    return;
  }

  String modLoader = modConfig["modLoader"];
  String mcVersion = modConfig["version"];
  List mods = modConfig["mods"];
  int timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;

  debugPrint(timestamp.toString());
  http.Response res = await http.post(
    Uri.parse(
      "https://api.mrquantumoff.dev/api/v3/quadrant/sync/submit",
    ),
    headers: {
      "User-Agent": await generateUserAgent(),
      "Authorization": "Bearer $token"
    },
    body: json.encode(
      {
        "name": selectedModpack,
        "mc_version": mcVersion,
        "mod_loader": modLoader,
        "mods": json.encode(mods),
        "overwrite": overwrite,
        "last_synced": timestamp,
      },
    ),
  );
  if (res.statusCode != 200) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.body,
        ),
      ),
    );
    return;
  }
  await selectedModpackSyncFile.writeAsString(
    json.encode({"last_synced": json.decode(res.body)["last_synced"]}),
  );
  if (overwrite) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(
          AppLocalizations.of(context)!.modpackUpdated,
        ),
      ),
    );
  }
}

void installModByProtocol(int modId, int fileId, Function() fail) async {
  try {
    final String apiKey =
        const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");
    String id = modId.toString().trim();
    String rawUri = "https://api.curseforge.com/v1/mods/$id";
    http.Response res = await http.get(
      Uri.parse(rawUri),
      headers: {
        "User-Agent": await generateUserAgent(),
        "X-API-Key": apiKey,
      },
    );
    debugPrint("Mod ID: $id\nFile ID: $fileId");
    Map responseJson = json.decode(res.body);
    Map mod = responseJson["data"];
    String name = mod["name"];
    String summary = mod["summary"];
    String modIconUrl =
        "https://github.com/mrquantumoff/quadrant/raw/master/assets/icons/logo.png";
    int downloadCount = mod["downloadCount"];
    try {
      String mModIconUrl = mod["logo"]["thumbnailUrl"].toString().trim();
      if (mModIconUrl == "") {
        throw Exception("No proper icon");
      }
      Uri.parse(mModIconUrl);
      modIconUrl = mModIconUrl;
      // ignore: empty_catches
    } catch (e) {}
    String slug = mod["slug"];
    List<dynamic> categories = mod["categories"];
    late ModClass modClass;

    /*
  mod(6),
  resourcePack(12),
  shaderPack(4546);
  */

    for (Map category in categories) {
      if (category["classId"] == 6) {
        modClass = ModClass.mod;
      } else if (category["classId"] == 12) {
        modClass = ModClass.resourcePack;
      } else if (category["classId"] == 4546) {
        modClass = ModClass.resourcePack;
      }
    }
    var finalMod = Mod(
      description: summary,
      name: name,
      id: id,
      modIconUrl: modIconUrl,
      slug: slug,
      setAreParentButtonsActive: (bool newValue) {},
      downloadCount: downloadCount,
      source: ModSource.curseForge,
      modClass: modClass,
    );
    Uri uri = Uri.parse(
      'https://api.modrinth.com/v2/tag/game_version',
    );
    List<dynamic> vrs = json.decode((await http.get(
      uri,
      headers: {
        "User-Agent": await generateUserAgent(),
      },
    ))
        .body);
    List<String> versions = [];
    for (var v in vrs) {
      if (v["version_type"] == "release") {
        versions.add(v["version"].toString());
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
    Get.to(
      () => InstallModPage(
        versions: versionItems,
        mod: finalMod,
        modpacks: modpackItems,
        source: ModSource.curseForge,
        modClass: modClass,
        installFileId: fileId,
      ),
      preventDuplicates: false,
      transition: Transition.upToDown,
    );
  } catch (e) {
    fail();
  }
}

void dataCollectionInit() async {
  if (GetStorage().read("collectUserData") == true) {
    //  try {
    collectUserInfo();
    // }
    // // ignore: empty_catches
    // catch (e) {
    //   debugPrint("Data collection failed: $e");
    // }
  } else if (GetStorage().read("collectUserData") == null) {
    MachineIdAndOS os = await getMachineIdAndOs();

    bool collectUserDataByDefault = false;

    if (os.os.toLowerCase().contains("windows")) {
      collectUserDataByDefault = true;
    }
    GetStorage().write("collectUserData", collectUserDataByDefault);
  }
}

class MachineIdAndOS {
  MachineIdAndOS({required this.machineId, required this.os});
  String machineId;
  String os;
}

Future<MachineIdAndOS> getMachineIdAndOs() async {
  late final String machineIdUnencoded;
  late final String os;
  final deviceInfoPlugin = DeviceInfoPlugin();
  if (Platform.isLinux) {
    final linuxInfo = await deviceInfoPlugin.linuxInfo;
    os = linuxInfo.prettyName;
    machineIdUnencoded = linuxInfo.machineId ?? "unknown";
  } else if (Platform.isWindows) {
    final windowsInfo = await deviceInfoPlugin.windowsInfo;
    os =
        "Windows ${windowsInfo.majorVersion.toSigned(100)} ${windowsInfo.displayVersion}; build number: ${windowsInfo.buildNumber}";
    machineIdUnencoded = windowsInfo.deviceId;
  } else if (Platform.isMacOS) {
    final macOSInfo = await deviceInfoPlugin.macOsInfo;
    os = "MacOS ${macOSInfo.osRelease}";
    machineIdUnencoded = macOSInfo.systemGUID!;
  }
  return MachineIdAndOS(
      machineId: base64Url.encode(utf8.encode(machineIdUnencoded)), os: os);
}

Future<List<DropdownMenuEntry>> getVersions() async {
  List<DropdownMenuEntry> items = [];
  Uri uri = Uri.parse(
    'https://api.modrinth.com/v2/tag/game_version',
  );
  List<dynamic> vrs = json.decode((await http.get(
    uri,
    headers: {
      "User-Agent": await generateUserAgent(),
    },
  ))
      .body);
  List<String> versions = [];
  for (var v in vrs) {
    if (v["version_type"] == "release") {
      versions.add(v["version"].toString());
    }
  }

  for (var version in versions) {
    items.add(
      DropdownMenuEntry(label: version.toString(), value: version),
    );
  }
  return items;
}

void collectUserInfo({bool saveToFile = false}) async {
  /*
    interface IAppInfo {
      version: string;
      os: string;
      modrinthUsage: number;
      curseforgeUsage: number;
      referenceFileUsage: number;
      manualInputUsage: number;
      hardwareId: string;
      date: string;
      country: string;
  }
  */

  try {
    debugPrint("Collecting user info");
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final String version = packageInfo.version;

    MachineIdAndOS info = await getMachineIdAndOs();

    final String os = info.os;
    final String machineId = info.machineId;

    debugPrint("Current OS: $os");
    var res = await http.get(
      Uri.parse("https://api.myip.com"),
    );
    Map responseJSON = json.decode(res.body);
    final String country = responseJSON["country"] ?? "Unknown";
    final int modrinthUsage = GetStorage().read("modrinthUsage") ?? 0;
    final int curseForgeUsage = GetStorage().read("curseForgeUsage") ?? 0;
    final int referenceFileUsage = GetStorage().read("referenceFileUsage") ?? 0;
    final int manualInputUsage = GetStorage().read("manualInputUsage") ?? 0;
    Map response = {
      "version": version,
      "os": os,
      "modrinth_usage": modrinthUsage,
      "curseforge_usage": curseForgeUsage,
      "reference_file_usage": referenceFileUsage,
      "manual_input_usage": manualInputUsage,
      "hardware_id": machineId,
      "date": DateTime.now().toUtc().toIso8601String(),
      "country": country
    };
    String postBody = json.encode(response);
    debugPrint(postBody);

    if (GetStorage().read("collectUserData") == true &&
        GetStorage().read("devMode") == false) {
      var result = await http.post(
        Uri.parse("https://api.mrquantumoff.dev/api/v3/quadrant/usage/submit"),
        headers: {
          "User-Agent": await generateUserAgent(),
          "Authorization": const String.fromEnvironment("QUADRANT_QNT_API_KEY")
        },
        body: postBody,
      );
      if (result.body.contains("Updated") || result.body.contains("Created")) {
        GetStorage().write("lastDataSent", DateTime.now().toUtc().toString());
      }
      // debugPrint(result.body);
    }
    if (saveToFile) {
      var filePickerResult =
          await FilePicker.platform.saveFile(fileName: "userDataReport.json");
      if (filePickerResult == null) return;
      File saveFile = File(filePickerResult);
      await saveFile.create(recursive: true);
      await saveFile.writeAsString(postBody);
    }
  } catch (e) {
    debugPrint("Failed to get user info ($e)");
  }
}

const _chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
Random _rnd = Random();

String getRandomString(int length) => String.fromCharCodes(Iterable.generate(
    length, (_) => _chars.codeUnitAt(_rnd.nextInt(_chars.length))));

void deleteUsageInfo() async {
  MachineIdAndOS info = await getMachineIdAndOs();

  await http.delete(
    Uri.parse(
        "https://api.mrquantumoff.dev/api/v3/quadrant/usage/delete?hardware_id=${info.machineId}"),
    headers: {
      "User-Agent": await generateUserAgent(),
      "Authorization": const String.fromEnvironment("QUADRANT_QNT_API_KEY")
    },
  );
}
