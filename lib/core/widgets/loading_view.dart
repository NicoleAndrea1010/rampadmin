import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_providers.dart';
import '../theme/app_colors.dart';

class LoadingView extends ConsumerStatefulWidget {
  const LoadingView({super.key, this.message = 'Loading...'});

  final String message;

  @override
  ConsumerState<LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends ConsumerState<LoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        ref.watch(reducedMotionProvider) ||
        MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) _pulse.stop();
    if (!reduceMotion && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Transform.scale(
              scale: reduceMotion ? 1 : .96 + _pulse.value * .04,
              child: child,
            ),
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryBlue, Color(0xFF4C8CFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withAlpha(32),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.apartment_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 13),
          Text(
            'RAMP',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          const SizedBox(height: 6),
          Text(
            widget.message,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: 84,
            child: LinearProgressIndicator(
              value: reduceMotion ? .45 : null,
              minHeight: 3,
              borderRadius: BorderRadius.circular(8),
              color: AppColors.primaryBlue,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}
