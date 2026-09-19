import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models.dart';
import '../widgets/info_badge.dart';
import 'route_replay_screen.dart';

class HistoryTab extends StatefulWidget {
  final List<Device> devices;
  final int? selectedDeviceId;
  final ValueChanged<int?> onDeviceChanged;

  const HistoryTab({
    super.key,
    required this.devices,
    required this.selectedDeviceId,
    required this.onDeviceChanged,
  });

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  List<LocationDay> _days = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HistoryTab old) {
    super.didUpdateWidget(old);
    if (old.selectedDeviceId != widget.selectedDeviceId) _load();
  }

  Future<void> _load() async {
    final deviceId = widget.selectedDeviceId;
    if (deviceId == null) {
      setState(() {
        _days = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final days = await ApiClient.instance.locationDays(deviceId);
      if (!mounted) return;
      setState(() {
        _days = days;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _deviceName(int id) =>
      widget.devices.where((d) => d.id == id).map((d) => d.name).firstOrNull ??
      '';

  @override
  Widget build(BuildContext context) {
    if (widget.devices.isEmpty) {
      return const Center(
          child: Text('Dodaj urządzenie, aby zobaczyć historię tras'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: DropdownMenu<int>(
            key: ValueKey(widget.selectedDeviceId),
            initialSelection: widget.selectedDeviceId,
            label: const Text('Urządzenie'),
            expandedInsets: EdgeInsets.zero,
            onSelected: (v) {
              if (v != null) widget.onDeviceChanged(v);
            },
            dropdownMenuEntries: [
              for (final d in widget.devices)
                DropdownMenuEntry(value: d.id, label: d.name),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: LayoutBuilder(
                    builder: (ctx, c) => _days.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: c.maxHeight,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.route,
                                          size: 56,
                                          color: Theme.of(ctx)
                                              .colorScheme
                                              .outline),
                                      const SizedBox(height: 12),
                                      Text(
                                          'Brak zapisanych tras dla tego urządzenia',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: Theme.of(ctx)
                                                  .colorScheme
                                                  .onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            itemCount: _days.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final d = _days[i];
                              final cs = Theme.of(ctx).colorScheme;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: cs.primaryContainer,
                                  child: Icon(Icons.route,
                                      color: cs.onPrimaryContainer),
                                ),
                                title: Text(dayLabel(d.day)),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      InfoBadge(Icons.straighten,
                                          formatDistance(d.distanceM)),
                                      if (d.maxSpeedKmh != null &&
                                          d.maxSpeedKmh! > 0)
                                        InfoBadge(Icons.speed,
                                            'max ${d.maxSpeedKmh!.toStringAsFixed(1).replaceAll('.', ',')} km/h'),
                                    ],
                                  ),
                                ),
                                trailing:
                                    const Icon(Icons.play_circle_outline),
                                onTap: () {
                                  final id = widget.selectedDeviceId;
                                  if (id == null) return;
                                  Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => RouteReplayScreen(
                                            deviceId: id,
                                            deviceName: _deviceName(id),
                                            day: d.day,
                                          )));
                                },
                              );
                            },
                          ),
                  ),
                ),
        ),
      ],
    );
  }
}
