import 'dart:async';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models.dart';
import '../widgets/info_badge.dart';

class EventsTab extends StatefulWidget {
  const EventsTab({super.key});

  @override
  State<EventsTab> createState() => _EventsTabState();
}

class _FeedItem {
  final DateTime when;
  final ZoneEvent? event;
  final AppNotification? alert;
  _FeedItem.event(ZoneEvent e)
      : when = e.occurredAt,
        event = e,
        alert = null;
  _FeedItem.alert(AppNotification n)
      : when = n.createdAt,
        event = null,
        alert = n;
}

class _EventsTabState extends State<EventsTab> {
  List<_FeedItem> _items = [];
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiClient.instance.events(),
        ApiClient.instance.notifications(),
      ]);
      if (!mounted) return;
      final events = results[0] as List<ZoneEvent>;
      final alerts = (results[1] as List<AppNotification>)
          .where((n) => n.zoneEventId == null);
      final items = <_FeedItem>[
        for (final e in events) _FeedItem.event(e),
        for (final n in alerts) _FeedItem.alert(n),
      ]..sort((a, b) => b.when.compareTo(a.when));
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(_FeedItem item) async {
    try {
      if (item.event != null) {
        await ApiClient.instance.deleteEvent(item.event!.id);
      } else {
        await ApiClient.instance.deleteNotification(item.alert!.id);
      }
      setState(() => _items.remove(item));
    } catch (_) {
      _load();
    }
  }

  Widget _empty(BoxConstraints c) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: c.maxHeight,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none,
                      size: 56,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Brak zdarzeń - alerty stref i powiadomienia\n'
                      'systemowe pojawią się tutaj',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _tile(_FeedItem item) {
    final cs = Theme.of(context).colorScheme;
    if (item.event != null) {
      final e = item.event!;
      final enter = e.eventType == 'ENTER';
      return ListTile(
        isThreeLine: true,
        leading: CircleAvatar(
          backgroundColor:
              enter ? cs.primaryContainer : cs.tertiaryContainer,
          child: Icon(enter ? Icons.login : Icons.logout,
              color:
                  enter ? cs.onPrimaryContainer : cs.onTertiaryContainer),
        ),
        title: Text(e.deviceName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(enter ? 'wejście do strefy' : 'wyjście ze strefy'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                InfoBadge(Icons.fence, e.geofenceName),
                InfoBadge(Icons.schedule, formatTime(e.occurredAt)),
              ],
            ),
          ],
        ),
      );
    }
    final n = item.alert!;
    final parts = n.title.split(': ');
    final device = parts.first;
    final action = parts.length > 1 ? parts.sublist(1).join(': ') : n.body;
    final pct = RegExp(r'(\d+)\s*%').firstMatch(n.body)?.group(1);
    return ListTile(
      isThreeLine: true,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
        child: Icon(Icons.battery_alert,
            color: Theme.of(context).colorScheme.onErrorContainer),
      ),
      title: Text(device),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(action),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (pct != null)
                InfoBadge(Icons.battery_alert, '$pct%',
                    bg: Theme.of(context).colorScheme.errorContainer,
                    fg: Theme.of(context).colorScheme.onErrorContainer),
              InfoBadge(Icons.schedule, formatTime(n.createdAt)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dismissible(_FeedItem item) => Dismissible(
        key: ValueKey(item.event != null
            ? 'e${item.event!.id}'
            : 'n${item.alert!.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          color: Theme.of(context).colorScheme.errorContainer,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: Icon(Icons.delete_outline,
              color: Theme.of(context).colorScheme.onErrorContainer),
        ),
        onDismissed: (_) => _delete(item),
        child: _tile(item),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final groups = <DateTime, List<_FeedItem>>{};
    for (final item in _items) {
      final d = DateTime(item.when.year, item.when.month, item.when.day);
      groups.putIfAbsent(d, () => []).add(item);
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (ctx, c) => _items.isEmpty
            ? _empty(c)
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  for (final entry in groups.entries)
                    ExpansionTile(
                      key: PageStorageKey('day-${entry.key}'),
                      initiallyExpanded: entry.key == today,
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text(
                        dayLabel(entry.key),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('wpisy: ${entry.value.length}',
                          style: Theme.of(context).textTheme.bodySmall),
                      children: [
                        for (final item in entry.value) ...[
                          _dismissible(item),
                          const Divider(height: 1, indent: 72),
                        ],
                      ],
                    ),
                ],
              ),
      ),
    );
  }
}
