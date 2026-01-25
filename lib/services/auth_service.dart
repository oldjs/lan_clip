import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 密码认证服务
class AuthService {
  static const String _passwordHashKey = 'password_hash';
  static const String _passwordEnabledKey = 'password_enabled';
  
  /// 计算 SHA-256 哈希
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  /// 保存密码（存储哈希）
  static Future<void> setPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final hash = hashPassword(password);
    await prefs.setString(_passwordHashKey, hash);
    await prefs.setBool(_passwordEnabledKey, true);
  }
  
  /// 清除密码
  static Future<void> clearPassword() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_passwordHashKey);
    await prefs.setBool(_passwordEnabledKey, false);
  }
  
  /// 获取存储的密码哈希
  static Future<String?> getPasswordHash() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_passwordHashKey);
  }
  
  /// 检查是否启用了密码
  static Future<bool> isPasswordEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_passwordEnabledKey) ?? false;
  }
  
  /// 验证密码哈希是否匹配
  static Future<bool> verifyHash(String hash) async {
    final storedHash = await getPasswordHash();
    return storedHash != null && storedHash == hash;
  }
  
  /// 验证明文密码
  static Future<bool> verifyPassword(String password) async {
    final hash = hashPassword(password);
    return verifyHash(hash);
  }
}
