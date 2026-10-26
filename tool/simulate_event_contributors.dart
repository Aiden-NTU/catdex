import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options == null) {
    _printUsage();
    exitCode = 64;
    return;
  }

  final client = HttpClient()..connectionTimeout = options.timeout;
  final statuses = <int, int>{};
  var nextContributor = 0;

  Future<void> worker() async {
    while (true) {
      final index = nextContributor++;
      if (index >= options.count) return;
      final contributorId =
          'contributor-${(index + 1).toString().padLeft(3, '0')}';
      var status = 0;
      try {
        final request = await client
            .postUrl(options.url)
            .timeout(options.timeout);
        request.headers.contentType = ContentType.json;
        request.headers.set('User-Agent', 'catdex-event-simulator/1.0');
        request.write(
          jsonEncode({
            'eventId': options.eventId,
            'contributorId': contributorId,
            'sequence': index + 1,
            'contribution': {
              'type': 'cat_sighting',
              'cellId': 'g_${index % 10}_${index ~/ 10}',
              'stars': (index % 5) + 1,
            },
          }),
        );
        final response = await request.close().timeout(options.timeout);
        status = response.statusCode;
        await response.drain<void>();
      } on Object catch (error) {
        stderr.writeln('$contributorId failed: $error');
      }
      statuses[status] = (statuses[status] ?? 0) + 1;
    }
  }

  final stopwatch = Stopwatch()..start();
  await Future.wait(List.generate(options.concurrency, (_) => worker()));
  stopwatch.stop();
  client.close(force: true);

  final succeeded = statuses.entries
      .where((entry) => entry.key >= 200 && entry.key < 300)
      .fold<int>(0, (sum, entry) => sum + entry.value);
  final summary = statuses.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  stdout.writeln(
    'Sent ${options.count} contributions from ${options.count} contributors '
    'in ${stopwatch.elapsedMilliseconds} ms; '
    '$succeeded succeeded; statuses '
    '${summary.map((entry) => '${entry.key}:${entry.value}').join(', ')}',
  );
  if (succeeded != options.count) exitCode = 1;
}

class _Options {
  const _Options({
    required this.url,
    required this.eventId,
    required this.count,
    required this.concurrency,
    required this.timeout,
  });

  final Uri url;
  final String eventId;
  final int count;
  final int concurrency;
  final Duration timeout;

  static _Options? parse(List<String> arguments) {
    if (arguments.contains('--help') || arguments.contains('-h')) return null;
    final values = <String, String>{};
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      if (!argument.startsWith('--') || i + 1 >= arguments.length) return null;
      values[argument.substring(2)] = arguments[++i];
    }

    final rawUrl = values['url'];
    final url = rawUrl == null ? null : Uri.tryParse(rawUrl);
    final count = int.tryParse(values['count'] ?? '100');
    final concurrency = int.tryParse(values['concurrency'] ?? '10');
    final timeoutMs = int.tryParse(values['timeout-ms'] ?? '5000');
    if (url == null ||
        !url.hasScheme ||
        count == null ||
        count < 1 ||
        concurrency == null ||
        concurrency < 1 ||
        timeoutMs == null ||
        timeoutMs < 1) {
      return null;
    }
    return _Options(
      url: url,
      eventId: values['event-id'] ?? 'catdex-load-test',
      count: count,
      concurrency: concurrency > count ? count : concurrency,
      timeout: Duration(milliseconds: timeoutMs),
    );
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart tool/simulate_event_contributors.dart '
    '--url <endpoint> [--event-id <id>] [--count 100] '
    '[--concurrency 10] [--timeout-ms 5000]',
  );
}
