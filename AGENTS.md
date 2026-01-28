# LAN Clip - Agent 开发指南

> 跨平台局域网剪贴板同步工具 - Flutter 项目

## 构建与运行命令

```bash
# 获取依赖
flutter pub get

# 静态分析 (lint)
flutter analyze

# 运行所有测试
flutter test

# 运行单个测试文件
flutter test test/widget_test.dart

# 运行指定测试用例 (按名称匹配)
flutter test --name "Counter increments"

# 运行 Windows 桌面端
flutter run -d windows

# 运行 Android 端
flutter run -d <device_id>

# 构建 Windows release
flutter build windows --release

# 构建 Android APK
flutter build apk --release

# 生成应用图标
flutter pub run flutter_launcher_icons
```

## 项目结构

```
lib/
├── main.dart                    # 应用入口，平台判断，Windows窗口初始化
├── models/                      # 数据模型
│   ├── device.dart              # 设备模型，UDP发现响应解析
│   ├── clipboard_data.dart      # 剪贴板内容模型，序列化/反序列化
│   ├── file_transfer.dart       # 文件传输任务模型，传输协议定义
│   ├── remote_request.dart      # 远程请求/响应模型
│   ├── app_entry.dart           # 快捷应用配置模型
│   ├── process_entry.dart       # Windows进程信息模型
│   └── received_message.dart    # 接收消息记录模型
├── screens/                     # 页面组件
│   ├── desktop_screen.dart      # Windows主界面，服务启动/托盘/剪贴板监听
│   ├── mobile_screen.dart       # Android主界面，设备发现/发送/接收
│   ├── mobile_screen_actions.dart  # 手机端业务逻辑(part of)
│   ├── mobile_screen_dialogs.dart  # 手机端对话框(part of)
│   ├── mobile_screen_ui.dart       # 手机端UI构建(part of)
│   ├── settings_screen.dart     # 设置页面，密码/加密/自动粘贴等
│   ├── file_transfer_screen.dart   # 文件传输列表页面
│   ├── touchpad_screen.dart     # 触摸板页面，远程控制鼠标
│   ├── app_grid_screen.dart     # 快捷应用网格页面
│   ├── simple_input_screen.dart # 简洁输入页面
│   └── text_memory_screen.dart  # 文本记忆暂存页面
├── services/                    # 业务逻辑服务
│   ├── socket_service.dart      # TCP通信服务，消息收发/认证/加密
│   ├── discovery_service.dart   # UDP设备发现服务
│   ├── encryption_service.dart  # AES-256-GCM加密服务，PBKDF2密钥派生
│   ├── auth_service.dart        # 密码认证服务，SHA256哈希+盐值
│   ├── clipboard_service.dart   # 键盘/鼠标控制指令常量定义
│   ├── clipboard_sync_service.dart    # 手机端剪贴板同步接收服务
│   ├── clipboard_watcher_service.dart # Windows剪贴板监听服务
│   ├── file_transfer_service.dart     # 文件传输服务，分块/断点续传
│   ├── mouse_service.dart       # Windows FFI鼠标控制
│   ├── screen_capture_service.dart    # Windows FFI屏幕截图
│   ├── tray_service.dart        # 系统托盘服务(Windows)
│   ├── overlay_service.dart     # Android悬浮窗管理服务
│   ├── phone_control_service.dart     # Android设备管理员/锁屏控制
│   ├── storage_permission_service.dart # Android存储权限服务
│   ├── input_method_service.dart      # Android输入法切换服务
│   ├── mobile_clipboard_helper.dart   # Android剪贴板写入工具
│   ├── text_memory_service.dart # 文本记忆本地存储服务
│   ├── desktop_app_service.dart # 快捷应用配置存储服务
│   ├── windows_app_launcher.dart    # Windows应用启动器
│   ├── windows_process_service.dart # Windows进程列表服务
│   ├── windows_window_service.dart  # Windows窗口激活服务
│   └── remote_request_codec.dart    # LC_REQ/LC_RES协议编解码
├── widgets/                     # 可复用UI组件
│   ├── desktop/                 # 桌面端专用组件
│   │   ├── desktop_app_bar.dart      # 自定义AppBar，窗口拖拽
│   │   ├── desktop_background.dart   # 渐变背景+光晕效果
│   │   ├── desktop_history_panel.dart # 接收历史面板
│   │   └── desktop_status_card.dart  # 服务状态卡片
│   ├── settings/                # 设置相关组件
│   │   └── settings_tiles.dart  # 开关/滑块设置项组件
│   ├── transfer_item_widget.dart    # 文件传输项组件
│   └── remote_screen_overlay.dart   # 远程屏幕悬浮窗组件
├── overlay/                     # Android悬浮窗
│   ├── overlay_main.dart        # 悬浮窗独立入口点(@pragma)
│   └── overlay_widget.dart      # 悬浮窗UI(折叠/展开态)
└── theme/
    └── desktop_theme.dart       # 桌面端Material3主题配置
```

## 代码风格

### 导入顺序
1. `dart:` 标准库
2. `package:flutter/` Flutter SDK
3. `package:` 第三方包 (按字母排序)
4. 相对路径导入 (本项目文件)

```dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../services/encryption_service.dart';
```

