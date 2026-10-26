import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/nakama_config.dart';
import '../game/battle/match_state.dart';

class NakamaException implements Exception {
  const NakamaException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final int? code;

  @override
  String toString() => 'NakamaException: $message';
}

class NakamaConfigurationException extends NakamaException {
  const NakamaConfigurationException(super.message);
}

class NakamaTimeoutException extends NakamaException {
  const NakamaTimeoutException(super.message);
}

class NakamaNetworkException extends NakamaException {
  const NakamaNetworkException(super.message);
}

class NakamaQueuedException extends NakamaNetworkException {
  const NakamaQueuedException(super.message);
}

class NakamaCard {
  const NakamaCard(this.json);

  final Map<String, dynamic> json;

  String get id => json['id'] as String? ?? '';
  String get name => json['name'] as String? ?? '';
  int get level => (json['level'] as num?)?.toInt() ?? 1;
  int get xp => (json['xp'] as num?)?.toInt() ?? 0;
  int get energy => (json['energy'] as num?)?.toInt() ?? 100;
  int get hunger => (json['hunger'] as num?)?.toInt() ?? 100;
  int get mood => (json['mood'] as num?)?.toInt() ?? 75;
  int get bond => (json['bond'] as num?)?.toInt() ?? 0;
  int get abilityMastery => (json['abilityMastery'] as num?)?.toInt() ?? 0;
}

class NakamaCareAccount {
  const NakamaCareAccount(this.json);

  final Map<String, dynamic> json;

  int get pawCoins => (json['pawCoins'] as num?)?.toInt() ?? 0;
  int get dailyEarned => (json['dailyEarned'] as num?)?.toInt() ?? 0;
  int get dailyCap => (json['dailyCap'] as num?)?.toInt() ?? 100;
  int get treats => (json['treats'] as num?)?.toInt() ?? 0;
  int get groomingSupplies => (json['groomingSupplies'] as num?)?.toInt() ?? 0;
}

class NakamaCareState {
  const NakamaCareState({
    required this.card,
    required this.account,
    this.action = '',
    this.xpAwarded = 0,
    this.coinsAwarded = 0,
    this.cooldownSeconds = 0,
    this.idempotent = false,
  });

  final NakamaCard card;
  final NakamaCareAccount account;
  final String action;
  final int xpAwarded;
  final int coinsAwarded;
  final int cooldownSeconds;
  final bool idempotent;

  factory NakamaCareState.fromJson(Map<String, dynamic> json) =>
      NakamaCareState(
        card: NakamaCard(_asMap(json['card'])),
        account: NakamaCareAccount(_asMap(json['account'])),
        action: json['action'] as String? ?? '',
        xpAwarded: (json['xpAwarded'] as num?)?.toInt() ?? 0,
        coinsAwarded: (json['coinsAwarded'] as num?)?.toInt() ?? 0,
        cooldownSeconds: (json['cooldownSeconds'] as num?)?.toInt() ?? 0,
        idempotent: json['idempotent'] as bool? ?? false,
      );

  static Map<String, dynamic> _asMap(Object? value) =>
      value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};
}

class NakamaInventory {
  const NakamaInventory(this.cards);

  final List<NakamaCard> cards;
}

class NakamaEnrollResult {
  const NakamaEnrollResult({
    required this.card,
    required this.idempotent,
    this.auditFlags = const [],
  });

  final NakamaCard card;
  final bool idempotent;
  final List<String> auditFlags;
}

class NakamaFeedResult {
  const NakamaFeedResult({
    required this.cardId,
    required this.level,
    required this.xp,
    required this.xpAwarded,
    required this.idempotent,
  });

  final String cardId;
  final int level;
  final int xp;
  final int xpAwarded;
  final bool idempotent;
}

class NakamaEvent {
  const NakamaEvent(this.json);

  final Map<String, dynamic> json;

