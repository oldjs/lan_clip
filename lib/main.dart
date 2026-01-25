import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'screens/mobile_screen.dart';
import 'screens/desktop_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Windows 窗口管理初始化
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    
    const windowOptions = WindowOptions(
      size: Size(450, 600),
      minimumSize: Size(400, 500),
      center: true,
      title: 'LAN Clip',
      skipTaskbar: false,
    );
    
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LAN Clip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: _buildHomeScreen(),
    );
  }

  /// 根据平台选择界面
  Widget _buildHomeScreen() {
    // Windows/macOS/Linux 作为接收端
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return const DesktopScreen();
    }
    // Android/iOS 作为发送端
    return const MobileScreen();
  }
}
