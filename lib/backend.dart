import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';

Directory getMinecraftFolder() {
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

List<String> getModpacks() {
  getMinecraftFolder().createSync(recursive: true);
  Directory modpackFolder = Directory("${getMinecraftFolder().path}/modpacks");
  modpackFolder.createSync(recursive: true);
  List<String> modpacks = [];
  for (var entity
      in modpackFolder.listSync(recursive: false, followLinks: false)) {
    if (entity.statSync().type == FileSystemEntityType.directory &&
        !(entity.path.endsWith("modpacks/free") ||
            entity.path.endsWith("modpacks\\free"))) {
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
  if (modsFolder.existsSync()) {
    try {
      modsFolder.deleteSync(recursive: true);
    } catch (e) {
      debugPrint("Error ${e.toString()}");
      return false;
    }
  }
  try {
    Link(modsFolder.path).createSync(modpackFolder.path, recursive: true);
  } catch (e) {
    debugPrint("Error ${e.toString()}");
    return false;
  }
  return true;
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

Future<void> installModpack(
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
