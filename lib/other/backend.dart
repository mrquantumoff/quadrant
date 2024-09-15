import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:clipboard/clipboard.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:get_storage_qnt/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:io/io.dart' as io;
import 'package:local_notifier/local_notifier.dart';
import 'package:quadrant/pages/apply/modpack_preview.dart';
import 'package:quadrant/pages/modpack_importer/import_modpacks/import_modpacks_page.dart';
import 'package:quadrant/pages/modpack_importer/import_modpacks/synced_modpack.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';
import 'package:quadrant/pages/web/mod/install_mod_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:quadrant/pages/web/mod/mod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:window_manager/window_manager.dart';

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

Future<List<ModpackPreview>> getModpackPreviews({String? searchQuery}) async {
  List<String> modpacks = getModpacks();

  List<ModpackPreview> previews = [];

  for (String modpackName in modpacks) {
    File modpackConfig = File(
        "${getMinecraftFolder().path}/modpacks/$modpackName/modConfig.json");
    File syncConfig = File(
        "${getMinecraftFolder().path}/modpacks/$modpackName/quadrantSync.json");

    int modCount = 0;
    String loader = "-";
    String mcVersion = "-";
    int lastSynced = 0;
    Map<dynamic, dynamic> modConfig = {
      "name": modpackName,
      "version": mcVersion,
      "mods": [],
      "modLoader": loader,
    };
    bool isApplied = false;

    File currentModpackInfo =
        File("${getMinecraftFolder().path}/mods/modConfig.json");
    if (await currentModpackInfo.exists()) {
      Map currentModConfig =
          json.decode(await currentModpackInfo.readAsString());
      if (currentModConfig["name"] == modpackName) {
        isApplied = true;
      }
    }
    if (await modpackConfig.exists()) {
      modConfig = json.decode(await modpackConfig.readAsString());
      loader = modConfig["modLoader"] ?? "-";
      mcVersion = modConfig["version"] ?? "-";
      modCount = ((modConfig["mods"] ?? []) as List<dynamic>).length;
    }
    if (await syncConfig.exists()) {
      Map modConfig = json.decode(await syncConfig.readAsString());
      lastSynced = modConfig["last_synced"];
    }

    previews.add(
      ModpackPreview(
        name: modpackName,
        loader: loader,
        modCount: modCount,
        lastSynced: lastSynced,
        mcVersion: mcVersion,
        modConfig: modConfig,
        isApplied: isApplied,
      ),
    );
  }

  if (searchQuery != null) {
    String query = searchQuery.trim().toLowerCase();
    List<ModpackPreview> searchedPreviews = [];
    debugPrint("Search Query: $query");
    for (var preview in previews) {
      if (preview.loader.toLowerCase().contains(query) ||
          preview.mcVersion.toLowerCase().contains(query) ||
          preview.name.toLowerCase().contains(query)) {
        searchedPreviews.add(preview);
      }
    }
    return searchedPreviews;
  }

  return previews;
}

