import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Snapshot;

import 'app_state.dart';
import 'data/local_repository.dart';
import 'data/repository.dart';
import 'data/supabase_repository.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/unlock_screen.dart';

// Pass with: flutter run --dart-define-from-file=env.json   (see env.example.json)
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Repository repo;
  if (_supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty) {
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
    repo = SupabaseRepository();
  } else {
    repo = LocalRepository(); // demo mode: this device only
  }
  final state = AppState(repo);
  runApp(ChangeNotifierProvider.value(value: state, child: const MahjongApp()));
  state.init();
}

class MahjongApp extends StatelessWidget {
  const MahjongApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mahjong SG Tracker',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const _Gate(),
      );
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.initError != null) {
      return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not connect: ${s.initError}', textAlign: TextAlign.center))));
    }
    if (!s.initialised) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!s.unlocked) return const UnlockScreen();
    return const Shell();
  }
}
