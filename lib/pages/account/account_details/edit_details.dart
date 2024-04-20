import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:http/http.dart' as http;
import 'package:quadrant/other/restart_app.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';

class EditDetails extends StatefulWidget {
  const EditDetails({super.key, required this.accountToken});

  final String accountToken;

  @override
  State<EditDetails> createState() => _EditDetailsState();
}

class _EditDetailsState extends State<EditDetails> {
  final storage = const FlutterSecureStorage();

  late TextEditingController nameController;
  late TextEditingController oldPasswordController;
  late TextEditingController newPasswordController;
  late TextEditingController confirmNewPasswordController;
  late TextEditingController usernameController;
  late bool resetSessions;
  late bool areButtonsEnabled;

  @override
  void initState() {
    super.initState();
    areButtonsEnabled = true;
    nameController = TextEditingController();
    oldPasswordController = TextEditingController();
    newPasswordController = TextEditingController();
    confirmNewPasswordController = TextEditingController();
    usernameController = TextEditingController();
    resetSessions = false;
  }

  void setResetSessions(bool value) async {
    if (!areButtonsEnabled) return;
    setState(() {
      resetSessions = value;
    });
  }

  void setAreButtonsEnabled(bool value) async {
    setState(() {
      areButtonsEnabled = value;
    });
  }

  Future<Widget> editAccount(BuildContext context) async {
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
      debugPrint(res.statusCode as String?);

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
    Map<String, dynamic> user = json.decode(res.body);

    String name = user["name"];
    String username = user["login"];
    String email = user["email"];
    String sid = json.decode(
      String.fromCharCodes(
        base64.decode(
          widget.accountToken.split(".")[1],
        ),
      ),
    )["uid"];
    nameController.text = name;
    usernameController.text = username;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 640,
          child: TextField(
            enabled: areButtonsEnabled,
            // obscureText: true,
            controller: nameController,
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
            enabled: areButtonsEnabled,
            // obscureText: true,
            controller: usernameController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: AppLocalizations.of(context)!.username,
            ),
          ),
        ),
        const SizedBox(
          height: 12,
        ),
        SizedBox(
          width: 640,
          child: TextField(
            enabled: areButtonsEnabled,
            obscureText: true,
            controller: newPasswordController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: AppLocalizations.of(context)!.newPassword,
            ),
          ),
        ),
        const SizedBox(
          height: 12,
        ),
        SizedBox(
          width: 640,
          child: TextField(
            enabled: areButtonsEnabled,
            obscureText: true,
            controller: confirmNewPasswordController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: AppLocalizations.of(context)!.newPassword,
            ),
          ),
        ),
        const SizedBox(
          height: 12,
        ),
        SizedBox(
          width: 640,
          child: TextField(
            enabled: areButtonsEnabled,
            obscureText: true,
            controller: oldPasswordController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: AppLocalizations.of(context)!.password,
            ),
          ),
        ),
        const SizedBox(
          height: 20,
        ),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Switch(value: resetSessions, onChanged: setResetSessions),
              const SizedBox(
                width: 8,
              ),
              Text(AppLocalizations.of(context)!.resetSessions),
            ],
          ),
        ),
        Center(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton(
                onPressed: areButtonsEnabled
                    ? () async {
                        // Show a warning
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title:
                                Text(AppLocalizations.of(context)!.areYouSure),
                            actions: [
                              IconButton.filled(
                                onPressed: () async {
                                  setAreButtonsEnabled(false);
                                  Map requestBody = {
                                    "email": email,
                                    "password": oldPasswordController.text,
                                  };
                                  http.Response res = await http.delete(
                                    Uri.parse(
                                        "https://api.mrquantumoff.dev/api/v2/delete/id/account"),
                                    headers: {
                                      "User-Agent": await generateUserAgent(),
                                    },
                                    body: json.encode(requestBody),
                                  );
                                  if (res.statusCode != 202) {
                                    debugPrint("${res.statusCode}");
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            "${AppLocalizations.of(context)!.unknown}: ${res.body}"),
                                      ),
                                    );
                                    setAreButtonsEnabled(true);
                                    return;
                                  }
                                  setAreButtonsEnabled(true);
                                  await storage.delete(
                                      key: "quadrant_id_token");
                                  RestartWidget.restartApp(context);
                                },
                                icon: const Icon(Icons.check),
                              ),
                              IconButton.filled(
                                onPressed: () {
                                  Get.back();
                                },
                                icon: const Icon(Icons.close),
                              )
                            ],
                          ),
                        );
                      }
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppLocalizations.of(context)!.buttonsAreDisabled,
                            ),
                          ),
                        );
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(AppLocalizations.of(context)!.delete),
                    const SizedBox(
                      width: 4,
                    ),
                    const Icon(
                      Icons.delete,
                      size: 16,
                    ),
                  ],
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              FilledButton(
                onPressed: areButtonsEnabled
                    ? () async {
                        setAreButtonsEnabled(false);
                        Map requestBody = {
                          "id": sid,
                          "password": oldPasswordController.text,
                          "reset_sessions": resetSessions
                        };
                        if (newPasswordController.text != "" &&
                            newPasswordController.text ==
                                confirmNewPasswordController.text) {
                          requestBody.addAll({
                            "new_password": newPasswordController.text,
                          });
                        } else if (newPasswordController.text != "" &&
                            newPasswordController.text !=
                                confirmNewPasswordController.text) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppLocalizations.of(context)!
                                    .passwordsDontMatch,
                              ),
                            ),
                          );
                          setAreButtonsEnabled(true);
                          return;
                        }

                        if (name != nameController.text) {
                          requestBody.addAll({
                            "name": nameController.text,
                          });
                        }
                        if (username != usernameController.text) {
                          requestBody.addAll({
                            "login": usernameController.text,
                          });
                        }

                        http.Response res = await http.patch(
                          Uri.parse(
                              "https://api.mrquantumoff.dev/api/v2/update/id/account"),
                          headers: {
                            "User-Agent": await generateUserAgent(),
                          },
                          body: json.encode(requestBody),
                        );
                        debugPrint(json.encode(requestBody));
                        if (res.statusCode != 202) {
                          debugPrint("${res.statusCode}");
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  "${AppLocalizations.of(context)!.unknown}: ${res.body}"),
                            ),
                          );
                          return;
                        }
                        if (resetSessions) {
                          await storage.delete(key: "quadrant_id_token");
                          Get.back();
                        }
                        Get.back();
                        RestartWidget.restartApp(context);
                      }
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(AppLocalizations.of(context)!
                                .buttonsAreDisabled),
                          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder(
        future: editAccount(context),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Center(child: snapshot.data!);
          }
          if (snapshot.hasError) {
            debugPrint("${snapshot.error}");

            return const Center(
              child: Icon(Icons.error),
            );
          }
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      ),
    );
  }
}
