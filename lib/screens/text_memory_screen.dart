import 'package:flutter/material.dart';
import '../models/device.dart';
import '../services/text_memory_service.dart';
import '../services/socket_service.dart';

/// 文本记忆页面：显示和管理暂存的文本列表
class TextMemoryScreen extends StatefulWidget {
  final Device device;
  final String? passwordHash;

  const TextMemoryScreen({
    super.key,
    required this.device,
    this.passwordHash,
  });

  @override
  State<TextMemoryScreen> createState() => _TextMemoryScreenState();
}

class _TextMemoryScreenState extends State<TextMemoryScreen> {
  final TextMemoryService _memoryService = TextMemoryService();
  final SocketService _socketService = SocketService();
  List<TextMemory> _memories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  /// 加载暂存列表
  Future<void> _loadMemories() async {
    setState(() => _isLoading = true);
    final list = await _memoryService.getAll();
    setState(() {
      _memories = list;
      _isLoading = false;
    });
  }

  /// 格式化时间: MM-dd HH:mm
  String _formatDate(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$m-$d $h:$min';
  }

  /// 发送单条消息
  Future<void> _sendMemory(TextMemory memory) async {
    final result = await _socketService.sendMessage(
      widget.device.ip,
      widget.device.port,
      memory.content,
      passwordHash: widget.passwordHash,
    );

    if (result.success) {
      await _memoryService.delete(memory.id);
      _loadMemories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('发送成功')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: ${result.error}')),
        );
      }
    }
  }

  /// 发送所有消息
  Future<void> _sendAll() async {
    if (_memories.isEmpty) return;
    
    int successCount = 0;
    for (var memory in List.from(_memories)) {
      final result = await _socketService.sendMessage(
        widget.device.ip,
        widget.device.port,
        memory.content,
        passwordHash: widget.passwordHash,
      );
      if (result.success) {
        await _memoryService.delete(memory.id);
        successCount++;
      }
    }
    
    _loadMemories();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功发送 $successCount 条消息')),
      );
    }
  }

  /// 删除单条
  Future<void> _deleteMemory(String id) async {
    await _memoryService.delete(id);
    _loadMemories();
  }

  /// 清空所有
  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('是否删除所有暂存文本？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await _memoryService.clear();
      _loadMemories();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('文本记忆'),
        actions: [
          if (_memories.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_sweep), onPressed: _clearAll),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _memories.isEmpty
              ? _buildEmptyState()
              : _buildList(),
      bottomNavigationBar: _memories.isEmpty ? null : _buildBottomBar(colorScheme),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text('暂无暂存文本', style: TextStyle(color: Colors.grey, fontSize: 16)),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _memories.length,
      itemBuilder: (context, index) {
        final memory = _memories[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memory.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDate(memory.createdAt),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => _deleteMemory(memory.id),
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                          label: const Text('删除', style: TextStyle(color: Colors.redAccent)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _sendMemory(memory),
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('发送'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 10, offset: const Offset(0, -5)),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _clearAll,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('清空'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: _sendAll,
                child: const Text('全部发送'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
