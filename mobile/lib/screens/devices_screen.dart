import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/api_client.dart';
import '../models.dart';
import '../widgets/info_badge.dart';
import 'qr_scan_screen.dart';

class DevicesTab extends StatelessWidget {
  final List<Device> devices;
  final VoidCallback onChanged;

  const DevicesTab({super.key, required this.devices, required this.onChanged});

  Future<String?> _askName(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nazwa urządzenia'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'np. Plecak, Rower'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Anuluj')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Dalej')),
        ],
      ),
    );
    return (name == null || name.isEmpty) ? null : name;
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _claimWithKey(BuildContext context, String key) async {
    if (devices.any((d) => d.deviceKey == key)) {
      _snack(context, 'To urządzenie jest już dodane do Twojego konta');
      return;
    }
    final name = await _askName(context);
    if (name == null || !context.mounted) return;
    try {
      final device = await ApiClient.instance.claimDevice(key, name);
      onChanged();
      if (!context.mounted) return;
      _snack(context, 'Dodano urządzenie "${device.name}"');
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, 'Błąd: $e');
    }
  }

  Future<void> _scanFlow(BuildContext context) async {
    final key = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (key == null || !context.mounted) return;
    await _claimWithKey(context, key.trim());
  }

  Future<void> _manualFlow(BuildContext context) async {
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Numer seryjny'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration:
              const InputDecoration(labelText: 'Numer z etykiety urządzenia'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Anuluj')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Dalej')),
        ],
      ),
    );
    if (key == null || key.isEmpty || !context.mounted) return;
    if (!RegExp(r'^[A-Za-z0-9_-]{6,64}$').hasMatch(key)) {
      _snack(context,
          'Nieprawidłowy numer seryjny');
      return;
    }
    await _claimWithKey(context, key);
  }

  void _addMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Zeskanuj kod QR'),
              subtitle: const Text('z etykiety lokalizatora'),
              onTap: () {
                Navigator.pop(ctx);
                _scanFlow(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.keyboard_alt_outlined),
              title: const Text('Wpisz numer seryjny'),
              subtitle: const Text('jeśli kod jest nieczytelny'),
              onTap: () {
                Navigator.pop(ctx);
                _manualFlow(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _configDialog(BuildContext context, Device d) async {
    final controller =
        TextEditingController(text: '${d.reportIntervalS ?? 10}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text('Konfiguracja: ${d.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Interwał [s]'),
            ),
            const SizedBox(height: 16),
            Text('Numer seryjny',
                style: Theme.of(ctx).textTheme.bodySmall),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    d.deviceKey,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Kopiuj',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: d.deviceKey));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Skopiowano numer seryjny')));
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Anuluj')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Wyślij do urządzenia')),
        ],
      ),
    );
    if (saved != true || !context.mounted) return;
    final value = int.tryParse(controller.text.trim());
    if (value == null || value < 1 || value > 3600) {
      _snack(context, 'Interwał musi być liczbą z zakresu 1-3600 sekund');
      return;
    }
    try {
      await ApiClient.instance.updateDeviceConfig(d.id, value);
      onChanged();
      if (!context.mounted) return;
      _snack(context,
          'Wysłano do urządzenia');
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, 'Błąd: $e');
    }
  }

  Future<bool> _confirmDelete(BuildContext context, Device d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usunąć urządzenie?'),
        content: Text(
            'Urządzenie "${d.name}" wraz z całą historią lokalizacji zostanie usunięte.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Anuluj')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Usuń')),
        ],
      ),
    );
    return ok == true;
  }

  Widget _tile(BuildContext context, Device d) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('device-${d.id}'),
      background: Container(
        color: scheme.primaryContainer,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Icon(Icons.settings, color: scheme.onPrimaryContainer),
      ),
      secondaryBackground: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          _configDialog(context, d);
          return false;
        }
        return _confirmDelete(context, d);
      },
      onDismissed: (_) async {
        await ApiClient.instance.deleteDevice(d.id);
        onChanged();
      },
      child: ListTile(
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.gps_fixed,
                  color: scheme.onPrimaryContainer),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: d.isOnline ? scheme.primary : scheme.outline,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
              ),
            ),
          ],
        ),
        title: Text(d.name),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              d.isOnline
                  ? InfoBadge(Icons.wifi, 'Online',
                      bg: scheme.primaryContainer,
                      fg: scheme.onPrimaryContainer)
                  : InfoBadge(Icons.wifi_off, 'Offline',
                      bg: scheme.surfaceContainerHighest,
                      fg: scheme.onSurfaceVariant),
              if (d.batteryPct != null)
                d.batteryPct! <= 20
                    ? InfoBadge(Icons.battery_alert, '${d.batteryPct}%',
                        bg: scheme.errorContainer,
                        fg: scheme.onErrorContainer)
                    : InfoBadge(
                        d.batteryPct! <= 50
                            ? Icons.battery_4_bar
                            : Icons.battery_full,
                        '${d.batteryPct}%'),
              if (d.lastSeenAt != null)
                InfoBadge(Icons.schedule, timeAgo(d.lastSeenAt!)),
              if (d.reportIntervalS != null)
                InfoBadge(Icons.timer_outlined, 'co ${d.reportIntervalS} s'),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _configDialog(context, d),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: devices.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.gps_off,
                      size: 56,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('Dodaj pierwsze urządzenie przyciskiem +',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)),
                ],
              ),
            )
          : ListView.separated(
              itemCount: devices.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) => _tile(ctx, devices[i]),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addMenu(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
