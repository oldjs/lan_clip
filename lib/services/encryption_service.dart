import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 端到端加密服务
/// 使用 AES-256-GCM 加密，PBKDF2 密钥派生
class EncryptionService {
  static const String _encryptionEnabledKey = 'encryption_enabled';
  
  // 加密协议版本前缀
  static const String _encryptedPrefix = 'ENC:1:';
  
  // PBKDF2 参数
  static const int _pbkdf2Iterations = 100000;
  static const int _keyLength = 32; // 256 bits
  static const int _nonceLength = 12;
  
  // 缓存的加密密钥
  static SecretKey? _cachedKey;
  static String? _cachedPassword;
  
  /// 检查是否启用加密
  static Future<bool> isEncryptionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_encryptionEnabledKey) ?? false;
  }
  
  /// 设置加密开关
  static Future<void> setEncryptionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_encryptionEnabledKey, enabled);
    if (!enabled) {
      // 关闭加密时清除缓存
      _cachedKey = null;
      _cachedPassword = null;
    }
  }
  
  /// 获取固定的应用级 salt
  /// 注意：使用固定 salt 是因为需要两端派生相同密钥
  /// 安全性由用户密码的强度保证
  static Uint8List _getFixedSalt() {
    // 固定 salt: "LAN_CLIP_E2E_V1!" 的 UTF-8 编码（16 字节）
    return Uint8List.fromList(
      'LAN_CLIP_E2E_V1!'.codeUnits,
    );
  }
  
  /// 从密码派生加密密钥
  static Future<SecretKey> deriveKey(String password) async {
    // 使用缓存避免重复计算
    if (_cachedKey != null && _cachedPassword == password) {
      return _cachedKey!;
    }
    
    final salt = _getFixedSalt();
    
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: _keyLength * 8,
    );
    
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    
    _cachedKey = key;
    _cachedPassword = password;
    
    return key;
  }
  
  /// 加密数据
  /// 返回格式: ENC:1:<base64(nonce + ciphertext + mac)>
  static Future<String> encrypt(String plaintext, SecretKey key) async {
    final algorithm = AesGcm.with256bits();
    
    // 生成随机 nonce
    final nonce = algorithm.newNonce();
    
    // 加密
    final secretBox = await algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    
    // 组合: nonce + ciphertext + mac
    final nonceBytes = Uint8List.fromList(nonce);
    final cipherBytes = Uint8List.fromList(secretBox.cipherText);
    final macBytes = Uint8List.fromList(secretBox.mac.bytes);
    
    final combined = Uint8List(
      nonceBytes.length + cipherBytes.length + macBytes.length,
    );
    
    int offset = 0;
    combined.setRange(offset, offset + nonceBytes.length, nonceBytes);
    offset += nonceBytes.length;
    combined.setRange(offset, offset + cipherBytes.length, cipherBytes);
    offset += cipherBytes.length;
    combined.setRange(offset, offset + macBytes.length, macBytes);
    
    return '$_encryptedPrefix${base64Encode(combined)}';
  }
  
  /// 解密数据
  static Future<String?> decrypt(String encrypted, SecretKey key) async {
    // 检查前缀
    if (!encrypted.startsWith(_encryptedPrefix)) {
      return null;
    }
    
    try {
      final base64Data = encrypted.substring(_encryptedPrefix.length);
      final combined = base64Decode(base64Data);
      
      // 解析: nonce(12) + ciphertext + mac(16)
      if (combined.length < _nonceLength + 16) {
        return null;
      }
      
      final nonce = combined.sublist(0, _nonceLength);
      final cipherText = combined.sublist(_nonceLength, combined.length - 16);
      final mac = combined.sublist(combined.length - 16);
      
      final algorithm = AesGcm.with256bits();
      
      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(mac),
      );
      
      final decrypted = await algorithm.decrypt(
        secretBox,
        secretKey: key,
      );
      
      return utf8.decode(decrypted);
    } catch (e) {
      // 解密失败（密钥错误或数据损坏）
      return null;
    }
  }
  
  /// 检查消息是否已加密
  static bool isEncrypted(String message) {
    return message.startsWith(_encryptedPrefix);
  }
  
  /// 清除缓存的密钥
  static void clearCache() {
    _cachedKey = null;
    _cachedPassword = null;
  }
  
  /// 重置加密设置
  static Future<void> resetEncryption() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_encryptionEnabledKey, false);
    clearCache();
  }
}
