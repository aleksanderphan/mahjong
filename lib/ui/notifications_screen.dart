import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

String _ago(int t) {
  final s = (DateTime.now().millisecondsSinceEpoch - t) ~/ 1000;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60} min ago';
  if (s < 86400) return '${s ~/ 3600} h ago';
  return DateTime.fromMillisecondsSinceEpoch(t).toString().substring(0, 10);
}

/// Bell icon with an unread badge; opens the list.
class NotificationsBell extends StatelessWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext context) {
    final n = context.watch<AppState>().unread;
    return IconButton(
      tooltip: 'Notifications',
      icon: Badge(isLabelVisible: n > 0, label: Text(n > 9 ? '9+' : '$n'), child: const Icon(Icons.notifications_outlined)),
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final List<bool> _wasUnread;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _wasUnread = app.notifications.map((n) => !n.read).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) => app.markAllRead());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('🔔 Notifications'), actions: [TextButton(onPressed: app.notifications.isEmpty ? null : app.clearNotifications, child: const Text('Clear all'))]),
      body: app.notifications.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No notifications yet.\nYou will see rule changes and game updates here.', textAlign: TextAlign.center)))
          : ListView.separated(
              itemCount: app.notifications.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final n = app.notifications[i];
                final fresh = i < _wasUnread.length && _wasUnread[i];
                return ListTile(
                  tileColor: fresh ? Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.4) : null,
                  title: Text(n.title, style: TextStyle(fontWeight: fresh ? FontWeight.bold : null)),
                  subtitle: Text('${n.body}\n${_ago(n.at)}'),
                  isThreeLine: n.body.isNotEmpty,
                );
              },
            ),
    );
  }
}
