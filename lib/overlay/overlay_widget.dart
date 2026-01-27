import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';
import '../services/text_memory_service.dart';
import '../services/socket_service.dart';
import '../services/encryption_service.dart';

/// 悬浮窗 UI 组件，支持折叠态和展开态
class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> {
  bool _isExpanded = false;
  final TextEditingController _textController = TextEditingController();
  final TextMemoryService _memoryService = TextMemoryService();
  final SocketService _socketService = SocketService();
  
  Map<String, dynamic>? _selectedDevice;
  int _memoryCount = 0;
  bool _showMemoryList = false;
  List<TextMemory> _memories = [];
  
  // 加密和认证相关
  bool _encryptionEnabled = false;
  SecretKey? _encryptionKey;
  String? _passwordHash;
  
  // Toast 显示控制
  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  @override
  void dispose() {
    _textController.dispose();
    _toastEntry?.remove();
    super.dispose();
  }

  /// 加载存储的设备信息、加密设置和密码哈希
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    
    // 加载设备信息
    final deviceJson = prefs.getString('overlay_selected_device');
    if (deviceJson != null) {
      _selectedDevice = jsonDecode(deviceJson);
    }
    
    // 加载加密设置
    _encryptionEnabled = await EncryptionService.isEncryptionEnabled();
    
    // 加载密码哈希（主应用保存的）
    _passwordHash = prefs.getString('overlay_password_hash');
    
    // 如果有密码哈希且启用加密，派生密钥
    if (_passwordHash != null && _passwordHash!.isNotEmpty && _encryptionEnabled) {
      _encryptionKey = await EncryptionService.deriveKey(_passwordHash!);
    }
    
