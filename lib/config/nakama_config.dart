class NakamaConfig {
  const NakamaConfig({
    required this.url,
    required this.serverKey,
    this.developmentMode = false,
    this.requestTimeout = const Duration(seconds: 8),
    this.outboxLimit = 100,
  });

  /// Local docker-compose defaults match `nakama/docker-compose.yml`.
  /// Override in real deploys with `--dart-define=CATDEX_NAKAMA_*`.
  factory NakamaConfig.fromEnvironment() => const NakamaConfig(
    url: String.fromEnvironment(
      'CATDEX_NAKAMA_URL',
      defaultValue: 'http://127.0.0.1:7350',
    ),
    serverKey: String.fromEnvironment(
      'CATDEX_NAKAMA_SERVER_KEY',
      defaultValue: 'localdevkey',
    ),
    developmentMode: bool.fromEnvironment('CATDEX_DEVELOPMENT_MODE'),
  );

  final String url;
  final String serverKey;
  final bool developmentMode;
  final Duration requestTimeout;
  final int outboxLimit;

  bool get isLoopback {
    final host = Uri.tryParse(url)?.host ?? '';
    return host == '127.0.0.1' || host == 'localhost' || host == '::1';
  }

  NakamaConfig copyWith({
    String? url,
    String? serverKey,
    bool? developmentMode,
  }) => NakamaConfig(
    url: url ?? this.url,
    serverKey: serverKey ?? this.serverKey,
    developmentMode: developmentMode ?? this.developmentMode,
    requestTimeout: requestTimeout,
    outboxLimit: outboxLimit,
  );

  Uri uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(url);
    final normalized = path.startsWith('/') ? path : '/$path';
    return base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$normalized',
      queryParameters: query,
    );
  }
}
