import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../api/api_client.dart';
import '../config.dart';
import '../models.dart';

class GeofenceAddScreen extends StatefulWidget {
  final List<Device> devices;
  final Geofence? existing;
  const GeofenceAddScreen({super.key, required this.devices, this.existing});

  @override
  State<GeofenceAddScreen> createState() => _GeofenceAddScreenState();
}

class _GeofenceAddScreenState extends State<GeofenceAddScreen> {
  final _name = TextEditingController();
  String _mode = 'circle';
  LatLng? _center;
  double _radiusM = 200;
  List<LatLng> _vertices = [];
  int? _deviceId;
  bool _saving = false;
  late final CameraPosition _initialCam;

  bool _alertEnter = true;
  bool _alertExit = true;
  bool _windowEnabled = false;
  TimeOfDay? _from;
  TimeOfDay? _to;

  @override
  void initState() {
    super.initState();
    final f = widget.existing;
    if (f != null) {
      _name.text = f.name;
      _deviceId = f.deviceId;
      _alertEnter = f.alertOnEnter;
      _alertExit = f.alertOnExit;
      if (f.activeFrom != null && f.activeTo != null) {
        _windowEnabled = true;
        _from = _parseTime(f.activeFrom!);
        _to = _parseTime(f.activeTo!);
      }
      if (f.isCircle) {
        _mode = 'circle';
        _center = LatLng(f.centerLat!, f.centerLon!);
        _radiusM = f.radiusM.clamp(50.0, 2000.0);
      } else {
        _mode = 'polygon';
        _vertices = [for (final p in f.polygonPoints) LatLng(p[0], p[1])];
      }
    }
    final target = _center ??
        (_vertices.isNotEmpty
            ? _vertices.first
            : const LatLng(defaultLat, defaultLon));
    _initialCam = CameraPosition(target: target, zoom: 14);
  }

