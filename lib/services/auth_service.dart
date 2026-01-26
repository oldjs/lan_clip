import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 密码认证服务
class AuthService {
  static const String _passwordHashKey = 'password_hash';
  static const String _passwordEnabledKey = 'password_enabled';
  static const String _saltKey = 'password_salt';
  
  /// 生成 16 字节随机盐值（返回 32 字符 hex 字符串）
  static String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
  
  /// 获取存储的盐值
  static Future<String?> getSalt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_saltKey);
  }
  
  /// 存储盐值
  static Future<void> setSalt(String salt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saltKey, salt);
  }
  
  /// 计算带盐哈希: sha256(salt + password)
  static String hashPassword(String password, String salt) {
    final bytes = utf8.encode(salt + password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  /// 旧版哈希（无盐，用于兼容旧协议）
  static String hashPasswordLegacy(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  /// 保存密码（生成随机盐值并存储）
  static Future<void> setPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = generateSalt();
    final hash = hashPassword(password, salt);
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_passwordHashKey, hash);
    await prefs.setBool(_passwordEnabledKey, true);
  }
  
  /// 清除密码
  static Future<void> clearPassword() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_passwordHashKey);
    await prefs.remove(_saltKey);
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
  
  /// 验证明文密码（使用存储的盐值）
  static Future<bool> verifyPassword(String password) async {
    final salt = await getSalt();
    if (salt == null) return false;
    final hash = hashPassword(password, salt);
    return verifyHash(hash);
  }
}