  String get id => json['id'] as String? ?? '';
  String get h3Cell => json['h3Cell'] as String? ?? '';
  int get goal => (json['goal'] as num?)?.toInt() ?? 0;
  int get progress => (json['progress'] as num?)?.toInt() ?? 0;
  String get kind => json['kind'] as String? ?? '';
  String get title => json['title'] as String? ?? 'Community event';
  String get description => json['description'] as String? ?? '';
  String get state => json['state'] as String? ?? 'active';
  double get latitude => (json['latitude'] as num?)?.toDouble() ?? 0;
  double get longitude => (json['longitude'] as num?)?.toDouble() ?? 0;
  int get radiusM => (json['radiusM'] as num?)?.toInt() ?? 500;
  int get perUserCap => (json['perUserCap'] as num?)?.toInt() ?? 0;
  int get myContribution => (json['myContribution'] as num?)?.toInt() ?? 0;
  DateTime get startsAt =>
      DateTime.tryParse(json['startsAt'] as String? ?? '') ?? DateTime.now();
  DateTime get endsAt =>
      DateTime.tryParse(json['endsAt'] as String? ?? '') ?? DateTime.now();
  Map<String, dynamic> get metadata => json['metadata'] is Map
      ? (json['metadata'] as Map).cast<String, dynamic>()
      : const {};
}

class NakamaContributionResult {
  const NakamaContributionResult({
    required this.eventId,
    required this.progress,
    required this.goal,
    required this.accepted,
    required this.idempotent,
    this.personalReward = 0,
    this.communityReward = 0,
    this.remainingCap = 0,
  });

  final String eventId;
  final int progress;
  final int goal;
  final int accepted;
  final bool idempotent;
  final int personalReward;
  final int communityReward;
  final int remainingCap;
}

class NakamaBattleResult {
  const NakamaBattleResult(this.json);

  final Map<String, dynamic> json;

  String get battleId => json['battleId'] as String? ?? '';
  String get winnerId => json['winnerId'] as String? ?? '';
}

class NakamaBattleState {
  const NakamaBattleState(this.state);

  final AuthoritativeBattleState state;
}

