import 'package:flutter/material.dart';

const _seed = Color(0xFF0B6E4F); // mahjong-table green

ThemeData buildTheme(Brightness b) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: b),
      cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 6)),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );

String sign(num x) => x > 0 ? '+$x' : '$x';

Color deltaColor(BuildContext c, num x) => x > 0 ? Colors.green.shade600 : (x < 0 ? Theme.of(c).colorScheme.error : Theme.of(c).hintColor);

void toast(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(msg)));

Future<bool> confirm(BuildContext c, String title, String text, {String ok = 'Confirm', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}
