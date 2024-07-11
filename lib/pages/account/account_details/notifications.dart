import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:quadrant/draggable_appbar.dart';
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

    debugPrint("NOTIFICATION : ${widget.message}");

    List<Widget> children = [];

    bool showRead = true;

    if (notification["notification_type"] == "login") {
      children = [
        Text(
          notification["simple_message"],
          style: const TextStyle(fontSize: 24),
        )
      ];
    } else if (notification["notification_type"] == "invite_to_sync") {
      showRead = false;
      String name = notification["message"]
          .split("have been invited to collaborate on a modpack by ")
          .last;
      children = [
        Text(
          AppLocalizations.of(context)!.invited(name),
          style: const TextStyle(fontSize: 24),
        ),
        const SizedBox(
          height: 12,
        ),
        widget.read
            ? Container()
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      http.Response res = await http.post(
                        Uri.parse(
                            "https://api.mrquantumoff.dev/api/v3/quadrant/sync/respond"),
                        headers: {
                          "User-Agent": await generateUserAgent(),
                          "Authorization": "Bearer ${widget.token}",
                          "Content-Type": "application/json"
                        },
                        body: json.encode({
                          "modpack_id": notification["invite_id"],
                          "accept": true,
                        }),
                      );
                      debugPrint("${res.body} (${res.statusCode})");
                      if (res.statusCode != 200) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: SnackBar(
                              content: Text("${res.body} (${res.statusCode})"),
                            ),
                          ),
                        );
                        return;
                      }
                      http.Response readRes = await http.post(
                        Uri.parse(
                            "https://api.mrquantumoff.dev/api/v3/account/notifications/read"),
                        headers: {
                          "User-Agent": await generateUserAgent(),
                          "Authorization": "Bearer ${widget.token}",
                          "Content-Type": "application/json"
                        },
                        body: json.encode(
                          {
                            "notification_id": widget.notificationId,
                          },
                        ),
                      );
                      debugPrint("${readRes.body} (${readRes.statusCode})");

                      if (readRes.statusCode != 200) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: SnackBar(
                              content: Text(
                                  "${readRes.body} (${readRes.statusCode})"),
                            ),
                          ),
                        );
                        return;
                      }
                      Get.back();
                    },
                    label: Text(AppLocalizations.of(context)!.accept),
                    icon: const Icon(Icons.check),
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      http.Response res = await http.post(
                        Uri.parse(
                            "https://api.mrquantumoff.dev/api/v3/quadrant/sync/respond"),
                        headers: {
                          "User-Agent": await generateUserAgent(),
                          "Authorization": "Bearer ${widget.token}",
                          "Content-Type": "application/json"
                        },
                        body: json.encode({
                          "modpack_id": notification["invite_id"],
                          "accept": false,
                        }),
                      );
                      debugPrint("${res.body} (${res.statusCode})");
                      if (res.statusCode != 200) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: SnackBar(
                              content: Text("${res.body} (${res.statusCode})"),
                            ),
                          ),
                        );
                        return;
                      }
                      http.Response readRes = await http.post(
                        Uri.parse(
                            "https://api.mrquantumoff.dev/api/v3/account/notifications/read"),
                        headers: {
                          "User-Agent": await generateUserAgent(),
                          "Authorization": "Bearer ${widget.token}",
                          "Content-Type": "application/json"
                        },
                        body: json.encode(
                          {
                            "notification_id": widget.notificationId,
                          },
                        ),
                      );
                      debugPrint("${readRes.body} (${readRes.statusCode})");

                      if (readRes.statusCode != 200) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: SnackBar(
                              content: Text(
                                  "${readRes.body} (${readRes.statusCode})"),
                            ),
                          ),
                        );
                        return;
                      }
                      Get.back();
                    },
                    label: Text(AppLocalizations.of(context)!.decline),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
      ];
    } else {
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
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          child: Column(
            children: children +
                (read || !showRead
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
      appBar: DraggableAppBar(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.account),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Get.back(),
          ),
        ),
      ),
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

            debugPrint("DATA: ${snapshot.data}");

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
            notifications.sort((a, b) => b.createdAt - a.createdAt);
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
