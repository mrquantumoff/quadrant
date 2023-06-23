import 'package:package_info_plus/package_info_plus.dart';

Future<String> generateUserAgent() async {
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  return "mrquantumoff/mcmodpackmanager_reborn/v${packageInfo.version} (mrquantumoff.dev)";
}
