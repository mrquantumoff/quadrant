import 'dart:convert';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:quadrant/pages/web/generate_user_agent.dart';

class SendFeedpackPage extends StatefulWidget {
  const SendFeedpackPage({super.key});

  @override
  State<SendFeedpackPage> createState() => _SendFeedpackPageState();
}

class _SendFeedpackPageState extends State<SendFeedpackPage> {
  TextEditingController emailController = TextEditingController();
  TextEditingController messageController = TextEditingController();
  TextEditingController titleController = TextEditingController();
  final storage = const FlutterSecureStorage();

  Future<Widget> getFeedbackPage(BuildContext context) async {
    String? accountToken = await storage.read(key: "quadrant_id_token");

    if (accountToken != null) {
      if (JwtDecoder.isExpired(accountToken)) {
        await storage.delete(key: "quadrant_id_token");
      }

      http.Response res = await http.get(
        Uri.parse("https://api.mrquantumoff.dev/api/v2/get/account"),
        headers: {
          "User-Agent": await generateUserAgent(),
          "Authorization": "Bearer $accountToken",
        },
      );

      if (res.statusCode == 400) {
        await storage.delete(key: "quadrant_id_token");
      } else if (res.statusCode == 200) {
        emailController.text = json.decode(res.body)["email"];
      }
    }
    return ListView(
      children: [
        const SizedBox(
          height: 12,
        ),
        Center(
          child: SizedBox(
            width: 960,
            child: TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: AppLocalizations.of(context)!.email,
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            child: SizedBox(
              width: 960,
              child: TextField(
                controller: titleController,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: AppLocalizations.of(context)!.subject,
                ),
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            child: SizedBox(
              width: 960,
              child: TextField(
                controller: messageController,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                minLines: 16,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: AppLocalizations.of(context)!.message,
                ),
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 48, bottom: 48),
            child: FilledButton.icon(
              onPressed: () async {
                if (emailController.text.trim().isEmpty ||
                    titleController.text.trim().isEmpty ||
                    messageController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.of(context)!.invalidData),
                    ),
                  );
                  return;
                }
                Map requestBody = {
                  "email": emailController.text,
                  "title": titleController.text,
                  "message": messageController.text,
                };
                http.Response res = await http.post(
                  Uri.parse(
                      "https://api.mrquantumoff.dev/api/v2/submit/quadrant_feedback"),
                  headers: {
                    "User-Agent": await generateUserAgent(),
                    "Authorization":
                        const String.fromEnvironment("QUADRANT_QNT_API_KEY"),
                  },
                  body: json.encode(requestBody),
                );

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("${res.body} (${res.statusCode})"),
                  ),
                );
                if (res.statusCode == 202) {
                  Get.back();
                }
                return;
              },
              label: Text(AppLocalizations.of(context)!.sendFeedback),
              icon: const Icon(Icons.send),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.sendFeedback),
      ),
      body: FutureBuilder(
        future: getFeedbackPage(context),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          } else if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return snapshot.data!;
        },
      ),
    );
  }
}
