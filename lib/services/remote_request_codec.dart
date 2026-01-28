import 'dart:convert';

import '../models/remote_request.dart';

const String requestPrefix = 'LC_REQ:';
const String responsePrefix = 'LC_RES:';

class RemoteRequestCodec {
  static String encodeRequest(RemoteRequest request) {
    return '$requestPrefix${jsonEncode(request.toJson())}';
  }

  static String encodeResponse(RemoteResponse response) {
    return '$responsePrefix${jsonEncode(response.toJson())}';
  }

  static RemoteRequest? tryDecodeRequest(String message) {
    if (!message.startsWith(requestPrefix)) return null;
    final raw = message.substring(requestPrefix.length).trim();
    if (raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;
      return RemoteRequest.tryFromJson(data);
    } catch (_) {
      return null;
    }
  }

  static RemoteResponse? tryDecodeResponse(String message) {
    if (!message.startsWith(responsePrefix)) return null;
    final raw = message.substring(responsePrefix.length).trim();
    if (raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;
      return RemoteResponse.tryFromJson(data);
    } catch (_) {
      return null;
    }
  }
}
