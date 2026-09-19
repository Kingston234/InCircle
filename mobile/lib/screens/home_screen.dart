import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../models.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/theme_controller.dart';
import 'devices_screen.dart';
import 'events_screen.dart';
import 'geofences_screen.dart';
import 'history_screen.dart';
import 'login_screen.dart';
import 'map_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  List<Device> _devices = [];
  int? _selectedDeviceId;
  Timer? _eventTimer;
  int? _lastEventId;
  bool _fcmActive = false;
  static const _lastEventKey = 'last_event_id';

  static const _titles = ['Mapa', 'Historia tras', 'Geostrefy', 'Zdarzenia', 'Urządzenia'];

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _fcmActive = await PushService.init();
    await _initEventWatcher();
  }

  @override
  void dispose() {
    _eventTimer?.cancel();
    super.dispose();
  }

  Future<void> _initEventWatcher() async {
    await NotificationService.init();
    _lastEventId = (await SharedPreferences.getInstance()).getInt(_lastEventKey);
    await _checkNewEvents();
    _eventTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkNewEvents();
      _loadDevices(silent: true);
    });
  }

  Future<void> _checkNewEvents() async {
    try {
      final events = await ApiClient.instance.events(limit: 20);
      if (events.isEmpty) return;
      final newestId = events.first.id;
      final last = _lastEventId;
      if (!_fcmActive && last != null && newestId > last) {
        for (final e in events.where((e) => e.id > last).toList().reversed) {
          final enter = e.eventType == 'ENTER';
          NotificationService.show(
              e.id,
              '${e.deviceName}: ${enter ? 'wejście do' : 'wyjście ze'} strefy',
              'Strefa „${e.geofenceName}” · ${formatTime(e.occurredAt).substring(0, 5)}');
        }
      }
      if (last == null || newestId > last) {
        _lastEventId = newestId;
        (await SharedPreferences.getInstance())
            .setInt(_lastEventKey, newestId);
      }
    } catch (_) {
    }
  }

  Future<void> _loadDevices({bool silent = false}) async {
    try {
      final devices = await ApiClient.instance.devices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        if (devices.isNotEmpty &&
            !devices.any((d) => d.id == _selectedDeviceId)) {
          _selectedDeviceId = devices.first.id;
        }
        if (devices.isEmpty) _selectedDeviceId = null;
      });
    } catch (e) {
      if (silent || !mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _themeDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Motyw aplikacji'),
        children: [
          for (final (mode, label, icon) in const [
            (ThemeMode.system, 'Systemowy', Icons.brightness_auto),
            (ThemeMode.light, 'Jasny', Icons.light_mode_outlined),
            (ThemeMode.dark, 'Ciemny', Icons.dark_mode_outlined),
          ])
            RadioListTile<ThemeMode>(
              value: mode,
              groupValue: ThemeController.mode.value,
              secondary: Icon(icon),
              title: Text(label),
              onChanged: (v) {
                if (v != null) ThemeController.set(v);
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await ApiClient.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Widget _body() {
    switch (_tab) {
      case 0:
        return MapTab(
          devices: _devices,
          selectedDeviceId: _selectedDeviceId,
          onDeviceChanged: (id) => setState(() => _selectedDeviceId = id),
          onGoToDevices: () => setState(() => _tab = 4),
        );
      case 1:
        return HistoryTab(
          devices: _devices,
          selectedDeviceId: _selectedDeviceId,
          onDeviceChanged: (id) => setState(() => _selectedDeviceId = id),
        );
      case 2:
        return GeofencesTab(devices: _devices);
      case 3:
        return const EventsTab();
      default:
        return DevicesTab(devices: _devices, onChanged: _loadDevices);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (v) {
              if (v == 'theme') {
                _themeDialog();
              } else if (v == 'logout') {
                _logout();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(Icons.brightness_6_outlined),
                    SizedBox(width: 12),
                    Text('Motyw'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 12),
                    Text('Wyloguj'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _body(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map), label: 'Mapa'),
          NavigationDestination(icon: Icon(Icons.route), label: 'Historia'),
          NavigationDestination(icon: Icon(Icons.fence), label: 'Strefy'),
          NavigationDestination(
              icon: Icon(Icons.notifications), label: 'Zdarzenia'),
          NavigationDestination(
              icon: Icon(Icons.gps_fixed), label: 'Urządzenia'),
        ],
      ),
    );
  }
}
