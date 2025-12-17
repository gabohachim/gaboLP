import 'dart:convert';
import 'package:http/http.dart' as http;

/// Cliente HTTP que inyecta los headers de GoogleSignIn (OAuth)
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Utilidad para convertir authHeaders (Map<String,String>) en headers válidos
Map<String, String> normalizeAuthHeaders(Map<String, String> h) {
  // A veces vienen valores con comillas escapadas, esto lo deja limpio.
  return h.map((k, v) => MapEntry(k, v is String ? v : jsonEncode(v)));
}

