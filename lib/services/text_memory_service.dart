import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 文本记忆数据模型
class TextMemory {
  final String id;
  final String content;
  final DateTime createdAt;

  TextMemory({
    required this.id,
    required this.content,
    required this.createdAt,
  });

  /// 从 JSON 转换
  factory TextMemory.fromJson(Map<String, dynamic> json) {
    return TextMemory(
      id: json['id'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

/// 文本记忆服务，用于本地存储文本记忆
class TextMemoryService {
  static const String _storageKey = 'text_memories';
  final _uuid = const Uuid();

  /// 强制重新加载 SharedPreferences（用于跨进程同步）
  Future<void> reload() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
  }

  /// 获取所有记忆，按创建时间倒序排列
  Future<List<TextMemory>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // 确保读取最新数据
    final String? memoriesJson = prefs.getString(_storageKey);
    
    if (memoriesJson == null) {
      return [];
    }

    try {
      final List<dynamic> decoded = jsonDecode(memoriesJson);
      final memories = decoded
          .map((item) => TextMemory.fromJson(item as Map<String, dynamic>))
          .toList();
      
      // 按创建时间倒序排列
      memories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return memories;
    } catch (e) {
      // 如果解析失败，可能数据格式已更改，返回空列表
      return [];
    }
  }

  /// 添加新记忆
  Future<void> add(String content) async {
    if (content.isEmpty) return;

    final memories = await getAll();
    final newMemory = TextMemory(
      id: _uuid.v4(),
      content: content,
      createdAt: DateTime.now(),
    );

    memories.add(newMemory);
    await _saveAll(memories);
  }

  /// 删除指定 ID 的记忆
  Future<void> delete(String id) async {
    final memories = await getAll();
    memories.removeWhere((item) => item.id == id);
    await _saveAll(memories);
  }

  /// 清空所有记忆
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// 获取记忆总数
  Future<int> getCount() async {
    final memories = await getAll();
    return memories.length;
  }

  /// 内部方法：保存所有记忆到本地存储
  Future<void> _saveAll(List<TextMemory> memories) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(
      memories.map((item) => item.toJson()).toList(),
    );
    await prefs.setString(_storageKey, encoded);
  }
}