  TimeOfDay _parseTime(String hhmmss) {
    final parts = hhmmss.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  List<LatLng> get _orderedVertices {
    if (_vertices.length < 3) return List.of(_vertices);
    final cLat = _vertices.map((v) => v.latitude).reduce((a, b) => a + b) /
        _vertices.length;
    final cLon = _vertices.map((v) => v.longitude).reduce((a, b) => a + b) /
        _vertices.length;
    final sorted = List<LatLng>.of(_vertices);
    sorted.sort((a, b) => math
        .atan2(a.latitude - cLat, a.longitude - cLon)
        .compareTo(math.atan2(b.latitude - cLat, b.longitude - cLon)));
    return sorted;
  }

  void _onTap(LatLng latlng) {
    setState(() {
      if (_mode == 'circle') {
        _center = latlng;
      } else {
        _vertices.add(latlng);
      }
    });
  }

  Future<void> _pickTime(bool from) async {
    final initial = (from ? _from : _to) ?? TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('Podaj nazwę strefy');
      return;
    }
    if (_windowEnabled && (_from == null || _to == null)) {
      _snack('Ustaw obie godziny okna aktywności (od i do)');
      return;
    }

    final body = <String, dynamic>{
      'name': name,
      'device_id': _deviceId,
      'type': _mode,
      'alert_on_enter': _alertEnter,
      'alert_on_exit': _alertExit,
      'active_from': _windowEnabled ? _fmtTime(_from!) : null,
      'active_to': _windowEnabled ? _fmtTime(_to!) : null,
    };
    if (_mode == 'circle') {
      if (_center == null) {
        _snack('Stuknij w mapę, aby wskazać środek okręgu');
        return;
      }
      body['center_lat'] = _center!.latitude;
      body['center_lon'] = _center!.longitude;
      body['radius_m'] = _radiusM;
    } else {
      if (_vertices.length < 3) {
        _snack('Wielokąt wymaga co najmniej 3 wierzchołków');
        return;
      }
      body['polygon'] = [
        for (final v in _orderedVertices) [v.latitude, v.longitude],
      ];
    }

    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await ApiClient.instance.createGeofence(body);
      } else {
        await ApiClient.instance.updateGeofence(widget.existing!.id, body);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack('Błąd: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _conditionsCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Alarm przy wejściu'),
            value: _alertEnter,
            onChanged: (v) => setState(() => _alertEnter = v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('Alarm przy wyjściu'),
            value: _alertExit,
            onChanged: (v) => setState(() => _alertExit = v),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('Aktywna tylko w wybranych godzinach'),
            value: _windowEnabled,
            onChanged: (v) => setState(() => _windowEnabled = v),
          ),
          if (_windowEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(
                          _from == null ? 'od...' : 'od ${_fmtTime(_from!)}'),
                      onPressed: () => _pickTime(true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('–'),
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 18),
                      label:
                          Text(_to == null ? 'do...' : 'do ${_fmtTime(_to!)}'),
                      onPressed: () => _pickTime(false),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final circles = <Circle>{
      if (_mode == 'circle' && _center != null)
        Circle(
          circleId: const CircleId('draft'),
          center: _center!,
          radius: _radiusM,
          fillColor: scheme.tertiary.withOpacity(0.18),
          strokeColor: scheme.tertiary,
          strokeWidth: 2,
        ),
    };
    final polygons = <Polygon>{
      if (_mode == 'polygon' && _vertices.length >= 3)
        Polygon(
          polygonId: const PolygonId('draft'),
          points: _orderedVertices,
          fillColor: scheme.tertiary.withOpacity(0.18),
          strokeColor: scheme.tertiary,
          strokeWidth: 2,
        ),
    };
    final polylines = <Polyline>{
      if (_mode == 'polygon' && _vertices.length == 2)
        Polyline(
          polylineId: const PolylineId('draft-line'),
          points: _vertices,
          color: scheme.tertiary,
          width: 3,
        ),
    };
    final markers = <Marker>{
      for (var i = 0; i < _vertices.length; i++)
        Marker(
          markerId: MarkerId('v$i'),
          position: _vertices[i],
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange),
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.existing == null ? 'Nowa geostrefa' : 'Edycja strefy'),
        actions: [
          IconButton(
            tooltip: 'Zapisz',
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: _initialCam,
              onTap: _onTap,
              markers: markers,
              circles: circles,
              polygons: polygons,
              polylines: polylines,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              padding: const EdgeInsets.only(bottom: 150),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.45,
            minChildSize: 0.16,
            maxChildSize: 0.9,
            builder: (ctx, scroll) => Material(
              elevation: 8,
              clipBehavior: Clip.antiAlias,
              color: scheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _name,
                    decoration:
                        const InputDecoration(labelText: 'Nazwa strefy'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'circle',
                                label: Text('Okrąg'),
                                icon: Icon(Icons.circle_outlined)),
                            ButtonSegment(
                                value: 'polygon',
                                label: Text('Wielokąt'),
                                icon: Icon(Icons.pentagon_outlined)),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (s) => setState(() {
                            _mode = s.first;
                            _center = null;
                            _vertices.clear();
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownMenu<int?>(
                    initialSelection: _deviceId,
                    label: const Text('Dotyczy urządzenia'),
                    expandedInsets: EdgeInsets.zero,
                    onSelected: (v) => setState(() => _deviceId = v),
                    dropdownMenuEntries: [
                      const DropdownMenuEntry<int?>(
                          value: null, label: 'Wszystkie urządzenia'),
                      for (final d in widget.devices)
                        DropdownMenuEntry<int?>(value: d.id, label: d.name),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (_mode == 'circle')
                    Row(
                      children: [
                        const Text('Promień'),
                        Expanded(
                          child: Slider(
                            value: _radiusM,
                            min: 50,
                            max: 2000,
                            divisions: 39,
                            label: '${_radiusM.toStringAsFixed(0)} m',
                            onChanged: (v) => setState(() => _radiusM = v),
                          ),
                        ),
                        Text('${_radiusM.toStringAsFixed(0)} m'),
                      ],
                    ),
                  if (_mode == 'polygon')
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            'Wierzchołki: ${_vertices.length}'),
                        TextButton.icon(
                          onPressed: _vertices.isEmpty
                              ? null
                              : () =>
                                  setState(() => _vertices.removeLast()),
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Cofnij'),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Text('Warunki alarmu',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _conditionsCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
