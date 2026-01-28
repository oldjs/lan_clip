import 'dart:io';

import 'package:device_policy_manager/device_policy_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'clipboard_service.dart';

class PhoneControlService {
  static const String allowPcLockKey = 'allow_pc_lock_phone';

  /// 是否允许电脑控制锁屏
  static Future<bool> isPcLockAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(allowPcLockKey) ?? false;
  }

  /// 设置是否允许电脑控制锁屏
  static Future<void> setPcLockAllowed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(allowPcLockKey, value);
  }

  /// 是否已授予设备管理员权限
  static Future<bool> isAdminGranted() async {
    if (!Platform.isAndroid) return false;
    return DevicePolicyManager.isPermissionGranted();
  }

  /// 请求设备管理员权限
  static Future<bool> requestAdminPermission() async {
    if (!Platform.isAndroid) return false;
    return DevicePolicyManager.requestPermession(
      'LAN Clip 需要设备管理员权限才能锁屏',
    );
  }

  /// 执行锁屏
  static Future<bool> lockNow() async {
    if (!Platform.isAndroid) return false;
    try {
      await DevicePolicyManager.lockNow();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 处理来自电脑的手机控制指令
  static Future<bool> handleCommand(String command) async {
    if (command != cmdPhoneLock) return false;

    final allowed = await isPcLockAllowed();
    if (!allowed) return true;

    final granted = await isAdminGranted();
    if (!granted) return true;

    await lockNow();
    return true;
  }
}
