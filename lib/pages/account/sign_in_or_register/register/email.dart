import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:quadrant/pages/account/sign_in_or_register/register/register.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';

class RegisterStep1 extends StatefulWidget {
  const RegisterStep1({super.key});

  @override
  State<RegisterStep1> createState() => _RegisterStep1State();
}

class _RegisterStep1State extends State<RegisterStep1> {
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
    return Scaffold(
      appBar: AppBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                AppLocalizations.of(context)!.register,
                style: const TextStyle(
                  // color: Colors.white,
                  fontSize: 30,
                  // fontWeight: FontWeight.w800,
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
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: AppLocalizations.of(context)!.email,
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
                          "https://api.mrquantumoff.dev/api/v2/submit/id/request_registration"),
                      headers: {
                        'User-Agent': await generateUserAgent(),
                        'Authorization':
                            const String.fromEnvironment("QUADRANT_QNT_API_KEY")
                      },
                      body: jsonEncode(
                        {
                          "email": emailController.text,
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

                    setButtonsEnabled(true);

                    Get.to(
                        () => RegisterStep2(
                              email: emailController.text,
                            ),
                        transition: Transition.fadeIn);
                  }
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            AppLocalizations.of(context)!.buttonsAreDisabled),
                      ),
                    );
                  },
            child: Text(AppLocalizations.of(context)!.register),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: buttonsEnabled
                ? () {
                    Get.back();
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
          )
        ],
      ),
    );
  }
}
