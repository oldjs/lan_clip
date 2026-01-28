import 'dart:convert';
import 'dart:io';

import '../models/process_entry.dart';

class WindowsProcessService {
  /// 获取当前可激活窗口的进程列表
  Future<List<ProcessEntry>> listProcesses() async {
    if (!Platform.isWindows) return [];

    final command =
        r"Get-Process | Where-Object { $_.MainWindowTitle -ne '' } | "
        r"Select-Object Id,ProcessName,MainWindowTitle,Path | ConvertTo-Json -Depth 3";

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', command],
        runInShell: true,
      );

      if (result.exitCode != 0) return [];
      final output = (result.stdout as String).trim();
      if (output.isEmpty) return [];

      final data = jsonDecode(output);
      final list = <ProcessEntry>[];

      if (data is List) {
        for (final item in data) {
          final entry = _mapToEntry(item);
          if (entry != null) list.add(entry);
        }
      } else {
        final entry = _mapToEntry(data);
        if (entry != null) list.add(entry);
      }

      return list;
    } catch (_) {
      return [];
    }
  }

  ProcessEntry? _mapToEntry(dynamic data) {
    if (data is! Map) return null;
    final pid = data['Id'];
    final name = data['ProcessName'] as String?;
    final title = data['MainWindowTitle'] as String?;
    if (pid is! int || name == null || title == null) return null;
    return ProcessEntry(
      pid: pid,
      name: name,
      title: title,
      path: data['Path'] as String?,
    );
  }
}
