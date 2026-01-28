class AppEntry {
  final String id;
  final String name;
  final String path;
  final String? args;
  final String? workDir;

  AppEntry({
    required this.id,
    required this.name,
    required this.path,
    this.args,
    this.workDir,
  });

  AppEntry copyWith({
    String? id,
    String? name,
    String? path,
    String? args,
    String? workDir,
  }) {
    return AppEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      args: args ?? this.args,
      workDir: workDir ?? this.workDir,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'args': args,
      'workDir': workDir,
    };
  }

  static AppEntry? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    final path = json['path'] as String?;
    if (id == null || name == null || path == null) return null;
    return AppEntry(
      id: id,
      name: name,
      path: path,
      args: json['args'] as String?,
      workDir: json['workDir'] as String?,
    );
  }
}