class NakamaSession {
  const NakamaSession({
    required this.token,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String token;
  final String refreshToken;
  final DateTime expiresAt;
}

class NakamaClient {
  NakamaClient({
    required this.config,
    required this.preferences,
    http.Client? httpClient,
    this.uuid = const Uuid(),
  }) : _http = httpClient ?? http.Client();

  static const _deviceIdKey = 'catdex_nakama_device_id';
  static const _tokenKey = 'catdex_nakama_token';
  static const _refreshTokenKey = 'catdex_nakama_refresh_token';
  static const _outboxKey = 'catdex_nakama_outbox_v1';

  final NakamaConfig config;
  final SharedPreferences preferences;
  final Uuid uuid;
  final http.Client _http;
  Future<NakamaSession>? _sessionRequest;
  bool _flushing = false;

  String get _basicAuthorization =>
      'Basic ${base64Encode(utf8.encode('${config.serverKey}:'))}';

  Future<String> deviceId() async {
    var value = preferences.getString(_deviceIdKey);
    if (value == null || value.isEmpty) {
      value = uuid.v4();
      await preferences.setString(_deviceIdKey, value);
    }
    return value;
  }

  Future<bool> healthcheck() async {
    try {
      final response = await _http
          .get(config.uri('/healthcheck'))
          .timeout(config.requestTimeout);
      return response.statusCode == 200;
    } on Object {
      return false;
    }
  }

  Future<NakamaSession> session() {
    final active = _sessionRequest;
    if (active != null) return active;
    final request = _loadOrAuthenticate();
    _sessionRequest = request;
    return request.whenComplete(() {
      if (identical(_sessionRequest, request)) _sessionRequest = null;
    });
  }

  Future<NakamaInventory> getInventory() async {
    final json = await _rpc('catdex_get_inventory', const {});
    final cards = _maps(json['cards']).map(NakamaCard.new).toList();
    return NakamaInventory(cards);
  }

  Future<int> upsertInventory(List<Map<String, dynamic>> cards) async {
    final json = await _rpc('catdex_upsert_inventory', {
      'cards': cards,
    }, queueWhenOffline: true);
    return (json['upserted'] as num?)?.toInt() ?? 0;
  }

  Future<NakamaEnrollResult> enroll({
    required String fingerprint,
    required String name,
    required String breed,
    required double breedConfidence,
    required String h3Cell,
    required double lat,
    required double lng,
    required double accuracyM,
    required DateTime capturedAt,
    required int baseAttack,
    required int baseDefense,
    required int baseSpeed,
    String ability = '',
    String accentColor = '',
    String? requestId,
  }) async {
    final json = await _rpc('catdex_enroll', {
      'requestId': requestId ?? uuid.v4(),
      'fingerprint': fingerprint,
      'name': name,
      'breed': breed,
      'breedConfidence': breedConfidence,
      'h3Cell': h3Cell,
      'lat': lat,
      'lng': lng,
      'accuracyM': accuracyM,
      'capturedAt': capturedAt.toUtc().toIso8601String(),
      'baseAttack': baseAttack,
      'baseDefense': baseDefense,
      'baseSpeed': baseSpeed,
      'ability': ability,
      'accentColor': accentColor,
    }, queueWhenOffline: true);
    return NakamaEnrollResult(
      card: NakamaCard(_map(json['card'])),
      idempotent: json['idempotent'] as bool? ?? false,
      auditFlags: (json['auditFlags'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Future<NakamaFeedResult> feed({
    required String cardId,
    required int amount,
    String? requestId,
  }) async {
    final json = await _rpc('catdex_feed', {
      'requestId': requestId ?? uuid.v4(),
      'cardId': cardId,
      'amount': amount,
    }, queueWhenOffline: true);
    return NakamaFeedResult(
      cardId: json['cardId'] as String? ?? '',
      level: (json['level'] as num?)?.toInt() ?? 1,
      xp: (json['xp'] as num?)?.toInt() ?? 0,
      xpAwarded: (json['xpAwarded'] as num?)?.toInt() ?? 0,
      idempotent: json['idempotent'] as bool? ?? false,
    );
  }

  Future<NakamaCareState> getCareState(String cardId) async {
    final json = await _rpc('catdex_get_care_state', {'cardId': cardId});
    return NakamaCareState.fromJson(json);
  }

  Future<NakamaCareState> careAction({
    required String cardId,
    required String action,
    String? requestId,
  }) async {
    final json = await _rpc('catdex_care_action', {
      'requestId': requestId ?? uuid.v4(),
      'cardId': cardId,
      'action': action,
    }, queueWhenOffline: true);
    return NakamaCareState.fromJson(json);
  }

  Future<List<NakamaEvent>> nearbyEvents(List<String> h3Cells) async {
    final json = await _rpc('catdex_nearby_events', {'h3Cells': h3Cells});
    return _maps(json['events']).map(NakamaEvent.new).toList();
  }

  Future<NakamaContributionResult> contributeEvent({
    required String eventId,
    required int amount,
    required String h3Cell,
    required double lat,
    required double lng,
    required double accuracyM,
    required String type,
    String squadId = '',
    String checkpointId = '',
    bool stationary = false,
    String? requestId,
  }) async {
    final json = await _rpc('catdex_contribute_event', {
      'requestId': requestId ?? uuid.v4(),
      'eventId': eventId,
      'amount': amount,
      'h3Cell': h3Cell,
      'lat': lat,
      'lng': lng,
      'accuracyM': accuracyM,
      'type': type,
      'squadId': squadId,
      'checkpointId': checkpointId,
      'stationary': stationary,
    }, queueWhenOffline: true);
    return NakamaContributionResult(
      eventId: json['eventId'] as String? ?? '',
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      goal: (json['goal'] as num?)?.toInt() ?? 0,
      accepted: (json['accepted'] as num?)?.toInt() ?? 0,
      idempotent: json['idempotent'] as bool? ?? false,
      personalReward: (json['personalReward'] as num?)?.toInt() ?? 0,
      communityReward: (json['communityReward'] as num?)?.toInt() ?? 0,
      remainingCap: (json['remainingCap'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Map<String, dynamic>> eventSummary(String eventId) =>
      _rpc('catdex_event_summary', {'eventId': eventId});

  Future<NakamaCard> getOpponent({
    required String cardId,
    String? h3Cell,
  }) async {
    final json = await _rpc('catdex_get_opponent', {
      'cardId': cardId,
      'h3Cell': ?h3Cell,
    });
    return NakamaCard(_map(json['opponent']));
  }

  Future<NakamaBattleResult> resolveBattle({
    required String cardId,
    required String opponentCardId,
    String? requestId,
  }) async {
    final json = await _rpc('catdex_resolve_battle', {
      'requestId': requestId ?? uuid.v4(),
      'cardId': cardId,
      'opponentCardId': opponentCardId,
    }, queueWhenOffline: true);
    return NakamaBattleResult(json);
  }

  Future<NakamaBattleState> startBattle({
    required String cardId,
    required String opponentCardId,
    bool localDevelopmentOpponent = false,
    String? requestId,
  }) async {
    final json = await _rpc('catdex_battle_start', {
      'requestId': requestId ?? uuid.v4(),
      'cardId': cardId,
      'opponentCardId': opponentCardId,
      'localDevelopmentOpponent': localDevelopmentOpponent,
    });
    return NakamaBattleState(AuthoritativeBattleState.fromJson(json));
  }

  Future<NakamaBattleState> getBattle({
    String matchId = '',
    String cardId = '',
  }) async {
    final json = await _rpc('catdex_battle_get', {
      'matchId': matchId,
      'cardId': cardId,
    });
    return NakamaBattleState(AuthoritativeBattleState.fromJson(json));
  }

  Future<NakamaBattleState> submitBattleAction({
    required String matchId,
    required int expectedRevision,
    required TacticalAction action,
    String? requestId,
  }) async {
    final json = await _rpc('catdex_battle_action', {
      'requestId': requestId ?? uuid.v4(),
      'matchId': matchId,
      'expectedRevision': expectedRevision,
      'action': action.name,
    });
    return NakamaBattleState(AuthoritativeBattleState.fromJson(json));
  }

  Future<int> flushOutbox() async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    try {
      final pending = List<String>.of(
        preferences.getStringList(_outboxKey) ?? const [],
      );
      while (pending.isNotEmpty) {
        final item = _map(jsonDecode(pending.first));
        try {
          await _rpc(
            item['rpc'] as String,
            _map(item['payload']),
            retryAuthentication: true,
          );
        } on NakamaNetworkException {
          break;
        } on NakamaTimeoutException {
          break;
        } on NakamaException {
          // Permanent server rejections must not block later operations.
        }
        pending.removeAt(0);
        sent++;
        await preferences.setStringList(_outboxKey, pending);
      }
      return sent;
    } finally {
      _flushing = false;
    }
  }

  Future<Map<String, dynamic>> _rpc(
    String id,
    Map<String, dynamic> payload, {
    bool queueWhenOffline = false,
    bool retryAuthentication = true,
  }) async {
    try {
      final active = await session();
      final response = await _http
          .post(
            config.uri('/v2/rpc/$id'),
            headers: {
              HttpHeaders.authorizationHeader: 'Bearer ${active.token}',
              HttpHeaders.contentTypeHeader: 'application/json',
            },
            // Nakama REST accepts the runtime payload as a JSON string body.
            body: jsonEncode(jsonEncode(payload)),
          )
          .timeout(config.requestTimeout);
      if (response.statusCode == 401 && retryAuthentication) {
        await _clearSession();
        return await _rpc(
          id,
          payload,
          // Let the outer attempt queue once if this retry cannot connect.
          queueWhenOffline: false,
          retryAuthentication: false,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _serverException(response);
      }
      final envelope = _map(jsonDecode(response.body));
      final rawPayload = envelope['payload'];
      if (rawPayload is! String) {
        throw const NakamaException('RPC response omitted its payload');
      }
      final decoded = jsonDecode(rawPayload);
      return _map(decoded);
    } on TimeoutException {
      if (queueWhenOffline) {
        await _enqueue(id, payload);
        throw const NakamaQueuedException('Request timed out and was queued');
      }
      throw const NakamaTimeoutException('Nakama request timed out');
    } on SocketException catch (error) {
      if (queueWhenOffline) {
        await _enqueue(id, payload);
        throw NakamaQueuedException('Request was queued: ${error.message}');
      }
      throw NakamaNetworkException(error.message);
    } on http.ClientException catch (error) {
      if (queueWhenOffline) {
        await _enqueue(id, payload);
        throw NakamaQueuedException('Request was queued: ${error.message}');
      }
      throw NakamaNetworkException(error.message);
    } on NakamaTimeoutException catch (error) {
      if (queueWhenOffline) {
        await _enqueue(id, payload);
        throw NakamaQueuedException('${error.message}; request was queued');
      }
      rethrow;
    } on NakamaNetworkException catch (error) {
      if (queueWhenOffline) {
        await _enqueue(id, payload);
        throw NakamaQueuedException('${error.message}; request was queued');
      }
      rethrow;
    } on NakamaException catch (error) {
      if (queueWhenOffline &&
          error.statusCode != null &&
          error.statusCode! >= 500) {
        await _enqueue(id, payload);
        throw NakamaQueuedException('Server unavailable; request was queued');
      }
      rethrow;
    } on FormatException catch (error) {
      throw NakamaException('Invalid Nakama response: ${error.message}');
    }
  }

  Future<NakamaSession> _loadOrAuthenticate() async {
    _validateConfiguration();
    final token = preferences.getString(_tokenKey);
    final refreshToken = preferences.getString(_refreshTokenKey);
    if (token != null && _isUsable(token)) {
      return NakamaSession(
        token: token,
        refreshToken: refreshToken ?? '',
        expiresAt: _jwtExpiry(token)!,
      );
    }
    if (refreshToken != null && _isUsable(refreshToken)) {
      try {
        return await _refresh(refreshToken);
      } on NakamaException {
        await _clearSession();
      }
    }
    return _authenticateDevice();
  }

  Future<NakamaSession> _authenticateDevice() async {
    final response = await _sendAuth(
      config.uri('/v2/account/authenticate/device', {'create': 'true'}),
      {'id': await deviceId()},
    );
    return _saveSession(response);
  }

  Future<NakamaSession> _refresh(String refreshToken) async {
    final response = await _sendAuth(
      config.uri('/v2/account/session/refresh'),
      {'token': refreshToken},
    );
    return _saveSession(response);
  }

  Future<http.Response> _sendAuth(Uri uri, Map<String, dynamic> body) async {
    try {
      final response = await _http
          .post(
            uri,
            headers: {
              HttpHeaders.authorizationHeader: _basicAuthorization,
              HttpHeaders.contentTypeHeader: 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(config.requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _serverException(response);
      }
      return response;
    } on TimeoutException {
      throw const NakamaTimeoutException('Nakama authentication timed out');
    } on SocketException catch (error) {
      throw NakamaNetworkException(error.message);
    } on http.ClientException catch (error) {
      throw NakamaNetworkException(error.message);
    }
  }

  Future<NakamaSession> _saveSession(http.Response response) async {
    final json = _map(jsonDecode(response.body));
    final token = json['token'] as String?;
    final refreshToken = json['refresh_token'] as String? ?? '';
    final expiry = token == null ? null : _jwtExpiry(token);
    if (token == null || expiry == null) {
      throw const NakamaException('Authentication returned an invalid token');
    }
    await preferences.setString(_tokenKey, token);
    await preferences.setString(_refreshTokenKey, refreshToken);
    return NakamaSession(
      token: token,
      refreshToken: refreshToken,
      expiresAt: expiry,
    );
  }

  Future<void> _clearSession() async {
    await preferences.remove(_tokenKey);
    await preferences.remove(_refreshTokenKey);
  }

  Future<void> _enqueue(String rpc, Map<String, dynamic> payload) async {
    final pending = List<String>.of(
      preferences.getStringList(_outboxKey) ?? const [],
    );
    pending.add(jsonEncode({'rpc': rpc, 'payload': payload}));
    final overflow = pending.length - config.outboxLimit;
    if (overflow > 0) pending.removeRange(0, overflow);
    await preferences.setStringList(_outboxKey, pending);
  }

  void _validateConfiguration() {
    if (config.serverKey.isEmpty) {
      throw const NakamaConfigurationException(
        'CATDEX_NAKAMA_SERVER_KEY must be set at compile time',
      );
    }
    final uri = Uri.tryParse(config.url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const NakamaConfigurationException(
        'CATDEX_NAKAMA_URL must be an absolute URL',
      );
    }
    // Loopback HTTP is allowed for self-hosted local stacks. Everything else
    // must be HTTPS — do not rely on developmentMode to bypass this.
    if (uri.scheme != 'https') {
      final host = uri.host;
      final loopback =
          host == '127.0.0.1' || host == 'localhost' || host == '::1';
      if (!loopback) {
        throw const NakamaConfigurationException(
          'Nakama requires HTTPS outside localhost',
        );
      }
    }
  }

  bool _isUsable(String token) {
    final expiry = _jwtExpiry(token);
    return expiry != null &&
        expiry.isAfter(DateTime.now().toUtc().add(const Duration(seconds: 30)));
  }

  DateTime? _jwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final json = _map(
        jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        ),
      );
      final seconds = (json['exp'] as num?)?.toInt();
      return seconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    } on Object {
      return null;
    }
  }

  NakamaException _serverException(http.Response response) {
    try {
      final json = _map(jsonDecode(response.body));
      return NakamaException(
        json['message'] as String? ?? 'Nakama request failed',
        statusCode: response.statusCode,
        code: (json['code'] as num?)?.toInt(),
      );
    } on Object {
      return NakamaException(
        'Nakama request failed (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    throw const FormatException('Expected a JSON object');
  }

  static List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List) throw const FormatException('Expected a JSON list');
    return value.map(_map).toList();
  }
}
