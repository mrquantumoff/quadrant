import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

// ignore: must_be_immutable
class DraggableAppBar extends StatelessWidget implements PreferredSizeWidget {
  AppBar appBar = AppBar();

  DraggableAppBar({
    super.key,
    required this.appBar,
  });

  @override
  Widget build(BuildContext context) {
    AppBar finalAppBar = AppBar(
      title: appBar.title,
      leading: appBar.leading,
      actions: appBar.actions ??
          <Widget>[] +
              <Widget>[
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: IconButton(
                    onPressed: () async {
                      windowManager.minimize();
                    },
                    icon: const Icon(Icons.minimize),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: IconButton(
                    onPressed: () async {
                      windowManager.hide();
                    },
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
    );

    return DragToMoveArea(
      child: finalAppBar,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
