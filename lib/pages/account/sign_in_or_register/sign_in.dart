import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get_storage_qnt/get_storage.dart';
import 'package:quadrant/other/backend.dart';
import 'package:quadrant/pages/account/sign_in_or_register/register/email.dart';
import 'package:url_launcher/url_launcher.dart';

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
  Timer? restartApp;
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
    return Center(
      child: Column(
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
                  // color: Colors.white,
                  fontSize: 30,
                  // fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                AppLocalizations.of(context)!.emailAndPassword,
                style: const TextStyle(
                  // color: Colors.white,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: buttonsEnabled
                ? () async {
                    String state = getRandomString(16);
                    GetStorage().write("oauth2_state", state);
                    await launchUrl(
                      Uri.parse(
                          "https://mrquantumoff.dev/account/oauth2/authorize?client_id=dee6f38c-e6c2-4cf1-9973-dfd3c793f979&redirect_uri=quadrant://login&scope=user_data,quadrant_sync,notifications&duration=7776000&response_type=code&state=$state"),
                    );
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
          FilledButton.tonal(
            onPressed: buttonsEnabled
                ? () async {
                    Get.to(() => const RegisterStep1(),
                        transition: Transition.rightToLeft);
                  }
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            AppLocalizations.of(context)!.buttonsAreDisabled),
                      ),
                    );
                  },
            child: Text(
              AppLocalizations.of(context)!.dontHaveAccount,
            ),
          ),
          const SizedBox(
            height: 12,
          ),
          TextButton.icon(
            onPressed: () async {
              await launchUrl(
                Uri.parse(
                    "https://github.com/mrquantumoff/quadrant/blob/master/QUADRANT-ID-TOS.md"),
              );
            },
            label: Text(AppLocalizations.of(context)!.acceptQuadrantIDTOS),
            icon: const Icon(Icons.open_in_browser),
          ),
        ],
      ),
    );
  }
}
