import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'light/network.dart';

/// Choices for how long the app may stay in the background before it
/// locks, in minutes.
const lockAfterChoices = [1, 5, 10, 30];

/// The default of [lockAfterChoices].
const defaultLockAfterMinutes = 5;

/// User settings, kept on the device only.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static const _serverKey = 'light_server';
  static const _lockAfterKey = 'lock_after_minutes';

  final SharedPreferencesAsync _prefs;
  String _server = defaultServers.first;
  int _lockAfterMinutes = defaultLockAfterMinutes;

  /// Loads saved settings, falling back to defaults.
  static Future<AppSettings> load({SharedPreferencesAsync? prefs}) async {
    final settings = AppSettings._(prefs ?? SharedPreferencesAsync());
    settings._server =
        await settings._prefs.getString(_serverKey) ?? defaultServers.first;
    final minutes = await settings._prefs.getInt(_lockAfterKey);
    if (lockAfterChoices.contains(minutes)) {
      settings._lockAfterMinutes = minutes!;
    }
    return settings;
  }

  /// The light server this wallet syncs from.
  String get server => _server;

  /// Uri of [server].
  Uri get serverUri => Uri.parse(_server);

  /// Saves a new light server. Only `https` (or `http` on a loopback
  /// address, for a node on the same machine) is accepted.
  Future<void> setServer(String value) async {
    final error = validateServer(value);
    if (error != null) throw ArgumentError(error);
    _server = value.trim();
    await _prefs.setString(_serverKey, _server);
    notifyListeners();
  }

  /// Minutes in the background before the wallet locks, one of
  /// [lockAfterChoices].
  int get lockAfterMinutes => _lockAfterMinutes;

  /// [lockAfterMinutes] as a duration.
  Duration get lockAfter => Duration(minutes: _lockAfterMinutes);

  /// Saves how long the app may stay in the background before it locks.
  Future<void> setLockAfterMinutes(int minutes) async {
    if (!lockAfterChoices.contains(minutes)) {
      throw ArgumentError('Choose one of $lockAfterChoices minutes');
    }
    _lockAfterMinutes = minutes;
    await _prefs.setInt(_lockAfterKey, minutes);
    notifyListeners();
  }
}

/// Why `value` is not a usable light server URL, or `null` if it is.
String? validateServer(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasAuthority) {
    return 'Enter a full URL, like https://light.example';
  }
  final loopback = uri.host == 'localhost' || uri.host == '127.0.0.1';
  if (uri.scheme == 'https' || (uri.scheme == 'http' && loopback)) return null;
  return 'Use https (http only for a node on this device)';
}
