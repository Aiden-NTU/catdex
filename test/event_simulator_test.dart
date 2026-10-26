import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/fake_http_server.dart';

void main() {
  test(
    'event simulator posts one deterministic payload per contributor',
    () async {
      final server = await FakeHttpServer.start(statusCode: 201);
      addTearDown(server.close);

      final result = await Process.run(_dartExecutable(), [
        'tool/simulate_event_contributors.dart',
        '--url',
        server.uri.resolve('/events/contributions').toString(),
        '--event-id',
        'fixture-event',
        '--concurrency',
        '10',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('100 succeeded'));
      expect(server.requests, hasLength(100));

      final bySequence = [...server.requests]
        ..sort(
          (a, b) =>
              (a.json['sequence'] as int).compareTo(b.json['sequence'] as int),
        );
      expect(bySequence.map((request) => request.uri.path).toSet(), {
        '/events/contributions',
      });
      expect(bySequence.first.json['contributorId'], 'contributor-001');
      expect(bySequence.last.json['contributorId'], 'contributor-100');
      expect(
        bySequence.map((request) => request.json['contributorId']).toSet(),
        hasLength(100),
      );
      expect(bySequence.map((request) => request.json['eventId']).toSet(), {
        'fixture-event',
      });
    },
  );
}

String _dartExecutable() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final dart = File('$flutterRoot/bin/dart');
    if (dart.existsSync()) return dart.path;
  }

  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final dart = File('${directory.path}/dart');
    if (directory.path.endsWith('/bin') && dart.existsSync()) {
      return dart.path;
    }
    directory = directory.parent;
  }
  return 'dart';
}
