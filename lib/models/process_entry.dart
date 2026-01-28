class ProcessEntry {
  final int pid;
  final String name;
  final String title;
  final String? path;

  ProcessEntry({
    required this.pid,
    required this.name,
    required this.title,
    this.path,
  });

  Map<String, dynamic> toJson() {
    return {
      'pid': pid,
      'name': name,
      'title': title,
      'path': path,
    };
  }

  static ProcessEntry? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final pid = json['pid'];
    final name = json['name'] as String?;
    final title = json['title'] as String?;
    if (pid is! int || name == null || title == null) return null;
    return ProcessEntry(
      pid: pid,
      name: name,
      title: title,
      path: json['path'] as String?,
    );
  }
}
