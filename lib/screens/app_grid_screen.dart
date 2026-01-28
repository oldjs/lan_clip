import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:cryptography/cryptography.dart';

import '../models/app_entry.dart';
import '../models/device.dart';
import '../models/process_entry.dart';
import '../models/remote_request.dart';
import '../services/auth_service.dart';
import '../services/encryption_service.dart';
import '../services/socket_service.dart';

class AppGridScreen extends StatefulWidget {
  final Device device;
  final String? passwordHash;

  const AppGridScreen({
    super.key,
    required this.device,
    this.passwordHash,
  });

  @override
  State<AppGridScreen> createState() => _AppGridScreenState();
}

class _AppGridScreenState extends State<AppGridScreen> {
  final _socketService = SocketService();
  final _uuid = const Uuid();

  final List<AppEntry> _apps = [];
  bool _loading = true;
  bool _sending = false;
  bool _encryptionEnabled = false;
  SecretKey? _encryptionKey;
  String? _passwordHash;

  @override
  void initState() {
    super.initState();
    _passwordHash = widget.passwordHash;
    _initialize();
  }

  Future<void> _initialize() async {
    // 初始化加密设置
    _encryptionEnabled = await EncryptionService.isEncryptionEnabled();
    
    // 当设备需要密码且已有密码哈希时，派生密钥
    if (widget.device.requiresPassword && _passwordHash != null) {
      _encryptionKey = await EncryptionService.deriveKey(_passwordHash!);
      _encryptionEnabled = true;
    } else if (_encryptionEnabled && _passwordHash != null) {
      _encryptionKey = await EncryptionService.deriveKey(_passwordHash!);
    }
    
    // 重要：如果没有密钥但启用了加密，禁用加密以避免解密失败
    if (_encryptionEnabled && _encryptionKey == null) {
      _encryptionEnabled = false;
    }
    
    _socketService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);

