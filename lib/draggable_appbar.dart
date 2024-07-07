import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class DraggableAppBar extends StatelessWidget implements PreferredSizeWidget {
  final AppBar appBar;

  const DraggableAppBar({
    super.key,
    required this.appBar,
  });

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: appBar,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
