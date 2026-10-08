import 'package:flutter/material.dart';

import '../../models/landlord_account.dart';
import '../theme/app_colors.dart';
import 'status_badge.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.badge,
  });
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final Widget? badge;
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.end,
    spacing: 20,
    runSpacing: 16,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 10), badge!],
            ],
          ),
        ],
      ),
      Wrap(spacing: 10, runSpacing: 10, children: actions),
    ],
  );
}

class LandlordAvatar extends StatelessWidget {
  const LandlordAvatar({super.key, required this.name, this.radius = 20});
  final String name;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts
        .take(2)
        .map((part) => part.isEmpty ? '' : part[0])
        .join()
        .toUpperCase();
    final colors = [
      AppColors.primaryBlue,
      AppColors.purple,
      AppColors.warning,
      AppColors.success,
    ];
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors[name.hashCode.abs() % colors.length].withAlpha(
        30,
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: colors[name.hashCode.abs() % colors.length],
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class HoverCard extends StatefulWidget {
  const HoverCard({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
      decoration: BoxDecoration(
        boxShadow: hovered
            ? [
                BoxShadow(
                  color: Colors.black.withAlpha(16),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : [],
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: widget.onTap, child: widget.child),
      ),
    ),
  );
}

class DashboardKpiCard extends StatelessWidget {
  const DashboardKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
    required this.tint,
    this.onTap,
  });
  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;
  final Color tint;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => HoverCard(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const Spacer(),
              Icon(Icons.arrow_forward, size: 17, color: color),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: .7,
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            caption,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
  });
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(42),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inbox_outlined,
            size: 44,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({super.key, this.rows = 5});
  final int rows;
  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) => Column(
      children: List.generate(
        widget.rows,
        (index) => Container(
          height: 68,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outline
                .withAlpha(20 + (controller.value * 18).round()),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
  );
}

class LandlordStatusChip extends StatelessWidget {
  const LandlordStatusChip({super.key, required this.landlord});
  final LandlordAccount landlord;
  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, children: [StatusBadge(status: landlord.status)]);
}