    await _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() => _loading = true);
    final response = await _sendRequest('app_list', null);
    if (response?.ok == true) {
      _apps
        ..clear()
        ..addAll(_parseApps(response!.data));
    } else {
      _showSnackBar(response?.error ?? '获取应用失败');
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _openAddDialog({AppEntry? editing}) async {
    final result = await _showAppEditorDialog(editing: editing);
    if (result == null) return;

    setState(() => _sending = true);
    final response = await _sendRequest('app_upsert', {'app': result.toJson()});
    if (response?.ok == true) {
      _apps
        ..clear()
        ..addAll(_parseApps(response!.data));
    } else {
      _showSnackBar(response?.error ?? '保存失败');
    }
    if (mounted) {
      setState(() => _sending = false);
    }
  }

  Future<void> _removeApp(AppEntry entry) async {
    final confirmed = await _showConfirmDialog('删除应用', '确定删除 ${entry.name} 吗？');
    if (!confirmed) return;

    setState(() => _sending = true);
    final response = await _sendRequest('app_remove', {'id': entry.id});
    if (response?.ok == true) {
      _apps
        ..clear()
        ..addAll(_parseApps(response!.data));
    } else {
      _showSnackBar(response?.error ?? '删除失败');
    }
    if (mounted) {
      setState(() => _sending = false);
    }
  }

  Future<void> _launchApp(AppEntry entry) async {
    setState(() => _sending = true);
    final response = await _sendRequest('app_launch', {'id': entry.id});
    if (response?.ok != true) {
      _showSnackBar(response?.error ?? '启动失败');
    }
    if (mounted) {
      setState(() => _sending = false);
    }
  }

  Future<void> _openProcessPicker() async {
    setState(() => _sending = true);
    // 拉取可激活进程
    final response = await _sendRequest('process_list', null);
    if (mounted) {
      setState(() => _sending = false);
    }
    if (response?.ok != true) {
      _showSnackBar(response?.error ?? '获取进程失败');
      return;
    }

    final processes = _parseProcesses(response!.data);
    if (processes.isEmpty) {
      _showSnackBar('没有可激活的窗口');
      return;
    }

    final selected = await _showProcessSelector(processes);
    if (selected == null) return;

    final activate = await _sendRequest('process_activate', {'pid': selected.pid});
    if (activate?.ok != true) {
      _showSnackBar(activate?.error ?? '激活失败');
    }
  }

  Future<RemoteResponse?> _sendRequest(String action, Map<String, dynamic>? payload) async {
    // 统一封装请求发送
    final passwordHash = await _ensurePasswordHash();
    if (widget.device.requiresPassword && passwordHash == null) return null;

    _socketService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);
    final request = RemoteRequest(id: _uuid.v4(), action: action, payload: payload);
    return _socketService.sendRequest(
      widget.device.ip,
      widget.device.port,
      request,
      passwordHash: passwordHash,
    );
  }

  Future<String?> _ensurePasswordHash() async {
    if (!widget.device.requiresPassword) return null;
    if (_passwordHash != null) return _passwordHash;

    // 需要密码时弹窗询问
    final password = await _showPasswordDialog();
    if (password == null) return null;

    final salt = widget.device.salt ?? '';
    _passwordHash = AuthService.hashPassword(password, salt);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('overlay_password_hash', _passwordHash!);

    if (_encryptionEnabled) {
      _encryptionKey = await EncryptionService.deriveKey(_passwordHash!);
    }
    return _passwordHash;
  }

  List<AppEntry> _parseApps(dynamic data) {
    if (data is! List) return [];
    return data
        .map((item) {
          if (item is! Map) return null;
          return AppEntry.tryFromJson(Map<String, dynamic>.from(item));
        })
        .whereType<AppEntry>()
        .toList();
  }

  List<ProcessEntry> _parseProcesses(dynamic data) {
    if (data is! List) return [];
    return data
        .map((item) {
          if (item is! Map) return null;
          return ProcessEntry.tryFromJson(Map<String, dynamic>.from(item));
        })
        .whereType<ProcessEntry>()
        .toList();
  }

  Future<ProcessEntry?> _showProcessSelector(List<ProcessEntry> list) {
    return showModalBottomSheet<ProcessEntry>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = list[index];
            return ListTile(
              title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${item.name} · PID ${item.pid}'),
              onTap: () => Navigator.pop(context, item),
            );
          },
        ),
      ),
    );
  }

  Future<AppEntry?> _showAppEditorDialog({AppEntry? editing}) async {
    final nameController = TextEditingController(text: editing?.name ?? '');
    final pathController = TextEditingController(text: editing?.path ?? '');
    final argsController = TextEditingController(text: editing?.args ?? '');
    final workDirController = TextEditingController(text: editing?.workDir ?? '');

    return showDialog<AppEntry>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(editing == null ? '添加应用' : '编辑应用'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pathController,
                decoration: const InputDecoration(labelText: '路径'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: argsController,
                decoration: const InputDecoration(labelText: '参数(可选)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: workDirController,
                decoration: const InputDecoration(labelText: '工作目录(可选)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              final path = pathController.text.trim();
              if (name.isEmpty || path.isEmpty) {
                _showSnackBar('名称和路径不能为空');
                return;
              }
              final entry = AppEntry(
                id: editing?.id ?? _uuid.v4(),
                name: name,
                path: path,
                args: argsController.text.trim().isEmpty ? null : argsController.text.trim(),
                workDir: workDirController.text.trim().isEmpty
                    ? null
                    : workDirController.text.trim(),
              );
              Navigator.pop(context, entry);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showConfirmDialog(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _showPasswordDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入连接密码'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '密码',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final password = controller.text.trim();
              Navigator.pop(context, password.isEmpty ? null : password);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用控制'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: '选择进程',
            onPressed: _sending ? null : _openProcessPicker,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loading ? null : _loadApps,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.9,
              ),
              itemCount: _apps.length + 1,
              itemBuilder: (context, index) {
                if (index == _apps.length) {
                  return _buildAddCard();
                }
                final entry = _apps[index];
                return _buildAppCard(entry);
              },
            ),
    );
  }

  Widget _buildAddCard() {
    return InkWell(
      onTap: _sending ? null : () => _openAddDialog(),
      child: Card(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.add, size: 28),
              SizedBox(height: 6),
              Text('添加', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppCard(AppEntry entry) {
    return InkWell(
      onTap: _sending ? null : () => _launchApp(entry),
      onLongPress: _sending
          ? null
          : () async {
              final action = await _showAppActionSheet();
              if (action == 'edit') {
                _openAddDialog(editing: entry);
              } else if (action == 'remove') {
                _removeApp(entry);
              }
            },
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.apps, size: 22),
              const SizedBox(height: 6),
              Text(
                entry.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _showAppActionSheet() {
    return showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('删除'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
  }
}
