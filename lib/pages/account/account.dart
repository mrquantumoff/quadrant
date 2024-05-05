import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:quadrant/pages/account/account_details/details_page.dart';
import 'package:quadrant/pages/account/sign_in_or_register/sign_in.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  @override
  void initState() {
    super.initState();
  }

  final storage = const FlutterSecureStorage();

  Future<Widget> getAccountPage() async {
    String? token = await storage.read(key: "quadrant_id_token");
    if (token == null) {
      return const SignInPage();
    } else {
      return const AccountDetails();
    }
    // return Container();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.account,
        ),
      ),
      body: FutureBuilder(
        future: getAccountPage(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return snapshot.data!;
          }
          if (snapshot.hasError) {
            return Text(snapshot.error.toString());
          }
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      ),
    );
  }
}
