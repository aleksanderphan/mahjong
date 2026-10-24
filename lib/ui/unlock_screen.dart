import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'theme.dart';

/// The shared database is locked behind an app password (checked server-side by Supabase's unlock_app()).
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});
  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pw = TextEditingController();
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      final ok = await context.read<AppState>().unlock(_pw.text);
      if (!ok && mounted) toast(context, 'Wrong password');
    } catch (e) {
      if (mounted) toast(context, 'Could not unlock: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🀄', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 8),
                Text('Mahjong SG Tracker', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                TextField(
                  controller: _pw,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'App password'),
                  onSubmitted: (_) => _go(),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _go, child: Text(_busy ? 'Checking…' : 'Unlock')),
              ]),
            ),
          ),
        ),
      );
}
