import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:http/http.dart' as http;
import 'package:quadrant/other/restart_app.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';

class AccountDetails extends StatefulWidget {
  const AccountDetails({super.key, required this.accountToken});

  final String accountToken;

  @override
  State<AccountDetails> createState() => _AccountDetailsState();
}

class _AccountDetailsState extends State<AccountDetails> {
  final storage = const FlutterSecureStorage();

  Future<Widget> accountDetails(BuildContext context) async {
    if (JwtDecoder.isExpired(widget.accountToken)) {
      await storage.delete(key: "quadrant_id_token");
    }

    http.Response res = await http.get(
      Uri.parse("https://api.mrquantumoff.dev/api/v2/get/account"),
      headers: {
        "User-Agent": await generateUserAgent(),
        "Authorization": "Bearer ${widget.accountToken}",
      },
    );

    if (res.statusCode == 403) {
      await storage.delete(key: "quadrant_id_token");
      RestartWidget.restartApp(context);
    } else if (res.statusCode != 200) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.unknown,
        ),
      );
    }
    Map<String, dynamic> user = json.decode(res.body);

    String name = user["name"];
    String username = user["login"];
    String email = user["email"];
    int syncLimit = user["quadrant_sync_limit"];
    int shareLimit = user["quadrant_share_limit"];

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          AppLocalizations.of(context)!.hello(name),
          style: const TextStyle(fontSize: 24),
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
              )
            ],
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: accountDetails(context),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Center(child: snapshot.data!);
        }
        if (snapshot.hasError) {
          return const Center(
            child: Icon(Icons.error),
          );
        }
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
    );
  }
}
