import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  String? _token;

  bool get isLoggedIn => _token != null;

  Future<void> loadToken() async {
    _token = (await SharedPreferences.getInstance()).getString('jwt');
  }

  Future<void> _saveToken(String token) async {
    _token = token;
    await (await SharedPreferences.getInstance()).setString('jwt', token);
  }

  Future<void> logout() async {
    _token = null;
    await (await SharedPreferences.getInstance()).remove('jwt');
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<dynamic> _request(String method, String path, {Object? body}) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    final encoded = body == null ? null : jsonEncode(body);
    late http.Response r;
    try {
      switch (method) {
      case 'GET':
        r = await http.get(uri, headers: _headers);
      case 'POST':
        r = await http.post(uri, headers: _headers, body: encoded);
      case 'PUT':
        r = await http.put(uri, headers: _headers, body: encoded);
      case 'DELETE':
        r = await http.delete(uri, headers: _headers);
      default:
        throw ArgumentError('Nieobsługiwana metoda: $method');
      }
    } on ApiException {
      rethrow;
    } on ArgumentError {
      rethrow;
    } catch (_) {
      throw ApiException(
          0, 'Brak połączenia z serwerem - sprawdź internet i adres API');
    }
    if (r.statusCode >= 400) {
      throw ApiException(r.statusCode, _friendlyError(r));
    }
    if (r.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  String _friendlyError(http.Response r) {
    dynamic detail;
    try {
      detail = jsonDecode(utf8.decode(r.bodyBytes))['detail'];
    } catch (_) {
      return 'Błąd serwera (${r.statusCode}) - spróbuj ponownie';
    }
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is List) {
      for (final e in detail) {
        final loc = (e is Map ? e['loc'] : null)?.toString() ?? '';
        if (loc.contains('email')) {
          return 'Podaj poprawny adres e-mail (np. jan@przyklad.pl)';
        }
        if (loc.contains('password')) {
          return 'Hasło musi mieć co najmniej 8 znaków';
        }
        if (loc.contains('device_key')) {
          return 'Nieprawidłowy kod urządzenia - zeskanuj naklejkę jeszcze raz';
        }
        if (loc.contains('name')) {
          return 'Podaj nazwę (od 1 do 100 znaków)';
        }
      }
      return 'Formularz zawiera nieprawidłowe dane';
    }
    return 'Błąd serwera (${r.statusCode}) - spróbuj ponownie';
  }

  Future<void> register(String email, String password) async {
    final j = await _request('POST', '/auth/register',
        body: {'email': email, 'password': password});
    await _saveToken(j['access_token'] as String);
  }

  Future<void> login(String email, String password) async {
    final j = await _request('POST', '/auth/login',
        body: {'email': email, 'password': password});
    await _saveToken(j['access_token'] as String);
  }

  Future<List<Device>> devices() async {
    final j = await _request('GET', '/devices') as List;
    return j.map((e) => Device.fromJson(e as Map<String, dynamic>)).toList();
  }


  Future<void> deleteDevice(int id) => _request('DELETE', '/devices/$id');

  Future<void> updateDeviceConfig(int id, int reportIntervalS) =>
      _request('PUT', '/devices/$id/config',
          body: {'report_interval_s': reportIntervalS});

  Future<Device> claimDevice(String deviceKey, String name) async {
    final j = await _request('POST', '/devices/claim',
        body: {'device_key': deviceKey, 'name': name});
    return Device.fromJson(j as Map<String, dynamic>);
  }

  Future<LocationPoint?> latestLocation(int deviceId) async {
    final j = await _request('GET', '/devices/$deviceId/locations/latest');
    if (j == null) return null;
    return LocationPoint.fromJson(j as Map<String, dynamic>);
  }

  Future<List<LocationPoint>> locationHistory(int deviceId,
      {int limit = 300, DateTime? from, DateTime? to}) async {
    var path = '/devices/$deviceId/locations?limit=$limit';
    if (from != null) {
      path += '&from=${Uri.encodeQueryComponent(from.toUtc().toIso8601String())}';
    }
    if (to != null) {
      path += '&to=${Uri.encodeQueryComponent(to.toUtc().toIso8601String())}';
    }
    final j = await _request('GET', path) as List;
    return j
        .map((e) => LocationPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<LocationDay>> locationDays(int deviceId) async {
    final j =
        await _request('GET', '/devices/$deviceId/locations/days') as List;
    return j
        .map((e) => LocationDay.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Geofence>> geofences() async {
    final j = await _request('GET', '/geofences') as List;
    return j.map((e) => Geofence.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> createGeofence(Map<String, dynamic> body) =>
      _request('POST', '/geofences', body: body);

  Future<void> updateGeofence(int id, Map<String, dynamic> body) =>
      _request('PUT', '/geofences/$id', body: body);

  Future<void> deleteGeofence(int id) => _request('DELETE', '/geofences/$id');

  Future<List<ZoneEvent>> events({int limit = 100}) async {
    final j = await _request('GET', '/events?limit=$limit') as List;
    return j.map((e) => ZoneEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> deleteEvent(int id) => _request('DELETE', '/events/$id');

  Future<List<AppNotification>> notifications({int limit = 100}) async {
    final j = await _request('GET', '/notifications?limit=$limit') as List;
    return j
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteNotification(int id) =>
      _request('DELETE', '/notifications/$id');

  Future<void> registerPushToken(String token, String platform) =>
      _request('POST', '/push/token',
          body: {'token': token, 'platform': platform});
}
