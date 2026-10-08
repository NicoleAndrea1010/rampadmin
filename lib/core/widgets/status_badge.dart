import 'package:flutter/material.dart';

import '../../models/landlord_account.dart';
import '../theme/app_colors.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.label});

  final LandlordStatus status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    Color textColor;
    Color bgColor;

    switch (status) {
      case LandlordStatus.active:
        textColor = AppColors.success;
        bgColor = AppColors.successBg;
        break;
      case LandlordStatus.invited:
        textColor = AppColors.warning;
        bgColor = AppColors.warningBg;
        break;
      case LandlordStatus.suspended:
        textColor = AppColors.error;
        bgColor = AppColors.errorBg;
        break;
      case LandlordStatus.archived:
        textColor = AppColors.textMuted;
        bgColor = AppColors.borderLight;
        break;
      case LandlordStatus.unknown:
        textColor = AppColors.textSecondary;
        bgColor = AppColors.borderLight;
        break;
    }
    if (Theme.of(context).brightness == Brightness.dark) {
      textColor = Color.lerp(textColor, Colors.white, .2)!;
      bgColor = textColor.withAlpha(36);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withAlpha(50), width: 1),
      ),
      child: Text(
        label ??
            (status == LandlordStatus.invited
                ? 'PENDING ACTIVATION'
                : status == LandlordStatus.unknown
                ? 'UNKNOWN'
                : status.name.toUpperCase()),
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
