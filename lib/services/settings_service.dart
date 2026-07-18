import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A saved panel connection (URL + API key).
class PanelProfile {
  final String name;
  final String url;
  final String apiKey;

  PanelProfile({required this.name, required this.url, required this.apiKey});

  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'apiKey': apiKey};

  factory PanelProfile.fromJson(Map<String, dynamic> json) => PanelProfile(
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
      );
}

class SettingsService {
  static const _profilesKey = 'panel_profiles';
  static const _activeIndexKey = 'active_profile_index';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  static Future<SettingsService> load() async =>
      SettingsService(await SharedPreferences.getInstance());

  List<PanelProfile> get profiles {
    final raw = _prefs.getString(_profilesKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => PanelProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  int get activeIndex {
    final i = _prefs.getInt(_activeIndexKey) ?? 0;
    final count = profiles.length;
    if (count == 0) return -1;
    return i.clamp(0, count - 1);
  }

  PanelProfile? get activeProfile {
    final i = activeIndex;
    return i < 0 ? null : profiles[i];
  }

  Future<void> _saveProfiles(List<PanelProfile> list) async {
    await _prefs.setString(
        _profilesKey, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<void> addProfile(PanelProfile profile) async {
    final list = profiles..add(profile);
    await _saveProfiles(list);
    await setActiveIndex(list.length - 1);
  }

  Future<void> updateProfile(int index, PanelProfile profile) async {
    final list = profiles;
    if (index < 0 || index >= list.length) return;
    list[index] = profile;
    await _saveProfiles(list);
  }

  Future<void> deleteProfile(int index) async {
    final list = profiles;
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await _saveProfiles(list);
    final active = _prefs.getInt(_activeIndexKey) ?? 0;
    if (active >= list.length) {
      await setActiveIndex(list.isEmpty ? 0 : list.length - 1);
    }
  }

  Future<void> setActiveIndex(int index) async {
    await _prefs.setInt(_activeIndexKey, index);
  }
}
