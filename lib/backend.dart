import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:mcmodpackmanager_reborn/modpack_installer/web/generate_user_agent.dart';
import 'package:mcmodpackmanager_reborn/modpack_installer/web/install_mod_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';

import 'modpack_installer/web/mod.dart';

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

void installModpack(
    String url,
    String modpackName,
    Function(double progress) setProgressValue,
    Function(bool newValue) setAreButtonsEnabled,
    String overwriteQ,
    String overwriteQText,
    Function displayErrorSnackBar,
    Function displaySuccessSnackbar,
    Function(double speed) setDownloadSpeed) async {
  setAreButtonsEnabled(false);
  final sep = Platform.isWindows ? "\\" : "/";
  try {
    Uri uri = Uri.parse(url);
    var request = http.Request('GET', uri);
    String name = modpackName;
    var response = await http.Client().send(request);
    List<int> chunks = [];
    File saveFile =
        File("${(await getTemporaryDirectory()).path}${sep}modpack-$name.zip");
    debugPrint(saveFile.path);
    if (await saveFile.exists()) {
      await saveFile.delete();
    }
    await saveFile.create(recursive: true);
    int contentLength = response.contentLength ?? 1;
    DateTime startContentDownloadTime = DateTime.now();
    response.stream.listen((List<int> newBytes) {
      chunks.addAll(newBytes);
      final downloadedLength = chunks.length;
      DateTime contentDownloadTime = DateTime.now();
      try {
        double dlSpeed = ((chunks.length /
                contentDownloadTime
                    .difference(startContentDownloadTime)
                    .inSeconds) /
            1000000 *
            0.875);
        String dlSpeedString =
            "${dlSpeed.toString().split(".").first}.${dlSpeed.toString().split(".").last.characters.elementAt(0)}${dlSpeed.toString().split(".").last.characters.elementAt(1)}";
        setDownloadSpeed(double.parse(dlSpeedString));
      } catch (e) {
        debugPrint("Error while calculating download speed");
      }
      setProgressValue(downloadedLength.toDouble() / contentLength);
    }).onDone(() async {
      setProgressValue(1);
      await saveFile.writeAsBytes(chunks, flush: true);
      final modpackDir = "${getMinecraftFolder().path}${sep}modpacks$sep$name";
      if (await Directory(modpackDir).exists()) {
        bool shouldReturn = false;

        final clickedButton = await FlutterPlatformAlert.showAlert(
          windowTitle: overwriteQ,
          text: overwriteQText,
          alertStyle: AlertButtonStyle.yesNo,
          iconStyle: IconStyle.warning,
        );
        shouldReturn = clickedButton == AlertButton.noButton;
        if (shouldReturn) {
          await saveFile.delete(recursive: true);
          setAreButtonsEnabled(true);
          displayErrorSnackBar();
          return;
        }
      }
      await extractFileToDisk(
          saveFile.path, "${getMinecraftFolder().path}${sep}modpacks$sep$name",
          asyncWrite: false);
      setAreButtonsEnabled(true);
      displaySuccessSnackbar();
    });
  } catch (e) {
    setAreButtonsEnabled(true);
    displayErrorSnackBar();
    debugPrint(e.toString());
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
      "https://mrquantumoff.dev/api/projects/getMinecraftModpackManagerLatestRelease");

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
          "https://mrquantumoff.dev/api/projects/getMinecraftModpackManagerLatestRelease"
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
    );
  } catch (e) {
    fail();
  }
}
