import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../widgets/info_badge.dart';
import '../models.dart';
import 'geofence_add_screen.dart';

class GeofencesTab extends StatefulWidget {
  final List<Device> devices;
  const GeofencesTab({super.key, required this.devices});

  @override
  State<GeofencesTab> createState() => _GeofencesTabState();
}

class _GeofencesTabState extends State<GeofencesTab> {
  List<Geofence> _fences = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final fences = await ApiClient.instance.geofences();
      if (!mounted) return;
      setState(() {
        _fences = fences;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Błąd: $e')));
    }
  }

  Future<bool> _confirmDelete(Geofence f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usunąć strefę?'),
        content: Text('Strefa "${f.name}" i jej historia zdarzeń zostaną usunięte.'),
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

  List<Widget> _badges(BuildContext context, Geofence f) {
    final cs = Theme.of(context).colorScheme;
    final list = <Widget>[
      InfoBadge(
          f.isCircle ? Icons.circle_outlined : Icons.pentagon_outlined,
          f.isCircle
              ? 'promień ${f.radiusM.toStringAsFixed(0)} m'
              : '${f.polygonPoints.length} wierzchołków'),
      InfoBadge(Icons.gps_fixed, _deviceName(f.deviceId)),
    ];
    if (f.activeFrom != null && f.activeTo != null) {
      list.add(InfoBadge(Icons.schedule,
          '${f.activeFrom!.substring(0, 5)}–${f.activeTo!.substring(0, 5)}'));
    }
    if (!f.alertOnEnter || !f.alertOnExit) {
      list.add(InfoBadge(
        f.alertOnEnter ? Icons.login : Icons.logout,
        f.alertOnEnter
            ? 'tylko wejścia'
            : (f.alertOnExit ? 'tylko wyjścia' : 'bez alarmów'),
        bg: cs.tertiaryContainer,
        fg: cs.onTertiaryContainer,
      ));
    }
    return list;
  }

  String _deviceName(int? id) {
    if (id == null) return 'wszystkie urządzenia';
    return widget.devices
        .where((d) => d.id == id)
        .map((d) => d.name)
        .firstOrNull ??
        'urządzenie #$id';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: LayoutBuilder(
                  builder: (ctx, c) => _fences.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: c.maxHeight,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fence,
                                    size: 56,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline),
                                const SizedBox(height: 12),
                                Text(
                                    'Brak stref - dodaj pierwszą przyciskiem +',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ),
                      ])
                  : ListView.separated(
                      itemCount: _fences.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final f = _fences[i];
                        Future<void> openEdit() async {
                          final changed = await Navigator.of(context)
                              .push<bool>(MaterialPageRoute(
                                  builder: (_) => GeofenceAddScreen(
                                      devices: widget.devices,
                                      existing: f)));
                          if (changed == true) _load();
                        }

                        return Dismissible(
                          key: ValueKey('fence-${f.id}'),
                          background: Container(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 20),
                            child: Icon(Icons.edit_outlined,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer),
                          ),
                          secondaryBackground: Container(
                            color: Theme.of(context)
                                .colorScheme
                                .errorContainer,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: Icon(Icons.delete_outline,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer),
                          ),
                          confirmDismiss: (dir) async {
                            if (dir == DismissDirection.startToEnd) {
                              openEdit();
                              return false;
                            }
                            return _confirmDelete(f);
                          },
                          onDismissed: (_) async {
                            await ApiClient.instance.deleteGeofence(f.id);
                            _load();
                          },
                          child: ListTile(
                            isThreeLine: true,
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: Icon(
                                f.isCircle
                                    ? Icons.circle_outlined
                                    : Icons.pentagon_outlined,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                            ),
                            title: Text(f.name),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: _badges(context, f),
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: openEdit,
                          ),
                        );
                      },
                    )),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                  builder: (_) => GeofenceAddScreen(devices: widget.devices)));
          if (created == true) _load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
