import 'package:flutter/material.dart';

import 'calculator_screen.dart';
import 'home_screen.dart';
import 'more_screen.dart';
import 'players_screen.dart';
import 'ranking_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;
  static const _pages = <Widget>[HomeScreen(), CalculatorScreen(), RankingScreen(), PlayersScreen(), MoreScreen()];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: IndexedStack(index: _i, children: _pages)),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _i,
          onDestinationSelected: (i) => setState(() => _i = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.calculate_outlined), selectedIcon: Icon(Icons.calculate), label: 'Score'),
            NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Ranking'),
            NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Players'),
            NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
          ],
        ),
      );
}
