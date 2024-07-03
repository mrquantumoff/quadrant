import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:quadrant/pages/web/generate_user_agent.dart';

class Notification extends StatefulWidget {
  // ignore: prefer_const_constructors_in_immutables
  Notification({
    super.key,
    required this.token,
    required this.notificationId,
    required this.createdAt,
    required this.message,
    required this.read,
    required this.setReload,
  });

  final String token;
  final String notificationId;
  final String message;
  final int createdAt;
  final bool read;
  final Function(String) setReload;

  @override
  State<Notification> createState() => _NotificationState();
}

class _NotificationState extends State<Notification> {
  bool read = false;

  @override
  void initState() {
    super.initState();
    read = widget.read;
  }

  @override
  Widget build(BuildContext context) {
    Map notification = json.decode(widget.message);

    List<Widget> children = [];

    if (notification["notification_type"] == "login") {
      children = [
        Text(
          notification["simple_message"],
          style: const TextStyle(fontSize: 24),
        )
      ];
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: children +
                (read
                    ? []
                    : [
                        const SizedBox(
                          height: 12,
                        ),
                        FilledButton.icon(
                          onPressed: () async {
                            http.Response res = await http.post(
                              Uri.parse(
                                  "https://api.mrquantumoff.dev/api/v3/account/notifications/read"),
                              headers: {
                                "User-Agent": await generateUserAgent(),
                                "Authorization": "Bearer ${widget.token}",
                                "Content-Type": "application/json",
                              },
                              body: json.encode({
                                "notification_id": widget.notificationId,
                              }),
                            );
                            debugPrint(res.body);
                            if (res.statusCode == 200) {
                              setState(() {
                                read = true;
                              });
                              widget.setReload(res.body);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(res.body),
                                ),
                              );
                            }
                          },
                          label: Text(AppLocalizations.of(context)!.read),
                          icon: const Icon(Icons.mark_email_read),
                        )
                      ]),
          ),
        ),
      ),
    );
  }
}

// ignore: must_be_immutable
class Notifications extends StatefulWidget {
  Notifications({super.key, required this.token, required this.setReload});

  String token;
  Function(String) setReload;

  @override
  State<Notifications> createState() => _NotificationsState();
}

class _NotificationsState extends State<Notifications> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder(
        future: () async {
          http.Response res = await http.get(
            Uri.parse("https://api.mrquantumoff.dev/api/v3/account/info/get"),
            headers: {
              "User-Agent": await generateUserAgent(),
              "Authorization": "Bearer ${widget.token}",
            },
          );
          debugPrint(res.body);
          if (res.statusCode == 200) {
            return res.body;
          }

          throw Exception(res.body);
        }(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(snapshot.error!.toString()),
            );
          }
          if (snapshot.hasData) {
            List<dynamic> nots = json.decode(snapshot.data!)["notifications"];

            List<Notification> notifications = [];

            debugPrint(nots.toString());

            for (var not in nots) {
              notifications.add(
                Notification(
                  token: widget.token,
                  notificationId: not["notification_id"],
                  message: not["message"],
                  createdAt: not["created_at"],
                  read: not["read"],
                  setReload: widget.setReload,
                ),
              );
            }

            return ListView(
              children: notifications,
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