### 命名约定
- 类名: `PascalCase` (如 `EncryptionService`, `DeviceModel`)
- 文件名: `snake_case` (如 `encryption_service.dart`)
- 变量/方法: `camelCase` (如 `isEncrypted`, `deriveKey`)
- 私有成员: `_` 前缀 (如 `_cachedKey`, `_handleClient`)
- 常量: `camelCase` 或 `_camelCase` (如 `defaultPort`, `_encryptionEnabledKey`)
- SharedPreferences 键: `snake_case` 字符串 (如 `'auto_paste_enabled'`)

### 类结构顺序
1. 静态常量
2. 实例字段
3. 构造函数
4. 工厂方法 (`factory`)
5. Getter/Setter
6. 公开方法
7. 私有方法
8. `@override` 方法 (`toString`, `==`, `hashCode`)

### 注释规范
- 使用中文注释，简洁明了
- 类和公开方法使用 `///` 文档注释
- 复杂逻辑使用 `//` 行内注释
- 避免冗余注释，代码本身应自解释

```dart
/// 端到端加密服务
/// 使用 AES-256-GCM 加密，PBKDF2 密钥派生
class EncryptionService {
  // PBKDF2 参数
  static const int _pbkdf2Iterations = 100000;
  
  /// 从密码派生加密密钥
  static Future<SecretKey> deriveKey(String password) async {
    // 使用缓存避免重复计算
    if (_cachedKey != null && _cachedPassword == password) {
      return _cachedKey!;
    }
    ...
  }
}
```

### Widget 编写
- `StatelessWidget`: 无状态组件，使用 `const` 构造函数
- `StatefulWidget`: 有状态组件，状态类命名为 `_XxxState`
- 私有 Widget: 使用 `_` 前缀，不需要 `key` 参数
- 使用 `super.key` 而非 `Key? key`

```dart
class DesktopAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onOpenSettings;
  
  const DesktopAppBar({super.key, required this.onOpenSettings});
  
  @override
  Widget build(BuildContext context) { ... }
}
```

### 错误处理
- 网络/IO 操作使用 `try-catch`
- 解密失败返回 `null` 而非抛异常
- 可选值使用 `?.` 和 `??` 操作符
- 异步错误用 `async/await` + `try-catch`

```dart
try {
  final decrypted = await algorithm.decrypt(secretBox, secretKey: key);
  return utf8.decode(decrypted);
} catch (e) {
  // 解密失败（密钥错误或数据损坏）
  return null;
}
```

## 项目级经验

### 加密与密码
- `encryptionEnabled` 必须与 `passwordEnabled` 联动，否则密钥为空导致解密失败
- `setEncryption(enabled: true, key: null)` 时应自动回退为禁用
- 密钥派生路径：`AuthService.hashPassword()` -> `EncryptionService.deriveKey(hash)`

### 平台差异
- Windows 隐藏标题栏：`WindowOptions.titleBarStyle: TitleBarStyle.hidden`
- 自定义 AppBar 拖拽：`GestureDetector(onPanStart: (_) => windowManager.startDragging())`
- 快速退出程序用 `exit(0)`（dart:io），`windowManager.destroy()` 有延迟
- 桌面端布局避免 `SingleChildScrollView`，用 `Column` + `Expanded`

### 协议约定
- 请求-响应：`LC_REQ:` / `LC_RES:` 前缀封装 JSON
- 命令通道：`CMD:` 前缀（如 `CMD:MOUSE_CLICK`）
- UDP 发现响应：`LAN_CLIP|{name}|{port}|{requiresPassword}|{syncPort}|{salt}`
- 剪贴板同步：`TYPE:TEXT\n内容` 或 `TYPE:IMAGE\n<base64>`

### 主题配置
- `textTheme` 默认不继承 `colorScheme.onSurface`
- 需显式调用 `textTheme.apply(bodyColor: colorScheme.onSurface, displayColor: colorScheme.onSurface)`

### 导航与设备连接
- `FileTransferScreen`、`AppGridScreen` 等需通过参数传入 `selectedDevice`
- 目标设备需密码时 (`device.requiresPassword`)，客户端必须派生加密密钥

### Android 特殊处理
- 锁屏需设备管理员：`AndroidManifest.xml` + `res/xml/device_admin_receiver.xml`
- `device_policy_manager` 权限方法名为 `requestPermession`（注意拼写）
- 悬浮窗入口点用 `@pragma("vm:entry-point")`
- 存储权限 Android 11+ 使用 `MANAGE_EXTERNAL_STORAGE`

### Windows 特殊处理
- 进程控制用 PowerShell：`Start-Process`, `Get-Process`, `WScript.Shell.AppActivate`
- 电脑控制手机指令走 `syncPort` 通道（`SocketService.pushCommandToDevices`）
- FFI 调用 `user32.dll`/`gdi32.dll` 实现鼠标控制和屏幕截图

### 单例模式
- `FileTransferService` 使用单例：`factory FileTransferService() => _instance;`

### 大型页面拆分 (part/part of)
- `mobile_screen.dart` 拆分为 `_actions.dart`、`_dialogs.dart`、`_ui.dart`
- 使用 `part 'mobile_screen_actions.dart';` 和 `part of` 关联

## 文件大小限制

- 单文件不超过 700 行
- 大型 Screen 拆分为：`xxx_screen.dart`, `xxx_screen_actions.dart`, `xxx_screen_dialogs.dart`, `xxx_screen_ui.dart`

## 禁止事项

- 禁止在代码和字符串中使用 Emoji
- 禁止使用 Emoji 替代图标（使用 `phosphor_flutter` 图标库）
