import 'dart:convert';
import 'dart:io';
import 'package:dart_ipify/dart_ipify.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';
import 'package:quadrant/pages/web/mod/install_mod_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:quadrant/pages/web/mod/mod.dart';

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
      "https://api.mrquantumoff.dev/api/v1/getLatestMinecraftModpackManagerRelease");

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
      "url":
          "https://api.mrquantumoff.dev/api/v1/getLatestMinecraftModpackManagerRelease"
    };
  }
  http.Response latestReleaseResponse =
      await http.get(apiLink, headers: headers);
  Map response = json.decode(latestReleaseResponse.body);
  dynamic latestRelease = response["release"].toString();
  PackageInfo packageInfo = await PackageInfo.fromPlatform();

  return {
    "latestRelease": latestRelease,
    "currentRelease": packageInfo.version,
    "url":
        "https://github.com/mrquantumoff/mcmodpackmanager_reborn/releases/tag/$latestRelease"
  };
}

Future<Mod> getMod(String modId, ModSource source,
    Function(bool val) setAreParentButtonsActive,
    {bool downloadAble = true}) async {
  if (source == ModSource.curseForge) {
    final String apiKey =
        const String.fromEnvironment("ETERNAL_API_KEY").replaceAll("\"", "");
    http.Response res = await http.get(
      Uri.parse("https://api.curseforge.com/v1/mods/$modId"),
      headers: {
        "User-Agent": await generateUserAgent(),
        "X-API-Key": apiKey,
      },
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

    return Mod(
      name: resJSON["name"],
      description: resJSON["summary"],
      downloadCount: resJSON["downloadCount"],
      modIconUrl: resJSON["logo"]["thumbnailUrl"],
      id: resJSON["id"].toString(),
      setAreParentButtonsActive: setAreParentButtonsActive,
      slug: resJSON["slug"],
      modClass: modClass,
      source: ModSource.curseForge,
      downloadAble: downloadAble,
    );
  } else {
    http.Response res = await http.get(
      Uri.parse("https://api.modrinth.com/v2/project/$modId"),
      headers: {
        "User-Agent": await generateUserAgent(),
      },
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
      downloadAble: downloadAble,
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
        "https://github.com/mrquantumoff/mcmodpackmanager_reborn/raw/master/assets/icons/logo.png";
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
    GetStorage().write("collectUserData", false);
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
      Uri.parse("https://api.iplocation.net/?ip=${await Ipify.ipv4()}"),
    );
    debugPrint("IP: ${await Ipify.ipv4()}");
    Map responseJSON = json.decode(res.body);
    final String country = responseJSON["country_name"] ?? "Unknown";
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
      //https://api.mrquantumoff.dev/api/v1/submitMinecraftModpackManagerUsageInfo
      var result = await http.post(
        Uri.parse(
            "https://api.mrquantumoff.dev/api/v1/submitMinecraftModpackManagerUsageInfo"),
        headers: {"User-Agent": await generateUserAgent()},
        body: postBody,
      );
      if (result.body.contains("Updated") || result.body.contains("Created")) {
        GetStorage().write("lastDataSent", DateTime.now().toUtc().toString());
      }
      debugPrint(result.body);
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

void deleteUsageInfo() async {
  MachineIdAndOS info = await getMachineIdAndOs();

  await http.delete(
    Uri.parse(
        "https://api.mrquantumoff.dev/api/v1/deleteUsageInfo?hardware_id=${info.machineId}"),
    headers: {
      "User-Agent": await generateUserAgent(),
    },
  );
}
