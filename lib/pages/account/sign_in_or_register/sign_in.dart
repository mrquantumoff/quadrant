import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
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
                    await launchUrl(
                      Uri.parse(
                          "https://mrquantumoff.dev/account/oauth2/authorize?client_id=dee6f38c-e6c2-4cf1-9973-dfd3c793f979&redirect_to=quadrant://login&scope=user_data,quadrant_sync&duration=77600"),
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
        ],
      ),
    );
  }
}
