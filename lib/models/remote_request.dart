class RemoteRequest {
  final String id;
  final String action;
  final Map<String, dynamic>? payload;

  RemoteRequest({
    required this.id,
    required this.action,
    this.payload,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'action': action,
      'payload': payload,
    };
  }

  static RemoteRequest? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = json['id'] as String?;
    final action = json['action'] as String?;
    final payload = json['payload'] as Map<String, dynamic>?;
    if (id == null || action == null) return null;
    return RemoteRequest(id: id, action: action, payload: payload);
  }
}

class RemoteResponse {
  final String id;
  final bool ok;
  final dynamic data;
  final String? error;

  RemoteResponse({
    required this.id,
    required this.ok,
    this.data,
    this.error,
  });

  factory RemoteResponse.ok(String id, {dynamic data}) {
    return RemoteResponse(id: id, ok: true, data: data);
  }

  factory RemoteResponse.fail(String id, String error) {
    return RemoteResponse(id: id, ok: false, error: error);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ok': ok,
      'data': data,
      'error': error,
    };
  }

  static RemoteResponse? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = json['id'] as String?;
    final ok = json['ok'] as bool?;
    if (id == null || ok == null) return null;
    return RemoteResponse(
      id: id,
      ok: ok,
      data: json['data'],
      error: json['error'] as String?,
    );
  }
}
