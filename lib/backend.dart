import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';

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
    var request = Request('GET', uri);
    String name = modpackName;
    var response = await Client().send(request);
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
  Uri githubGet = Uri.parse(
      "https://api.github.com/repos/mrquantumoff/mcmodpackmanager_reborn/releases");

  Map<String, String> headers = {
    "Authentication":
        "Bearer ${const String.fromEnvironment("GITHUB_RELEASE_KEY")}"
  };
  Response latestReleaseResponse = await get(githubGet, headers: headers);
  List<dynamic> response = json.decode(latestReleaseResponse.body);
  Map latestRelease = response[0];
  PackageInfo packageInfo = await PackageInfo.fromPlatform();

  return {
    "latestRelease": latestRelease["tag_name"],
    "currentRelease": packageInfo.version,
    "url": latestRelease["html_url"]
  };
}
