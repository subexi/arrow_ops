import 'package:flutter/widgets.dart';

enum ArrowOpsWindowClass { compact, medium, expanded }

class ArrowOpsBreakpoints {
  const ArrowOpsBreakpoints._();

  static const double compactMaxWidth = 600;
  static const double mediumMaxWidth = 1024;

  static ArrowOpsWindowClass fromWidth(double width) {
    if (width < compactMaxWidth) {
      return ArrowOpsWindowClass.compact;
    }
    if (width < mediumMaxWidth) {
      return ArrowOpsWindowClass.medium;
    }
    return ArrowOpsWindowClass.expanded;
  }

  static ArrowOpsWindowClass of(BuildContext context) {
    return fromWidth(MediaQuery.sizeOf(context).width);
  }
}