Future<bool> applyModpack(String? modpack) async {
  var minecraftFolder = getMinecraftFolder();

  if (modpack == null) return false;
  if ((modpack.contains("\\") ||
      modpack.contains("?") ||
      modpack.contains(">") ||
      modpack.contains("<") ||
      modpack.contains(":") ||
      modpack.contains("\"") ||
      modpack.contains("/") ||
      modpack.contains("|") ||
      modpack.contains("*"))) {
    modpack = modpack.replaceAllMapped(RegExp('[<>:"/\\|?*]'), (_) => "_");
  }

  Directory modpackFolder =
      Directory("${minecraftFolder.path}/modpacks/$modpack");
  if (!await modpackFolder.exists()) return false;

  Directory modsFolder = Directory("${minecraftFolder.path}/mods");

  String modsPath = modsFolder.path.replaceAll("\\", "/");

  if (await modsFolder.exists() &&
      (await modsFolder.resolveSymbolicLinks()).replaceAll("\\", "/") !=
          modsPath) {
    Link link = Link(modsFolder.path);

    try {
      if (kDebugMode) {
        debugPrint("Updating mods folder");
      }
      await link.update(
        modpackFolder.path,
      );
      return true;
    } catch (e) {
      debugPrint("Error ${e.toString()}");
      return false;
    }
  } else if (modsFolder.existsSync()) {
    Link link = Link(modsFolder.path);

    try {
      if (kDebugMode) {
        debugPrint("Replacing mods folder");
      }

      Directory oldModsFolder = Directory(
          "${minecraftFolder.path}/modpacks/mods-${DateTime.now().millisecondsSinceEpoch}");

      await io.copyPath(modsFolder.path, oldModsFolder.path);
      await modsFolder.delete(recursive: true);

      await link.create(
        modpackFolder.path,
        recursive: true,
      );
      return true;
    } catch (e) {
      debugPrint("Error ${e.toString()}");
      return false;
    }
  } else {
    Link link = Link(modsFolder.path);

    if (kDebugMode) {
      debugPrint("Creating mods folder");
    }
    try {
      await link.create(
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

Future<bool> clearModpack() async {
  Directory minecraftFolder = getMinecraftFolder();
  Directory freeModpacks = Directory("${minecraftFolder.path}/modpacks/free");
  try {
    await freeModpacks.create(recursive: true);
    return await applyModpack("free");
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
  Map response = json.decode(utf8.decode(latestReleaseResponse.bodyBytes));
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
      var decoded = json.decode(utf8.decode(res.bodyBytes));

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

  var decoded = json.decode(utf8.decode(res.bodyBytes));

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

      final resJSON = json.decode(utf8.decode(res.bodyBytes))["data"];

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

          Map parsed = json.decode(utf8.decode(res.bodyBytes));
          // debugPrint("\n\n${utf8.decode(res.bodyBytes)}\n\n");
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

      List<String> screenshots = [];

      for (dynamic screenshot in resJSON["screenshots"]) {
        screenshots.add(screenshot["thumbnailUrl"]);
      }

      String logo =
          "https://raw.githubusercontent.com/mrquantumoff/quadrant/master/assets/icons/logo.png";
      if (resJSON["logo"] != null) {
        logo = resJSON["logo"]["url"];
      }

      debugPrint("Mod ID gotten: ${resJSON["id"]}");
      return Mod(
        name: resJSON["name"].toString(),
        description: resJSON["summary"].toString(),
        downloadCount: int.parse(resJSON["downloadCount"].toString()),
        modIconUrl: logo,
        thumbnailUrl: screenshots,
        id: resJSON["id"].toString(),
        setAreParentButtonsActive: setAreParentButtonsActive,
        slug: resJSON["slug"].toString(),
        rawMod: resJSON,
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

    final resJSON = json.decode(utf8.decode(res.bodyBytes));

    List<String> screenshots = [];

    for (dynamic screenshot in resJSON["gallery"] ?? []) {
      screenshots.add(screenshot["url"]);
    }

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

      List parsed = json.decode(utf8.decode(res.bodyBytes));
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
      rawMod: resJSON,
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
      thumbnailUrl: screenshots,
    );
  }
}

Future<void> syncModpack(
    BuildContext context, String modConfigRaw, bool overwrite) async {
  Map modConfig = json.decode(modConfigRaw);
  String selectedModpack = modConfig["name"];

  if ((selectedModpack.contains("\\") ||
      selectedModpack.contains("?") ||
      selectedModpack.contains(">") ||
      selectedModpack.contains("<") ||
      selectedModpack.contains(":") ||
      selectedModpack.contains("\"") ||
      selectedModpack.contains("/") ||
      selectedModpack.contains("|") ||
      selectedModpack.contains("*"))) {
    selectedModpack = selectedModpack.replaceAllMapped(
      RegExp('[<>:"/\\|?*]'),
      (_) => "_",
    );
  }

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
          utf8.decode(res.bodyBytes),
        ),
      ),
    );
    return;
  }
  await selectedModpackSyncFile.writeAsString(
    json.encode({
      "last_synced": json.decode(utf8.decode(res.bodyBytes))["last_synced"]
    }),
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
    Map responseJson = json.decode(utf8.decode(res.bodyBytes));
    Map mod = responseJson["data"];
    String name = mod["name"];
    String summary = mod["summary"];
    String modIconUrl =
        "https://github.com/mrquantumoff/quadrant/raw/master/assets/icons/logo.png";
    List<String> screenshots = [];
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

    for (dynamic screenshot in mod["screenshots"]) {
      screenshots.add(screenshot["thumbnailUrl"]);
    }

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
      rawMod: mod,
      modClass: modClass,
      thumbnailUrl: screenshots,
    );

    List<DropdownMenuEntry> versionItems = await getVersionsEntries();
    List<DropdownMenuEntry> modpackItems = [];

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
    dataCollectionInit();
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

Future<List<String>> getVersions({bool onInit = false}) async {
  List<String> versions = [];

  if (onInit) {
    List<String> newVersions = [];

    Uri uri = Uri.parse(
      'https://api.modrinth.com/v2/tag/game_version',
    );
    http.Response res = await http.get(
      uri,
      headers: {
        "User-Agent": await generateUserAgent(),
      },
    );
    debugPrint("Minecraft versions: ${utf8.decode(res.bodyBytes)}");
    dynamic vrs = json.decode(utf8.decode(res.bodyBytes));

    for (var v in vrs) {
      if (v["version_type"] == "release") {
        newVersions.add(v["version"].toString());
      }
    }
    versions = newVersions;
    GetStorage().write("mcVersions", newVersions);
  }

  versions = GetStorage().read("mcVersions") ?? versions;

  return versions;
}

Future<List<DropdownMenuEntry>> getVersionsEntries() async {
  List<DropdownMenuEntry> items = [];
  List<String> versions = await getVersions();
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
    Map responseJSON = json.decode(utf8.decode(res.bodyBytes));
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
      await http.post(
        Uri.parse("https://api.mrquantumoff.dev/api/v3/quadrant/usage/submit"),
        headers: {
          "User-Agent": await generateUserAgent(),
          "Authorization": const String.fromEnvironment("QUADRANT_QNT_API_KEY")
        },
        body: postBody,
      );
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

Future<void> importModpack(
  List<String> modDownloadUrls,
  String modpack,
  Function(double value) setProgressValue,
  String modConfig,
  int syncTime,
) async {
  List<DownloadedMod> downloadedMods = [];
  debugPrint("$modDownloadUrls");
  List<String> modpackFiles = [];

  Directory modpackDir =
      Directory("${getMinecraftFolder().path}/modpacks/$modpack");
  if (modpackDir.existsSync()) {
    Stream<FileSystemEntity> installedMods =
        modpackDir.list(recursive: true, followLinks: true);
    await for (FileSystemEntity item in installedMods) {
      String fileName = item.path.replaceAll("\\", "/").split("/").last;
      if (fileName.endsWith(".json") ||
          (await FileSystemEntity.isDirectory(item.path))) {
        continue;
      }
      modpackFiles.add(item.path.replaceAll("\\", "/"));
    }
  }

  debugPrint("Modpack files: $modpackFiles");
  for (var downloadUrl in modDownloadUrls) {
    String modFileName = Uri.parse(downloadUrl).pathSegments.last;
    File modDestFile =
        File("${getMinecraftFolder().path}/modpacks/$modpack/$modFileName");
    if (modpackFiles.contains(modDestFile.path.replaceAll("\\", "/"))) {
      modpackFiles.remove(modDestFile.path.replaceAll("\\", "/"));
    }
    int modIndex = modDownloadUrls.indexOf(downloadUrl);

    if (modDestFile.existsSync()) {
      setProgressValue(modIndex / modDownloadUrls.length);
      continue;
    }

    final http.Response res = await http.get(
      Uri.parse(downloadUrl),
      headers: {
        "User-Agent": await generateUserAgent(),
      },
    );

    List<int> bytes = res.bodyBytes;
    setProgressValue(modIndex / modDownloadUrls.length);
    downloadedMods.add(
      DownloadedMod(bytes: bytes, file: modDestFile),
    );
  }

  for (String item in modpackFiles) {
    File itemFile = File(item);
    if (itemFile.existsSync()) {
      await itemFile.delete();
    }
  }

  if (!await modpackDir.exists()) {
    await modpackDir.create(recursive: true);
  }
  bool success = true;
  for (DownloadedMod dlMod in downloadedMods) {
    if (dlMod.file.existsSync()) {
      await dlMod.file.delete();
    }
    await dlMod.file.create(recursive: true);
    await dlMod.file.writeAsBytes(dlMod.bytes);
  }
  if (success) {
    File modpackConfig = File("${modpackDir.path}/modConfig.json");
    debugPrint(modpackConfig.path);
    if (modpackConfig.existsSync()) {
      await modpackConfig.delete();
    }
    await modpackConfig.create();

    File syncConfig = File("${modpackDir.path}/quadrantSync.json");

    if (syncConfig.existsSync()) {
      await syncConfig.writeAsString(
        json.encode(
          {"last_synced": syncTime},
        ),
      );
    }

    await modpackConfig.writeAsString(modConfig);
    return;
  }
}

Future<void> checkAccountUpdates() async {
  const storage = FlutterSecureStorage();
  String? token = await storage.read(key: "quadrant_id_token");
  if (token == null) {
    return;
  }
  http.Response res = await http.get(
      Uri.parse("https://api.mrquantumoff.dev/api/v3/quadrant/sync/get"),
      headers: {
        "User-Agent": await generateUserAgent(),
        "Authorization": "Bearer $token"
      });
  http.Response userInfoRes = await http.get(
    Uri.parse("https://api.mrquantumoff.dev/api/v3/account/info/get"),
    headers: {
      "User-Agent": await generateUserAgent(),
      "Authorization": "Bearer $token"
    },
  );
  Map userInfo = json.decode(utf8.decode(userInfoRes.bodyBytes));

  if (userInfoRes.statusCode != 200) {
    debugPrint(
        "ACCOUNT UPDATE ERROR: ${utf8.decode(userInfoRes.bodyBytes)} (${userInfoRes.statusCode})");
    return;
  }
  if (res.statusCode != 200) {
    debugPrint(
        "ACCOUNT UPDATE ERROR : ${utf8.decode(res.bodyBytes)} (${res.statusCode})");
    return;
  }
  List<dynamic> notifications = userInfo["notifications"];
  for (dynamic notification in notifications) {
    if (notification["read"] == false) {
      Map notificationBody = json.decode(notification["message"]);
      debugPrint("$notification");
      List<dynamic> shownNotifications =
          GetStorage().read("shownNotifications") ?? [];
      if (!shownNotifications.contains(notification["notification_id"])) {
        LocalNotification localNotification = LocalNotification(
          title: notificationBody["simple_message"],
          identifier: notification["notification_id"],
          silent: false,
        );
        await localNotification.show();
        localNotification.onClick = () {
          windowManager.show();
          windowManager.focus();
        };
      }
      shownNotifications.add(notification["notification_id"]);
      GetStorage().write("shownNotifications", shownNotifications);
    }
  }

  List<SyncedModpack> syncedModpacks = [];
  List<dynamic> data = json.decode(utf8.decode(res.bodyBytes));
  for (var modpack in data) {
    syncedModpacks.add(
      SyncedModpack(
        modpackId: modpack["modpack_id"],
        name: modpack["name"],
        mods: modpack["mods"],
        mcVersion: modpack["minecraft_version"],
        modLoader: modpack["mod_loader"],
        lastSynced: modpack["last_synced"],
        reload: (value) {},
        token: token,
        username: userInfo["login"],
      ),
    );
  }

  syncedModpacks.sort(((a, b) {
    return b.lastSynced.compareTo(a.lastSynced);
  }));

  List<String> localModpacks = getModpacks();
  List<SyncedModpack> localSyncedModpacks = [];
  for (SyncedModpack modpack in syncedModpacks) {
    if (localModpacks.contains(modpack.name)) {
      localSyncedModpacks.add(modpack);
    }
  }
  for (SyncedModpack modpack in localSyncedModpacks) {
    File localSyncedModpackFile = File(
        "${getMinecraftFolder().path}/modpacks/${modpack.name}/quadrantSync.json");

    if (!localSyncedModpackFile.existsSync()) {
      continue;
    }
    try {
      int lastLocalSync =
          json.decode(localSyncedModpackFile.readAsStringSync())["last_synced"];
      int lastRemoteSync = modpack.lastSynced;
      bool cond1 = lastRemoteSync > lastLocalSync;
      bool cond2 = GetStorage().read("autoQuadrantSync") == true;
      bool cond3 = !await windowManager.isFocused();
      bool cond4 =
          GetStorage().read("isModpack_${modpack.modpackId}Updated") == false;

      if (GetStorage().read("devMode") == true) {
        debugPrint("Is AutoSync on: $cond2");
        debugPrint("Are modpacks being updated: $cond4");
        debugPrint("Is modpack synced: $cond1");
        debugPrint("Is window not focused: $cond3");
      }
      if (cond1 && cond2 && cond3 && cond4) {
        try {
          debugPrint("AutoSyncing ${modpack.name}");
          GetStorage()
              .writeInMemory("isModpack_${modpack.modpackId}Updated", true);
          LocalNotification modpackUpdateNotification = LocalNotification(
            title: modpack.name,
            identifier: modpack.modpackId,
            body: "🔃 Updating...",
            subtitle: "${modpack.modLoader} | ${modpack.mcVersion}",
            silent: false,
          );

          modpackUpdateNotification.show();
          modpackUpdateNotification.onClick = () {
            windowManager.show();
            windowManager.focus();
          };

          List<dynamic> mods = json.decode(modpack.mods);

          List<String> modDownloadUrls = [];
          for (dynamic mod in mods) {
            modDownloadUrls.add(mod["downloadUrl"]);
          }

          await importModpack(
            modDownloadUrls,
            modpack.name,
            (value) {},
            json.encode(
              {
                "name": modpack.name,
                "modLoader": modpack.modLoader,
                "version": modpack.mcVersion,
                "mods": mods
              },
            ),
            modpack.lastSynced,
          );
          LocalNotification modpackUpdateStatus = LocalNotification(
            title: modpack.name,
            identifier: modpack.modpackId,
            body: "✅ Successfully updated!",
            subtitle: "${modpack.modLoader} | ${modpack.mcVersion}",
            silent: false,
          );

          modpackUpdateStatus.show();
          modpackUpdateStatus.onClick = () {
            windowManager.show();
            windowManager.focus();
          };
          GetStorage()
              .writeInMemory("isModpack_${modpack.modpackId}Updated", false);
        } catch (e) {
          debugPrint("Error while autosyncing: $e");
          LocalNotification modpackUpdateStatus = LocalNotification(
            title: modpack.name,
            identifier: modpack.modpackId,
            body: "❌ Failed to update | $e",
            subtitle: "${modpack.modLoader} | ${modpack.mcVersion}",
            silent: false,
          );

          modpackUpdateStatus.show();
          modpackUpdateStatus.onClick = () {
            windowManager.show();
            windowManager.focus();
          };
        }
        GetStorage()
            .writeInMemory("isModpack_${modpack.modpackId}Updated", false);
      }
      GetStorage()
          .writeInMemory("isModpack_${modpack.modpackId}Updated", false);
    } catch (e) {
      debugPrint("$e");
    }
  }
}

void initConfig() {
  if (GetStorage().read("clipIcons") == null) {
    GetStorage().writeInMemory("clipIcons", true);
  }
  if (GetStorage().read("lastRSSfetched") == null) {
    GetStorage().writeInMemory("lastRSSfetched",
        DateTime.now().subtract(const Duration(days: 14)).toIso8601String());
  }
  if (GetStorage().read("curseforge") == null) {
    GetStorage().writeInMemory("curseForge", true);
  }
  if (GetStorage().read("modrinth") == null) {
    GetStorage().writeInMemory("modrinth", true);
  }
  if (GetStorage().read("devMode") == null) {
    GetStorage().writeInMemory("devMode", false);
  }
  if (GetStorage().read("rssFeeds") == null) {
    GetStorage().writeInMemory("rssFeeds", true);
  }
  if (GetStorage().read("silentNews") == null) {
    GetStorage().writeInMemory("silentNews", false);
  }
  if (GetStorage().read("autoQuadrantSync") == null) {
    GetStorage().writeInMemory("autoQuadrantSync", true);
  }
  if (GetStorage().read("showUnupgradeableMods") == null) {
    GetStorage().writeInMemory("showUnupgradeableMods", false);
  }
  if (GetStorage().read("lastPage") == null) {
    GetStorage().writeInMemory("lastPage", 0);
  }
  if (GetStorage().read("extendedNavigation") == null) {
    GetStorage().writeInMemory("extendedNavigation", false);
  }
  if (GetStorage().read("experimentalFeatures") == null) {
    GetStorage().writeInMemory("experimentalFeatures", false);
  }
  if (GetStorage().read("dontShowUserDataRecommendation") == null) {
    GetStorage().writeInMemory("dontShowUserDataRecommendation", false);
  }
  if (GetStorage().read("cacheKeepAlive") == null ||
      GetStorage().read("cacheKeepAlive").runtimeType != int) {
    GetStorage().writeInMemory("cacheKeepAlive", 30);
  }
}

class QuadrantCacheManager {
  static const key = 'quadrantCache';
  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: Duration(days: GetStorage().read("cacheKeepAlive")),
      maxNrOfCacheObjects: 768,
      repo: JsonCacheInfoRepository(databaseName: key),
      fileSystem: IOFileSystem(key),
      fileService: HttpFileService(),
    ),
  );
}
