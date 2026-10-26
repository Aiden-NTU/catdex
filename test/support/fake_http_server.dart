import 'dart:convert';
import 'dart:io';

class RecordedRequest {
  const RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri uri;
  final HttpHeaders headers;
  final String body;

  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

/// Dependency-free localhost HTTP fake suitable for Linux test runs.
class FakeHttpServer {
  FakeHttpServer._(this._server, this.statusCode, this.responseBody) {
    _serve();
  }

  final HttpServer _server;
  final int statusCode;
  final String responseBody;
  final requests = <RecordedRequest>[];

  Uri get uri => Uri.parse('http://${_server.address.address}:${_server.port}');

  static Future<FakeHttpServer> start({
    int statusCode = HttpStatus.ok,
    String responseBody = '{"ok":true}',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return FakeHttpServer._(server, statusCode, responseBody);
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      requests.add(
        RecordedRequest(
          method: request.method,
          uri: request.uri,
          headers: request.headers,
          body: await utf8.decoder.bind(request).join(),
        ),
      );
      request.response
        ..statusCode = statusCode
        ..headers.contentType = ContentType.json
        ..write(responseBody);
      await request.response.close();
    }
  }

  Future<void> close() => _server.close(force: true);
}
