import 'dart:async';

import 'package:flutter/material.dart';

class TransientFeedback {
  static OverlayEntry? _overlayEntry;
  static Timer? _overlayTimer;

  static void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(milliseconds: 1600),
    IconData? iconData,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final effectiveForegroundColor = foregroundColor ?? Colors.white;
    if (messenger != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            backgroundColor: backgroundColor,
            content: Row(
              children: [
                if (iconData != null) ...[
                  Icon(iconData, color: effectiveForegroundColor, size: 18),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: effectiveForegroundColor),
                  ),
                ),
              ],
            ),
            duration: duration,
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }

    _overlayTimer?.cancel();
    _overlayEntry?.remove();

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final topInset = MediaQuery.maybeOf(overlayContext)?.padding.top ?? 0;
        return Positioned(
          top: topInset + 14,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: backgroundColor ?? Colors.black.withValues(alpha: 0.84),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (iconData != null) ...[
                        Icon(iconData, size: 18, color: effectiveForegroundColor),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          message,
                          style: TextStyle(color: effectiveForegroundColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_overlayEntry!);
    _overlayTimer = Timer(duration, () {
      _overlayEntry?.remove();
      _overlayEntry = null;
      _overlayTimer = null;
    });
  }
}