import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:quadrant/other/restart_app.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';

class RegisterStep2 extends StatefulWidget {
  const RegisterStep2({super.key, required this.email});

  final String email;

  @override
  State<RegisterStep2> createState() => _RegisterStep2State();
}

class _RegisterStep2State extends State<RegisterStep2> {
  late bool buttonsEnabled;
  late TextEditingController emailController;
  late TextEditingController passwordController;
  late TextEditingController confirmPasswordController;
  late TextEditingController verificationCodeController;
  late TextEditingController usernameController;
  late TextEditingController nameController;
  final storage = const FlutterSecureStorage();

  @override
  void initState() {
    buttonsEnabled = true;
    emailController = TextEditingController();
    passwordController = TextEditingController();
    confirmPasswordController = TextEditingController();
    verificationCodeController = TextEditingController();
    usernameController = TextEditingController();
    nameController = TextEditingController();
    emailController.text = widget.email;
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
                    enabled: false,
                    controller: emailController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: AppLocalizations.of(context)!.email,
                    ),
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                SizedBox(
                  width: 640,
                  child: TextField(
                    enabled: buttonsEnabled,
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: AppLocalizations.of(context)!.password,
                    ),
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                SizedBox(
                  width: 640,
                  child: TextField(
                    enabled: buttonsEnabled,
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: AppLocalizations.of(context)!.password,
                    ),
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                SizedBox(
                  width: 640,
                  child: TextField(
                    enabled: buttonsEnabled,
                    controller: verificationCodeController,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: AppLocalizations.of(context)!.verificationCode,
                    ),
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                SizedBox(
                  width: 640,
                  child: TextField(
                    enabled: buttonsEnabled,
                    controller: nameController,
                    keyboardType: TextInputType.name,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: AppLocalizations.of(context)!.name,
                    ),
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                SizedBox(
                  width: 640,
                  child: TextField(
                    enabled: buttonsEnabled,
                    controller: usernameController,
                    // keyboardType: TextInputType.number,
                    // maxLength: 8,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: AppLocalizations.of(context)!.username,
                    ),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: buttonsEnabled
                ? () async {
                    setButtonsEnabled(false);

                    if (confirmPasswordController.text !=
                        passwordController.text) {
                      setButtonsEnabled(true);
                      ScaffoldMessenger.of(context).setState(() {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppLocalizations.of(context)!.passwordsDontMatch,
                            ),
                          ),
                        );
                      });
                      return;
                    }

                    if (passwordController.text.isEmpty ||
                        confirmPasswordController.text.isEmpty ||
                        verificationCodeController.text.isEmpty ||
                        usernameController.text.isEmpty ||
                        nameController.text.isEmpty) {
                      setButtonsEnabled(true);
                      return;
                    }

                    int? code = int.tryParse(verificationCodeController.text);

                    if (code == null) {
                      setButtonsEnabled(true);
                      return;
                    }
                    http.Response response = await http.post(
                      Uri.parse(
                          "https://api.mrquantumoff.dev/api/v2/submit/id/register"),
                      headers: {
                        'User-Agent': await generateUserAgent(),
                      },
                      body: jsonEncode(
                        {
                          "email": emailController.text.trim(),
                          "verification_code": code,
                          "login": usernameController.text.trim(),
                          "password": passwordController.text.trim(),
                          "name": nameController.text.trim(),
                        },
                      ),
                    );
                    if (response.statusCode != 201) {
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
                    Get.back();
                    Get.back();
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
            child: Text(AppLocalizations.of(context)!.register),
          ),
        ],
      ),
    );
  }
}
