import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/landlord_account.dart';
import '../../providers/settings_providers.dart';
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
                ?.copyWith(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              ?badge,
            ],
          ),
        ],
      ),
      Wrap(spacing: 10, runSpacing: 10, children: actions),
    ],
  );
}

class RampListSkeleton extends StatelessWidget {
  const RampListSkeleton({super.key, this.rows = 4});
  final int rows;

  @override
  Widget build(BuildContext context) => LoadingSkeleton(rows: rows);
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

class HoverCard extends ConsumerStatefulWidget {
  const HoverCard({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  ConsumerState<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends ConsumerState<HoverCard> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        ref.watch(reducedMotionProvider) ||
        MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(
          0,
          hovered && !reduceMotion ? -2 : 0,
          0,
        ),
        decoration: BoxDecoration(
          boxShadow: hovered && !reduceMotion
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
    this.compact = false,
    this.icon = Icons.inbox_outlined,
  });
  final String title;
  final String message;
  final Widget? action;
  final bool compact;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 20 : 42,
      vertical: compact ? 22 : 42,
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 54 : 68,
            height: compact ? 54 : 68,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: compact ? 27 : 34,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class LoadingSkeleton extends ConsumerStatefulWidget {
  const LoadingSkeleton({super.key, this.rows = 5});
  final int rows;
  @override
  ConsumerState<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends ConsumerState<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    if (MediaQuery.disableAnimationsOf(context) ||
        ref.read(reducedMotionProvider)) {
      controller.stop();
    } else if (!controller.isAnimating) {
      controller.repeat();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(reducedMotionProvider);
    _syncMotion();
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) => Column(
        children: List.generate(
          widget.rows,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 68,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1.5 + controller.value * 2, 0),
                end: Alignment(-.5 + controller.value * 2, 0),
                colors: [
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                  Theme.of(context).colorScheme.surface,
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant LoadingSkeleton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }
}

class RampEntrance extends ConsumerStatefulWidget {
  const RampEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  ConsumerState<RampEntrance> createState() => _RampEntranceState();
}

class _RampEntranceState extends ConsumerState<RampEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      _timer = null;
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced =
        ref.watch(reducedMotionProvider) ||
        MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      _timer?.cancel();
      _timer = null;
      _controller.stop();
      return widget.child;
    }
    if (_timer == null &&
        !_controller.isCompleted &&
        !_controller.isAnimating) {
      _controller.forward();
    }
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, reduced ? 0 : 10 * (1 - curve.value)),
          child: child,
        ),
      ),
    );
  }
}

class RampMetricSkeleton extends StatelessWidget {
  const RampMetricSkeleton({super.key, this.count = 4});
  final int count;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900
          ? 4
          : constraints.maxWidth >= 520
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: List.generate(
          count,
          (index) => SizedBox(
            width: width,
            height: 138,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const RampSkeleton(width: 38, height: 38, radius: 13),
                    const RampSkeleton(width: 108, height: 12),
                    const RampSkeleton(width: 142, height: 25),
                    const RampSkeleton(width: 124, height: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class RampSkeleton extends ConsumerStatefulWidget {
  const RampSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 7,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  ConsumerState<RampSkeleton> createState() => _RampSkeletonState();
}

class _RampSkeletonState extends ConsumerState<RampSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    if (MediaQuery.disableAnimationsOf(context) ||
        ref.read(reducedMotionProvider)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(reducedMotionProvider);
    _syncMotion();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1.5 + _controller.value * 2, 0),
            end: Alignment(-.5 + _controller.value * 2, 0),
            colors: [
              Theme.of(context).colorScheme.surfaceContainerHighest,
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceContainerHighest,
            ],
          ),
        ),
      ),
    );
  }
}

class RampTableSkeleton extends StatelessWidget {
  const RampTableSkeleton({super.key, this.rows = 5});
  final int rows;
  @override
  Widget build(BuildContext context) => LoadingSkeleton(rows: rows);
}

class RampChartSkeleton extends StatelessWidget {
  const RampChartSkeleton({super.key});
  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 210, child: LoadingSkeleton(rows: 2));
}

class ResponsiveFilterToolbar extends StatelessWidget {
  const ResponsiveFilterToolbar({
    super.key,
    required this.search,
    required this.filters,
    this.activeFilterCount = 0,
  });

  final Widget search;
  final List<Widget> filters;
  final int activeFilterCount;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 700;
      if (!compact) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: 300, child: search),
                ...filters,
              ],
            ),
          ),
        );
      }

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    showDragHandle: true,
                    builder: (sheetContext) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              MediaQuery.sizeOf(sheetContext).height * .82,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    activeFilterCount > 0
                                        ? 'Filters ($activeFilterCount)'
                                        : 'Filters',
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Close filters',
                                  onPressed: () =>
                                      Navigator.of(sheetContext).pop(),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final filter in filters)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: filter,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                child: const Text('Done'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.tune_rounded),
                  label: Text(
                    activeFilterCount > 0
                        ? 'Filters ($activeFilterCount)'
                        : 'Filters',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class LandlordStatusChip extends StatelessWidget {
  const LandlordStatusChip({super.key, required this.landlord});
  final LandlordAccount landlord;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      StatusBadge(
        status: landlord.status,
        label: landlord.statusLabel.toUpperCase(),
      ),
    ],
  );
}