    setState(() {});
    _refreshMemoryCount();
  }

  /// 获取本地记忆总数
  Future<void> _refreshMemoryCount() async {
    await _memoryService.reload();
    final count = await _memoryService.getCount();
    setState(() {
      _memoryCount = count;
    });
  }
  
  /// 刷新记忆列表
  Future<void> _refreshMemoryList() async {
    final memories = await _memoryService.getAll();
    setState(() {
      _memories = memories;
    });
  }

  /// 切换展开/折叠状态并调整悬浮窗尺寸
  void _toggleExpand() async {
    setState(() {
      _isExpanded = !_isExpanded;
      _showMemoryList = false;
    });
    if (_isExpanded) {
      await _loadData();
      await FlutterOverlayWindow.resizeOverlay(240, 320, true);
    } else {
      // 修复: 折叠尺寸与小球实际尺寸一致 (48x48)
      await FlutterOverlayWindow.resizeOverlay(48, 48, true);
    }
  }

  /// 调用 SocketService 发送内容
  Future<void> _handleSend(String content) async {
    if (content.isEmpty) return;
    if (_selectedDevice == null) {
      _showToast('请先在主应用选择设备');
      return;
    }

    final String ip = _selectedDevice!['ip'];
    final int port = _selectedDevice!['port'];
    
    // 设置加密
    _socketService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);
    
    final result = await _socketService.sendMessage(
      ip, 
      port, 
      content,
      passwordHash: _passwordHash,
    );
    
    if (result.success) {
      _textController.clear();
      _showToast('发送成功');
    } else {
      _showToast('发送失败: ${result.error ?? "未知错误"}');
    }
  }

  /// 暂存当前输入到记忆库
  Future<void> _handleStash() async {
    final content = _textController.text;
    if (content.isEmpty) return;
    await _memoryService.add(content);
    _textController.clear();
    _refreshMemoryCount();
    _showToast('已暂存');
  }

  /// 发送记忆内容并删除
  Future<void> _handleSendMemory(TextMemory memory) async {
    if (_selectedDevice == null) {
      _showToast('请先在主应用选择设备');
      return;
    }
    
    final String ip = _selectedDevice!['ip'];
    final int port = _selectedDevice!['port'];
    
    _socketService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);
    
    final result = await _socketService.sendMessage(
      ip, 
      port, 
      memory.content,
      passwordHash: _passwordHash,
    );
    
    if (result.success) {
      await _memoryService.delete(memory.id);
      await _refreshMemoryList();
      _refreshMemoryCount();
      _showToast('发送成功');
    } else {
      _showToast('发送失败');
    }
  }
  
  /// 删除记忆（不发送）
  Future<void> _handleDeleteMemory(TextMemory memory) async {
    await _memoryService.delete(memory.id);
    await _refreshMemoryList();
    _refreshMemoryCount();
    _showToast('已删除');
  }
  
  /// 加载并显示记忆列表
  Future<void> _openMemoryList() async {
    final memories = await _memoryService.getAll();
    setState(() {
      _memories = memories;
      _showMemoryList = true;
    });
  }

  /// 显示自定义 Toast（比 SnackBar 更稳定）
  void _showToast(String message) {
    _toastEntry?.remove();
    
    _toastEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 60,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
    
    Overlay.of(context).insert(_toastEntry!);
    
    Future.delayed(const Duration(seconds: 2), () {
      _toastEntry?.remove();
      _toastEntry = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _isExpanded ? _buildExpandedView() : _buildCollapsedView(),
      ),
    );
  }

  /// 折叠状态: 悬浮小球 (48x48)
  Widget _buildCollapsedView() {
    return GestureDetector(
      onTap: _toggleExpand,
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withAlpha(77),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 22),
            ),
            if (_memoryCount > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Center(
                    child: Text(
                      '$_memoryCount',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 展开状态: 交互卡片
  Widget _buildExpandedView() {
    return Container(
      width: 240,
      height: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(38),
            blurRadius: 25,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _showMemoryList ? _buildMemoryListView() : _buildMainInputView(),
            ),
          ],
        ),
      ),
    );
  }

  /// 头部栏
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      color: Colors.grey[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _showMemoryList ? "历史记忆" : "快捷发送",
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.black87),
          ),
          IconButton(
            icon: Icon(_showMemoryList ? Icons.arrow_back_ios_new : Icons.close_rounded, size: 16),
            onPressed: () {
              if (_showMemoryList) {
                setState(() => _showMemoryList = false);
              } else {
                _toggleExpand();
              }
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: Colors.grey[600],
          ),
        ],
      ),
    );
  }

  /// 发送主界面
  Widget _buildMainInputView() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 设备标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.laptop, size: 12, color: Color(0xFF4A90E2)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _selectedDevice?['name'] ?? '未选择设备',
                    style: const TextStyle(color: Color(0xFF4A90E2), fontSize: 11, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 输入框
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontSize: 13, height: 1.4),
              decoration: InputDecoration(
                hintText: "输入内容...",
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 底部操作栏
          Row(
            children: [
              _buildToolBtn("暂存", Icons.save_alt_rounded, _handleStash),
              const SizedBox(width: 6),
              _buildToolBtn("记忆($_memoryCount)", Icons.history_rounded, _openMemoryList),
              const SizedBox(width: 8),
              _buildSendBtn(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolBtn(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[200]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: Colors.grey[600]),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 8, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildSendBtn() {
    return Expanded(
      child: ElevatedButton(
        onPressed: () => _handleSend(_textController.text),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4A90E2),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text("发送", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  /// 记忆列表（支持长按删除）
  Widget _buildMemoryListView() {
    if (_memories.isEmpty) {
      return Center(
        child: Text("暂无记忆内容", style: TextStyle(color: Colors.grey[400], fontSize: 13)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: _memories.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final memory = _memories[index];
        return GestureDetector(
          onTap: () async {
            await _handleSendMemory(memory);
            if (_memories.isEmpty) {
              setState(() => _showMemoryList = false);
            }
          },
          // 长按删除
          onLongPress: () => _showDeleteConfirm(memory),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[100]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    memory.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.send_rounded, size: 16, color: Colors.blue[400]),
              ],
            ),
          ),
        );
      },
    );
  }
  
  /// 显示删除确认
  void _showDeleteConfirm(TextMemory memory) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记忆', style: TextStyle(fontSize: 16)),
        content: Text(
          '确定删除这条记忆吗？\n\n"${memory.content.length > 50 ? '${memory.content.substring(0, 50)}...' : memory.content}"',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleDeleteMemory(memory);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
