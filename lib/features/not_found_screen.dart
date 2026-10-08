import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/admin_routes.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_outlined, size: 56),
              const SizedBox(height: 16),
              const Text(
                'Page not found',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text('The page you requested does not exist.'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.go(AdminRoutes.dashboard),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
