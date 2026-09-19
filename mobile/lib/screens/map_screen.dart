import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../api/api_client.dart';
import '../config.dart';
import '../models.dart';

class MapTab extends StatefulWidget {
  final List<Device> devices;
  final int? selectedDeviceId;
  final ValueChanged<int?> onDeviceChanged;
  final VoidCallback onGoToDevices;

  const MapTab({
    super.key,
    required this.devices,
    required this.selectedDeviceId,
    required this.onDeviceChanged,
    required this.onGoToDevices,
  });

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  GoogleMapController? _controller;
  Timer? _refreshTimer;
  Timer? _animTimer;

  LocationPoint? _latest;
  List<Geofence> _fences = [];
  bool _centeredOnce = false;
  bool _follow = false;

  LatLng? _shown;
  LatLng? _segStart;
  LatLng? _segEnd;
  double _segT = 1.0;
  static const _tick = Duration(milliseconds: 40);
  static const double _glideMs = 500;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(mapRefreshInterval, (_) => _refresh());
    _animTimer = Timer.periodic(_tick, (_) => _animate());
  }

  @override
  void didUpdateWidget(covariant MapTab old) {
    super.didUpdateWidget(old);
    if (old.selectedDeviceId != widget.selectedDeviceId) {
      _latest = null;
      _centeredOnce = false;
      _shown = null;
      _segStart = null;
      _segEnd = null;
      _segT = 1.0;
      _refresh();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _animTimer?.cancel();
    super.dispose();
  }

  void _centerOnLatest() {
    if (_latest != null && !_centeredOnce && _controller != null) {
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(
          LatLng(_latest!.lat, _latest!.lon), 15));
      _centeredOnce = true;
    }
  }

  void _setTarget(LatLng target) {
    if (_shown == null) {
      _shown = target;
      return;
    }
    if (_shown!.latitude == target.latitude &&
        _shown!.longitude == target.longitude) {
      return;
    }
    _segStart = _shown;
    _segEnd = target;
    _segT = 0.0;
  }

  void _animate() {
    if (_segEnd == null || _segT >= 1.0) return;
    _segT = (_segT + _tick.inMilliseconds / _glideMs).clamp(0.0, 1.0);
    final t = _segT;
    setState(() {
      _shown = LatLng(
        _segStart!.latitude + (_segEnd!.latitude - _segStart!.latitude) * t,
        _segStart!.longitude + (_segEnd!.longitude - _segStart!.longitude) * t,
      );
    });
    if (_segT >= 1.0) _segEnd = null;
  }

  Future<void> _refresh() async {
    final deviceId = widget.selectedDeviceId;
    if (deviceId == null) return;
    try {
      final results = await Future.wait([
        ApiClient.instance.latestLocation(deviceId),
        ApiClient.instance.geofences(),
      ]);
      if (!mounted) return;
      setState(() {
        _latest = results[0] as LocationPoint?;
        _fences = results[1] as List<Geofence>;
      });
      final latest = results[0] as LocationPoint?;
      if (latest != null) {
        _setTarget(LatLng(latest.lat, latest.lon));
        if (_follow) {
          _controller?.animateCamera(
              CameraUpdate.newLatLng(LatLng(latest.lat, latest.lon)));
        }
      }
      _centerOnLatest();
    } catch (_) {
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gps_off, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            Text('Nie masz jeszcze żadnego urządzenia.',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: widget.onGoToDevices,
                child: const Text('Dodaj urządzenie')),
          ],
        ),
      );
    }

    final circles = <Circle>{
      for (final f in _fences.where((f) => f.isCircle))
        Circle(
          circleId: CircleId('fence-${f.id}'),
          center: LatLng(f.centerLat!, f.centerLon!),
          radius: f.radiusM,
          fillColor: scheme.primary.withOpacity(0.12),
          strokeColor: scheme.primary,
          strokeWidth: 2,
        ),
    };
    final polygons = <Polygon>{
      for (final f in _fences.where((f) => !f.isCircle))
        Polygon(
          polygonId: PolygonId('fence-${f.id}'),
          points: [for (final p in f.polygonPoints) LatLng(p[0], p[1])],
          fillColor: scheme.primary.withOpacity(0.12),
          strokeColor: scheme.primary,
          strokeWidth: 2,
        ),
    };
    final markerPos = _shown ??
        (_latest != null ? LatLng(_latest!.lat, _latest!.lon) : null);
    final markers = <Marker>{
      if (markerPos != null)
        Marker(
          markerId: const MarkerId('latest'),
          position: markerPos,
          infoWindow: InfoWindow(
              title: 'Ostatnia pozycja',
              snippet: _latest != null
                  ? formatDateTime(_latest!.recordedAt)
                  : null),
        ),
    };

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
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: const CameraPosition(
                    target: LatLng(defaultLat, defaultLon), zoom: 13),
                onMapCreated: (c) {
                  _controller = c;
                  _centerOnLatest();
                },
                markers: markers,
                circles: circles,
                polygons: polygons,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
              ),
              if (_latest != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 14,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(blurRadius: 6, color: Colors.black12)
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(timeAgo(_latest!.recordedAt),
                              style: Theme.of(context).textTheme.bodySmall),
                          if (_latest!.speedKmh != null) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.speed,
                                size: 16,
                                color:
                                    Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                                '${_latest!.speedKmh!.toStringAsFixed(1).replaceAll('.', ',')} km/h',
                                style:
                                    Theme.of(context).textTheme.bodySmall),
                          ],
                          if (_latest!.batteryPct != null) ...[
                            const SizedBox(width: 12),
                            Icon(
                              _latest!.batteryPct! <= 20
                                  ? Icons.battery_alert
                                  : Icons.battery_full,
                              size: 16,
                              color: _latest!.batteryPct! <= 20
                                  ? scheme.error
                                  : scheme.primary,
                            ),
                            const SizedBox(width: 2),
                            Text('${_latest!.batteryPct}%',
                                style:
                                    Theme.of(context).textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 12,
                right: 12,
                child: FloatingActionButton.small(
                  heroTag: 'follow-device',
                  tooltip: _follow
                      ? 'Przestań podążać za urządzeniem'
                      : 'Podążaj za urządzeniem',
                  backgroundColor: _follow
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surface,
                  foregroundColor: _follow
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.primary,
                  onPressed: () {
                    setState(() => _follow = !_follow);
                    if (_follow && _latest != null) {
                      _controller?.animateCamera(CameraUpdate.newLatLngZoom(
                          LatLng(_latest!.lat, _latest!.lon), 15));
                    }
                  },
                  child: const Icon(Icons.my_location),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
