import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/scan.dart';
import '../core/scoring.dart';
import 'pattern_picker.dart';
import 'theme.dart';

/// Standalone Tai & payout calculator (nothing is saved).
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _picker = PickerState();
  String _method = 'self';

  @override
  Widget build(BuildContext context) {
    final rules = context.watch<AppState>().house;
    return ListenableBuilder(
      listenable: _picker,
      builder: (context, _) {
        final res = _picker.result(rules, selfDraw: _method == 'self');
        final unit = rules.scoreLabel;
        List<int>? d;
        if (res.hand.valid) {
          d = winDeltas(
            winner: 0,
            shooter: _method == 'discard' ? 1 : null,
            selfDraw: _method == 'self',
            baoBy: _method == 'bao' ? 1 : null,
            tai: res.hand.actual,
            cap: rules.taiCap,
            baoMultiplier: rules.baoMultiplier,
          );
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Score calculator', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              const ButtonSegment(value: 'self', label: Text('Self-draw')),
              const ButtonSegment(value: 'discard', label: Text('Discard')),
              ButtonSegment(value: 'bao', label: Text('Pay-all ${rules.baoMultiplier}×')),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: 12),
          PatternPicker(state: _picker, rules: rules, selfDraw: _method == 'self', scanContext: ScanContext(selfDraw: _method == 'self')),
          if (d != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Payout (winner East${_method == 'self' ? '' : ', South ${_method == 'bao' ? 'pays all' : 'discards'}'})', style: Theme.of(context).textTheme.titleSmall),
                  for (var i = 0; i < 4; i++)
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(const ['East', 'South', 'West', 'North'][i]),
                      Text('${sign(d[i])} $unit', style: TextStyle(fontWeight: FontWeight.bold, color: deltaColor(context, d[i]))),
                    ]),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}
