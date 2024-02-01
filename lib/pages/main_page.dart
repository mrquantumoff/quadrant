import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_svg/svg.dart';
import 'package:quadrant/pages/apply/selector.dart';

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.apply),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 15),
              child: SvgPicture.asset(
                "assets/icons/logo.svg",
                height: 128,
              ),
            ),
            const Selector(),
          ],
        ),
      ),
    );
  }
}
