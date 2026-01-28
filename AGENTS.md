# 项目级经验

- 加密功能依赖密码设置：`encryptionEnabled` 必须与 `passwordEnabled` 联动，否则会因密钥为空导致文件传输解密失败。在 `setEncryption(enabled: true, key: null)` 时应自动回退为禁用。
- Flutter `textTheme` 默认不继承 `colorScheme.onSurface`，需要在 `ThemeData` 中显式调用 `textTheme.apply(bodyColor: colorScheme.onSurface, displayColor: colorScheme.onSurface)`，否则浅色背景上文字可能不可见。
- 桌面端布局避免使用 `SingleChildScrollView` 包裹整个页面，改用 `Column` + `Expanded` 让子组件自适应窗口大小。
- 请求-响应协议使用 `LC_REQ:` / `LC_RES:` 前缀封装 JSON，并与加密流程共用同一路径，不能按普通消息处理。
- 电脑端应用控制与进程激活依赖 PowerShell：启动用 `Start-Process`，进程列表与激活分别用 `Get-Process` 与 `WScript.Shell.AppActivate`。
- 手机端入口调整需同步拆分文件：`lib/screens/mobile_screen.dart` 与 `lib/screens/mobile_screen_actions.dart`、`lib/screens/mobile_screen_dialogs.dart`、`lib/screens/mobile_screen_ui.dart`。
- 电脑控制手机类指令走手机 `syncPort` 的剪贴板同步通道（`SocketService.pushCommandToDevices`），手机端需在 `ClipboardSyncService` 先分流 `CMD:` 再处理剪贴板内容。
- Android 锁屏需设备管理员接收器与策略 XML（`AndroidManifest.xml` + `res/xml/device_admin_receiver.xml`），并在手机设置默认关闭后手动授权。
- `device_policy_manager` 的权限申请方法名为 `requestPermession`（拼写不是 requestPermission），调用时要按包的真实 API 名称。
- 触摸板按钮走 `CMD:MOUSE_*` 指令通道，长按发送 `*_DOWN/UP`，中键单击用 `CMD:MOUSE_MIDDLE_CLICK`。
- `FileTransferScreen`、`AppGridScreen` 等需要设备连接的屏幕，必须通过导航参数传入 `selectedDevice`，否则显示"未连接"且功能不可用。
- 当目标设备需要密码（`device.requiresPassword`）时，客户端屏幕应始终派生加密密钥，不论本地加密设置如何，以匹配 PC 端的加密状态。
- Windows 隐藏系统标题栏：`WindowOptions` 设置 `titleBarStyle: TitleBarStyle.hidden`，自定义 AppBar 用 `GestureDetector(onPanStart: (_) => windowManager.startDragging())` 支持拖拽。
- 快速退出程序用 `exit(0)`（dart:io），`windowManager.destroy()` 有动画延迟会很慢。
