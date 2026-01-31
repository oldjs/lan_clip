import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../services/quick_transfer_service.dart';
import '../services/socket_service.dart';

/// 二维码扫描页面
/// Android 端扫码连接电脑
class QRScanScreen extends StatefulWidget {
  const QRScanScreen({super.key});
  
  @override
  State<QRScanScreen> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  String _statusText = '将二维码放入框内扫描';
  Color _statusColor = Colors.white;
  
  @override
  void initState() {
    super.initState();
    _initScanner();
  }
  
  void _initScanner() {
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }
  
  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
  
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    
    final rawValue = barcodes.first.rawValue;
    if (rawValue == null) return;
    
    setState(() {
      _isProcessing = true;
      _statusText = '正在连接...';
      _statusColor = Colors.yellow;
    });
    
    // 停止扫描
    _controller?.stop();
    
    // 解析二维码
    final device = QuickTransferService.createDeviceFromUrl(rawValue);
    
    if (device == null) {
      setState(() {
        _isProcessing = false;
        _statusText = '无效的二维码或已过期';
        _statusColor = Colors.red;
      });
      // 2秒后恢复扫描
      await Future.delayed(const Duration(seconds: 2));
      _controller?.start();
      return;
    }
    
    // 尝试连接
    try {
      final socketService = SocketService();
      // 扫码连接不需要加密（二维码会话已验证身份）
      socketService.setEncryption(enabled: false, key: null);
      final connected = await socketService.connectToDevice(device);
      
      if (connected && mounted) {
        setState(() {
          _statusText = '连接成功！';
          _statusColor = Colors.green;
        });
        
        // 延迟后返回
        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.pop(context, device);
      } else if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusText = '连接失败，请检查网络';
          _statusColor = Colors.red;
        });
        // 2秒后恢复扫描
        await Future.delayed(const Duration(seconds: 2));
        _controller?.start();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusText = '连接失败: $e';
          _statusColor = Colors.red;
        });
        // 2秒后恢复扫描
        await Future.delayed(const Duration(seconds: 2));
        _controller?.start();
      }
    }
  }
  
  void _toggleTorch() {
    _controller?.toggleTorch();
  }
  
  void _switchCamera() {
    _controller?.switchCamera();
  }
  
  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 扫描器
          if (_controller != null)
            MobileScanner(
              controller: _controller!,
              onDetect: _onDetect,
              scanWindow: Rect.fromCenter(
                center: Offset(
                  MediaQuery.of(context).size.width / 2,
                  MediaQuery.of(context).size.height / 2,
                ),
                width: 250,
                height: 250,
              ),
            ),
          
          // 扫描框
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _statusColor,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  // 四角标记
                  Positioned(
                    top: 0,
                    left: 0,
                    child: _CornerMarker(color: _statusColor),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _CornerMarker(color: _statusColor, isRight: true),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: _CornerMarker(color: _statusColor, isBottom: true),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: _CornerMarker(color: _statusColor, isRight: true, isBottom: true),
                  ),
                ],
              ),
            ),
          ),
          
          // 顶部栏
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
                  // 闪光灯按钮
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.flashlight_on, color: Colors.white),
                      onPressed: _toggleTorch,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 切换摄像头按钮
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                      onPressed: _switchCamera,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // 状态文字
          Positioned(
            bottom: 120,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusText,
                  style: TextStyle(
                    color: _statusColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          
          // 底部说明
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PhosphorIcon(
                      PhosphorIconsRegular.info,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '扫描电脑端显示的二维码即可连接',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 扫描框四角标记
class _CornerMarker extends StatelessWidget {
  final Color color;
  final bool isRight;
  final bool isBottom;
  
  const _CornerMarker({
    required this.color,
    this.isRight = false,
    this.isBottom = false,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        border: Border(
          top: isBottom ? BorderSide.none : BorderSide(color: color, width: 4),
          bottom: isBottom ? BorderSide(color: color, width: 4) : BorderSide.none,
          left: isRight ? BorderSide.none : BorderSide(color: color, width: 4),
          right: isRight ? BorderSide(color: color, width: 4) : BorderSide.none,
        ),
      ),
    );
  }
}
