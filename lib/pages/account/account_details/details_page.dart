import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:http/http.dart' as http;
import 'package:quadrant/other/restart_app.dart';
import 'package:quadrant/pages/account/account_details/edit_details.dart';
import 'package:quadrant/pages/account/account_details/notifications.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';

class AccountDetails extends StatefulWidget {
  const AccountDetails({super.key});
  @override
  State<AccountDetails> createState() => _AccountDetailsState();
}

class _AccountDetailsState extends State<AccountDetails> {
  final storage = const FlutterSecureStorage();

  String reload = "account";

  Future<Widget> accountDetails(BuildContext context, String reload) async {
    // Verify account details
    String accountToken = (await storage.read(key: "quadrant_id_token"))!;

    if (JwtDecoder.isExpired(accountToken)) {
      await storage.delete(key: "quadrant_id_token");
    }

    http.Response res = await http.get(
      Uri.parse("https://api.mrquantumoff.dev/api/v3/account/info/get"),
      headers: {
        "User-Agent": await generateUserAgent(),
        "Authorization": "Bearer $accountToken",
      },
    );

    if (res.statusCode != 200) {
      // If the token is not valid, log out of the account and ask the user to login again.
      debugPrint("${res.body} (${res.statusCode})");
      await storage.delete(key: "quadrant_id_token");
      RestartWidget.restartApp(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            AppLocalizations.of(context)!.unknown,
          ),
          Text(res.body),
        ],
      );
    }

    // Parse the user data
    Map<String, dynamic> user = json.decode(res.body);
    String name = user["name"];
    String username = user["login"];
    String email = user["email"];
    int syncLimit = user["quadrant_sync_limit"];
    int shareLimit = user["quadrant_share_limit"];
    List<dynamic> notifications = user["notifications"];
    List<dynamic> unreadNotifications = [];

    for (var not in notifications) {
      if (not["read"] == false) {
        unreadNotifications.add(not);
      }
    }
    // Display the user data
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          AppLocalizations.of(context)!.hello(name),
          style: const TextStyle(fontSize: 24),
        ),
        Text(
          AppLocalizations.of(context)!
              .unreadNotifications(unreadNotifications.length),
          style: const TextStyle(fontSize: 18),
        ),
        Container(
          margin: const EdgeInsets.only(top: 12),
          child: FilledButton.icon(
            onPressed: () async {
              Get.to(
                () => Notifications(token: accountToken, setReload: setReload),
              );
            },
            label: Text(AppLocalizations.of(context)!.read),
            icon: const Icon(Icons.notifications),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Card(
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Text(
                "${AppLocalizations.of(context)!.username}: $username",
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Card(
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Text(
                "${AppLocalizations.of(context)!.email}: $email",
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Card(
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Text(
                "${AppLocalizations.of(context)!.syncLimit}: $syncLimit",
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Card(
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Text(
                "${AppLocalizations.of(context)!.shareLimit}: $shareLimit",
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
        ),
        Center(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton(
                onPressed: () async {
                  await storage.delete(key: "quadrant_id_token");
                  RestartWidget.restartApp(context);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(AppLocalizations.of(context)!.signout),
                    const SizedBox(
                      width: 4,
                    ),
                    const Icon(
                      Icons.logout,
                      size: 16,
                    ),
                  ],
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              FilledButton(
                onPressed: () async {
                  Get.to(
                    () => const EditDetails(),
                    transition: Transition.fadeIn,
                  );
                },
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(AppLocalizations.of(context)!.edit),
                    const SizedBox(
                      width: 4,
                    ),
                    const Icon(
                      Icons.edit,
                      size: 16,
                    ),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  void setReload(String newReload) {
    setState(() {
      reload = newReload;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: accountDetails(context, reload),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Center(child: snapshot.data!);
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              children: [
                const Icon(Icons.error),
                Text("${snapshot.error}"),
              ],
            ),
          );
        }
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
    );
  }
}
