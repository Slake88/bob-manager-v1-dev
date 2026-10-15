import 'package:flutter/material.dart';

enum AppLayoutSize { compact, medium, expanded }

class AppBreakpoints {
  const AppBreakpoints._();

  static const double medium = 600;
  static const double expanded = 1000;

  static AppLayoutSize forWidth(double width) {
    if (width < medium) return AppLayoutSize.compact;
    if (width < expanded) return AppLayoutSize.medium;
    return AppLayoutSize.expanded;
  }

  static AppLayoutSize of(BuildContext context) {
    return forWidth(MediaQuery.sizeOf(context).width);
  }
}
