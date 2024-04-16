import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/other/restart_app.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  late bool buttonsEnabled;
  late TextEditingController emailController;
  late TextEditingController passwordController;
  final storage = const FlutterSecureStorage();

  @override
  void initState() {
    buttonsEnabled = true;
    emailController = TextEditingController();
    passwordController = TextEditingController();
    super.initState();
  }

  void setButtonsEnabled(bool enabled) {
    setState(() {
      buttonsEnabled = enabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppLocalizations.of(context)!.signIn,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                // fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              AppLocalizations.of(context)!.emailAndPassword,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              SizedBox(
                width: 640,
                child: TextField(
                  enabled: buttonsEnabled,
                  controller: emailController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: AppLocalizations.of(context)!.email,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 640,
                child: TextField(
                  enabled: buttonsEnabled,
                  obscureText: true,
                  controller: passwordController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: AppLocalizations.of(context)!.password,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: buttonsEnabled
              ? () async {
                  setButtonsEnabled(false);
                  http.Response response = await http.post(
                    Uri.parse(
                        "https://api.mrquantumoff.dev/api/v2/submit/account/login"),
                    headers: {
                      'User-Agent': await generateUserAgent(),
                    },
                    body: jsonEncode(
                      {
                        "email": emailController.text,
                        "password": passwordController.text,
                        "scope": "quadrant_sync,user_data",
                        "token_duration": 7776000, // 90 Days
                        "device":
                            "Quadrant on ${(await getMachineIdAndOs()).os}"
                      },
                    ),
                  );
                  if (response.statusCode != 202) {
                    setButtonsEnabled(true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          response.body,
                        ),
                      ),
                    );
                    return;
                  }
                  String token = response.body;
                  await storage.write(key: "quadrant_id_token", value: token);
                  RestartWidget.restartApp(context);
                }
              : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          AppLocalizations.of(context)!.buttonsAreDisabled),
                    ),
                  );
                },
          child: Text(AppLocalizations.of(context)!.signIn),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: buttonsEnabled
              ? () {}
              : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          AppLocalizations.of(context)!.buttonsAreDisabled),
                    ),
                  );
                },
          child: Text(AppLocalizations.of(context)!.dontHaveAccount),
        )
      ],
    );
  }
}
