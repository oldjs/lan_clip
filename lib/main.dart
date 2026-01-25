import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'screens/mobile_screen.dart';
import 'screens/desktop_screen.dart';

// 是否为开机自启
bool isAutoStart = false;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 检查是否为开机自启 (通过命令行参数)
  isAutoStart = args.contains('--autostart');
  
  // Windows 平台初始化
  if (Platform.isWindows) {
    // 初始化 launch_at_startup
    final packageInfo = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
      args: ['--autostart'],  // 自启时传递参数
    );
    
    // 窗口管理初始化
    await windowManager.ensureInitialized();
    
    const windowOptions = WindowOptions(
      size: Size(450, 600),
      minimumSize: Size(400, 500),
      center: true,
      title: 'LAN Clip',
      skipTaskbar: false,
    );
    
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (isAutoStart) {
        // 开机自启时直接隐藏到托盘
        await windowManager.hide();
      } else {
        // 手动启动时显示窗口
        await windowManager.show();
        await windowManager.focus();
      }
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
