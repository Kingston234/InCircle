import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../api/api_client.dart';
import '../models.dart';

class RouteReplayScreen extends StatefulWidget {
  final int deviceId;
  final String deviceName;
  final DateTime day;

  const RouteReplayScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.day,
  });

  @override
  State<RouteReplayScreen> createState() => _RouteReplayScreenState();
}

class _RouteReplayScreenState extends State<RouteReplayScreen> {
  GoogleMapController? _controller;
  List<LocationPoint> _pts = [];
  bool _loading = true;

  Timer? _timer;
  bool _playing = false;
  bool _wasPlaying = false;
  int _idx = 0;
  double _segT = 0.0;
  LatLng? _shown;
  static const _tick = Duration(milliseconds: 40);
  late double _segMs;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_tick, (_) => _animate());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final start = DateTime(widget.day.year, widget.day.month, widget.day.day);
    final end = start.add(const Duration(days: 1));
    try {
      final pts = await ApiClient.instance.locationHistory(widget.deviceId,
          limit: 2000, from: start, to: end);
      if (!mounted) return;
      final asc = pts.reversed.toList();
      setState(() {
        _pts = asc;
        _loading = false;
        if (asc.isNotEmpty) _shown = LatLng(asc.first.lat, asc.first.lon);
        _segMs = asc.length > 1
            ? (20000 / (asc.length - 1)).clamp(80.0, 600.0)
            : 500.0;
      });
      _fitCamera(asc);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fitCamera(List<LocationPoint> pts) {
    if (pts.isEmpty || _controller == null) return;
    double minLat = pts.first.lat, maxLat = pts.first.lat;
    double minLon = pts.first.lon, maxLon = pts.first.lon;
    for (final p in pts) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    _controller!.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
            southwest: LatLng(minLat, minLon),
            northeast: LatLng(maxLat, maxLon)),
        60));
  }

  void _togglePlay() {
    if (_pts.length < 2) return;
    setState(() {
      if (!_playing && _idx >= _pts.length - 1) _restart(keepPaused: true);
      _playing = !_playing;
    });
  }

  void _restart({bool keepPaused = false}) {
    _idx = 0;
    _segT = 0.0;
    _shown = LatLng(_pts.first.lat, _pts.first.lon);
    if (!keepPaused) _playing = false;
    setState(() {});
  }

  void _animate() {
    if (!_playing || _pts.length < 2 || _idx >= _pts.length - 1) return;
    _segT += _tick.inMilliseconds / _segMs;
    while (_segT >= 1.0 && _idx < _pts.length - 1) {
      _segT -= 1.0;
      _idx++;
    }
    if (_idx >= _pts.length - 1) {
      setState(() {
        _shown = LatLng(_pts.last.lat, _pts.last.lon);
        _playing = false;
        _idx = _pts.length - 1;
      });
      return;
    }
    final a = _pts[_idx];
    final b = _pts[_idx + 1];
    final t = _segT.clamp(0.0, 1.0);
    setState(() {
      _shown = LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
    });
  }

  Widget _playerCard(BuildContext context, LocationPoint? current) {
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
        child: Row(
          children: [
            IconButton.filled(
              onPressed: _togglePlay,
              iconSize: 28,
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
            ),
            Expanded(
              child: _pts.length < 2
                  ? const SizedBox.shrink()
                  : Slider(
                      value: (_idx + _segT)
                          .clamp(0.0, (_pts.length - 1).toDouble()),
                      max: (_pts.length - 1).toDouble(),
                      onChangeStart: (_) {
                        _wasPlaying = _playing;
                        setState(() => _playing = false);
                      },
                      onChanged: (v) => setState(() {
                        _idx = v.floor().clamp(0, _pts.length - 2);
                        _segT = (v - _idx).clamp(0.0, 1.0);
                        final a = _pts[_idx];
                        final b = _pts[_idx + 1];
                        _shown = LatLng(
                          a.lat + (b.lat - a.lat) * _segT,
                          a.lon + (b.lon - a.lon) * _segT,
                        );
                      }),
                      onChangeEnd: (_) =>
                          setState(() => _playing = _wasPlaying),
                    ),
            ),
            Text(
              current == null ? '' : formatTime(current.recordedAt),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current =
        _pts.isEmpty ? null : _pts[math.min(_idx, _pts.length - 1)];
    return Scaffold(
      appBar: AppBar(
          title: Text('${widget.deviceName} - ${dayLabel(widget.day)}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pts.isEmpty
              ? const Center(child: Text('Brak pozycji z tego dnia'))
              : Stack(
                  children: [
                    Positioned.fill(
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                            target: LatLng(_pts.first.lat, _pts.first.lon),
                            zoom: 14),
                        onMapCreated: (c) {
                          _controller = c;
                          _fitCamera(_pts);
                        },
                        polylines: {
                          Polyline(
                            polylineId: const PolylineId('route'),
                            points: [
                              for (final p in _pts) LatLng(p.lat, p.lon)
                            ],
                            color:
                                Theme.of(context).colorScheme.primary,
                            width: 4,
                          ),
                        },
                        markers: {
                          Marker(
                            markerId: const MarkerId('start'),
                            position:
                                LatLng(_pts.first.lat, _pts.first.lon),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueGreen),
                            infoWindow: const InfoWindow(title: 'Start'),
                          ),
                          Marker(
                            markerId: const MarkerId('end'),
                            position: LatLng(_pts.last.lat, _pts.last.lon),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueRed),
                            infoWindow: const InfoWindow(title: 'Meta'),
                          ),
                          if (_shown != null)
                            Marker(
                              markerId: const MarkerId('replay'),
                              position: _shown!,
                              zIndex: 10,
                            ),
                        },
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        padding: const EdgeInsets.only(bottom: 88),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: _playerCard(context, current),
                    ),
                  ],
                ),
    );
  }
}
