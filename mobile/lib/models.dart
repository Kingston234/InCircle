class Device {
  final int id;
  final String deviceKey;
  final String name;
  final bool isOnline;
  final int? batteryPct;
  final Map<String, dynamic>? config;
  final DateTime? lastSeenAt;

  Device({
    required this.id,
    required this.deviceKey,
    required this.name,
    required this.isOnline,
    this.batteryPct,
    this.config,
    this.lastSeenAt,
  });

  int? get reportIntervalS =>
      (config?['report_interval_s'] as num?)?.toInt();

  factory Device.fromJson(Map<String, dynamic> j) => Device(
        id: j['id'] as int,
        deviceKey: j['device_key'] as String,
        name: j['name'] as String,
        isOnline: (j['is_online'] as bool?) ?? false,
        batteryPct: (j['battery_pct'] as num?)?.toInt(),
        config: (j['config'] as Map?)?.cast<String, dynamic>(),
        lastSeenAt: j['last_seen_at'] != null
            ? DateTime.parse(j['last_seen_at'] as String).toLocal()
            : null,
      );
}

class LocationPoint {
  final double lat;
  final double lon;
  final DateTime recordedAt;
  final double? speedKmh;
  final int? batteryPct;

  LocationPoint({
    required this.lat,
    required this.lon,
    required this.recordedAt,
    this.speedKmh,
    this.batteryPct,
  });

  factory LocationPoint.fromJson(Map<String, dynamic> j) => LocationPoint(
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        recordedAt: DateTime.parse(j['recorded_at'] as String).toLocal(),
        speedKmh: (j['speed_kmh'] as num?)?.toDouble(),
        batteryPct: (j['battery_pct'] as num?)?.toInt(),
      );
}

class Geofence {
  final int id;
  final String name;
  final int? deviceId;
  final Map<String, dynamic> definition;
  final bool alertOnEnter;
  final bool alertOnExit;
  final int dwellSeconds;
  final String? activeFrom;
  final String? activeTo;

  Geofence({
    required this.id,
    required this.name,
    required this.deviceId,
    required this.definition,
    required this.alertOnEnter,
    required this.alertOnExit,
    required this.dwellSeconds,
    this.activeFrom,
    this.activeTo,
  });

  factory Geofence.fromJson(Map<String, dynamic> j) => Geofence(
        id: j['id'] as int,
        name: j['name'] as String,
        deviceId: j['device_id'] as int?,
        definition: (j['definition'] as Map).cast<String, dynamic>(),
        alertOnEnter: (j['alert_on_enter'] as bool?) ?? true,
        alertOnExit: (j['alert_on_exit'] as bool?) ?? true,
        dwellSeconds: (j['dwell_seconds'] as num?)?.toInt() ?? 0,
        activeFrom: j['active_from'] as String?,
        activeTo: j['active_to'] as String?,
      );

  bool get isCircle => definition['type'] == 'circle';

  double? get centerLat => (definition['center_lat'] as num?)?.toDouble();
  double? get centerLon => (definition['center_lon'] as num?)?.toDouble();
  double get radiusM => (definition['radius_m'] as num?)?.toDouble() ?? 0;

  List<List<double>> get polygonPoints =>
      ((definition['polygon'] as List?) ?? [])
          .map<List<double>>((p) =>
              [(p[0] as num).toDouble(), (p[1] as num).toDouble()])
          .toList();
}

class ZoneEvent {
  final int id;
  final String deviceName;
  final String geofenceName;
  final String eventType;
  final DateTime occurredAt;

  ZoneEvent({
    required this.id,
    required this.deviceName,
    required this.geofenceName,
    required this.eventType,
    required this.occurredAt,
  });

  factory ZoneEvent.fromJson(Map<String, dynamic> j) => ZoneEvent(
        id: j['id'] as int,
        deviceName: j['device_name'] as String,
        geofenceName: j['geofence_name'] as String,
        eventType: j['event_type'] as String,
        occurredAt: DateTime.parse(j['occurred_at'] as String).toLocal(),
      );
}

class LocationDay {
  final DateTime day;
  final int count;
  final double distanceM;
  final double durationS;
  final double? maxSpeedKmh;
  LocationDay({
    required this.day,
    required this.count,
    required this.distanceM,
    required this.durationS,
    this.maxSpeedKmh,
  });
  factory LocationDay.fromJson(Map<String, dynamic> j) => LocationDay(
        day: DateTime.parse(j['day'] as String),
        count: j['count'] as int,
        distanceM: (j['distance_m'] as num?)?.toDouble() ?? 0,
        durationS: (j['duration_s'] as num?)?.toDouble() ?? 0,
        maxSpeedKmh: (j['max_speed_kmh'] as num?)?.toDouble(),
      );
}

String formatDistance(double meters) {
  if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
  return '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
}

String formatDuration(double seconds) {
  final s = seconds.round();
  if (s < 60) return '$s s';
  final min = (s / 60).round();
  if (min < 60) return '$min min';
  final h = min ~/ 60;
  final rest = (min % 60).toString().padLeft(2, '0');
  return '$h h $rest min';
}

class AppNotification {
  final int id;
  final String title;
  final String body;
  final int? zoneEventId;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.zoneEventId,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as int,
        title: j['title'] as String,
        body: j['body'] as String,
        zoneEventId: j['zone_event_id'] as int?,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

String timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 15) return 'przed chwilą';
  if (diff.inSeconds < 60) return '${diff.inSeconds} s temu';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min temu';
  String two(int n) => n.toString().padLeft(2, '0');
  if (diff.inHours < 24) return '${two(dt.hour)}:${two(dt.minute)}';
  return dayLabel(dt);
}

String formatTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}

String dayLabel(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'Dzisiaj';
  if (diff == 1) return 'Wczoraj';
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

String formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}.${two(dt.month)}.${dt.year} '
      '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}
