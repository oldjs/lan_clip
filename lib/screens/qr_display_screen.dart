import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/quick_transfer_service.dart';

/// 二维码显示页面
/// Windows 端生成二维码供手机扫码
class QRDisplayScreen extends StatefulWidget {
  final int port;
  final String deviceName;
  
  const QRDisplayScreen({
    super.key,
    required this.port,
    required this.deviceName,
  });
  
  @override
  State<QRDisplayScreen> createState() => _QRDisplayScreenState();
}

class _QRDisplayScreenState extends State<QRDisplayScreen> {
  String? _qrUrl;
  int _remainingSeconds = 0;
  Timer? _countdownTimer;
  bool _isGenerating = true;
  
  @override
  void initState() {
    super.initState();
    _generateQR();
  }
  
  @override
  void dispose() {
    _countdownTimer?.cancel();
    QuickTransferService().stopSession();
    super.dispose();
  }
  
  Future<void> _generateQR() async {
    setState(() => _isGenerating = true);
    
    final url = await QuickTransferService().startSession(
      port: widget.port,
      deviceName: widget.deviceName,
      onClientConnected: (socket) {
        // 连接成功后关闭页面
        if (mounted) {
          Navigator.pop(context, true);
        }
      },
    );
    
    if (mounted) {
      setState(() {
        _qrUrl = url;
        _isGenerating = false;
        _remainingSeconds = 300; // 5分钟
      });
      
      // 启动倒计时
      _startCountdown();
    }
  }
  
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_remainingSeconds > 0) {
            _remainingSeconds--;
          } else {
            timer.cancel();
          }
        });
      }
    });
  }
  
  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
  
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.qr_code_scanner, color: colorScheme.primary),
            const SizedBox(width: 8),
            const Text('扫码连接'),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainerHighest.withOpacity(0.3),
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              margin: const EdgeInsets.all(24),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.qr_code_scanner,
                          size: 32,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '扫码闪电传',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 说明文字
                    Text(
                      '使用手机扫描二维码即可快速连接',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // 二维码区域
                    if (_isGenerating)
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: colorScheme.primary,
                          ),
                        ),
                      )
                    else if (_qrUrl != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant,
                            width: 1,
                          ),
                        ),
                        child: QrImageView(
                          data: _qrUrl!,
                          version: QrVersions.auto,
                          size: 200,
                          backgroundColor: Colors.white,
                          errorStateBuilder: (context, error) {
                            return const Center(
                              child: Text(
                                '生成二维码失败',
                                style: TextStyle(color: Colors.red),
                              ),
                            );
                          },
                        ),
                      )
                    else
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: colorScheme.error,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '生成失败',
                                style: TextStyle(color: colorScheme.error),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    const SizedBox(height: 24),
                    
                    // 倒计时
                    if (!_isGenerating && _qrUrl != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _remainingSeconds < 30
                            ? colorScheme.errorContainer
                            : colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer,
                              size: 18,
                              color: _remainingSeconds < 30
                                ? colorScheme.error
                                : colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formatTime(_remainingSeconds),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _remainingSeconds < 30
                                  ? colorScheme.error
                                  : colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    const SizedBox(height: 24),
                    
                    // 操作按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            _countdownTimer?.cancel();
                            _generateQR();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新生成'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          label: const Text('关闭'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
