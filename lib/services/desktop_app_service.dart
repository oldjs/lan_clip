import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_entry.dart';
import 'windows_app_launcher.dart';

class DesktopAppService {
  static const String _storageKey = 'desktop_app_entries';

  /// 读取本地应用列表
  Future<List<AppEntry>> loadApps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return [];

    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return data
          .map((item) {
            if (item is! Map) return null;
            return AppEntry.tryFromJson(Map<String, dynamic>.from(item));
          })
          .whereType<AppEntry>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存应用列表
  Future<void> saveApps(List<AppEntry> apps) async {
    final prefs = await SharedPreferences.getInstance();
    final data = apps.map((e) => e.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(data));
  }

  /// 新增或更新应用
  Future<List<AppEntry>> upsert(AppEntry entry) async {
    final apps = await loadApps();
    final index = apps.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      apps[index] = entry;
    } else {
      apps.add(entry);
    }
    await saveApps(apps);
    return apps;
  }

  /// 删除应用
  Future<List<AppEntry>> remove(String id) async {
    final apps = await loadApps();
    apps.removeWhere((e) => e.id == id);
    await saveApps(apps);
    return apps;
  }

  /// 启动应用
  Future<bool> launchById(String id) async {
    final apps = await loadApps();
    for (final entry in apps) {
      if (entry.id == id) {
        return WindowsAppLauncher.launch(entry);
      }
    }
    return false;
  }
}
