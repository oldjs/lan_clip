import 'dart:io';

import '../models/app_entry.dart';

class WindowsAppLauncher {
  /// 启动应用，使用 PowerShell 兼容参数与工作目录
  static Future<bool> launch(AppEntry entry) async {
    if (!Platform.isWindows) return false;

    final path = _escapePowerShell(entry.path.trim());
    final args = entry.args?.trim();
    final workDir = entry.workDir?.trim();

    final argsPart = (args == null || args.isEmpty)
        ? ''
        : ' -ArgumentList "${_escapePowerShell(args)}"';
    final workDirPart = (workDir == null || workDir.isEmpty)
        ? ''
        : ' -WorkingDirectory "${_escapePowerShell(workDir)}"';

    final command = 'Start-Process -FilePath "$path"$argsPart$workDirPart';

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', command],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// PowerShell 字符串转义
  static String _escapePowerShell(String value) {
    return value.replaceAll('"', '`"');
  }
}
