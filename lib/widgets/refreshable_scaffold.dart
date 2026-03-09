import 'package:flutter/material.dart';

class RefreshableWrapper extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const RefreshableWrapper({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: Colors.green, // Your app's theme color
      backgroundColor: Colors.white,
      child: child is SingleChildScrollView
          ? child
          : SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: child,
      ),
    );
  }
}