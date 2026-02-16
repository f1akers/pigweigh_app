import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/constants/storage_keys.dart';
import 'core/theme/app_theme.dart';
import 'providers/router_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  // Initialise Hive (local key-value storage)
  await Hive.initFlutter();

  // Open Hive boxes needed at startup
  await Future.wait([
    Hive.openBox(StorageKeys.settingsBox),
    Hive.openBox(StorageKeys.cacheBox),
    Hive.openBox(StorageKeys.adminCacheBox),
  ]);

  runApp(const ProviderScope(child: PigWeighApp()));
}

class PigWeighApp extends ConsumerWidget {
  const PigWeighApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'PigWeigh',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
