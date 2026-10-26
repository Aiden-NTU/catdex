import 'dart:convert';
import 'dart:io';

import 'package:catdex/game/geo_cell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

const _runIntegration = bool.fromEnvironment('CATDEX_RUN_NAKAMA_INTEGRATION');
const _base = 'http://127.0.0.1:7350';

void main() {
  test('two users share authoritative reconnectable battle state', () async {
    final suffix = const Uuid().v4();
    final a = await _WireUser.create('battle-a-$suffix');
    final b = await _WireUser.create('battle-b-$suffix');
    final aCard = await a.enroll('a-$suffix', speed: 75);
    final bCard = await b.enroll('b-$suffix', speed: 55);

    final started = await a.rpc('catdex_battle_start', {
      'requestId': 'start-$suffix',
      'cardId': aCard,
      'opponentCardId': bCard,
      'localDevelopmentOpponent': false,
    });
    final matchId = started['matchId'] as String;
    expect(matchId, isNotEmpty);
    expect(started['revision'], 0);

    final seenByB = await b.rpc('catdex_battle_get', {
      'matchId': matchId,
      'cardId': '',
    });
    expect(seenByB, started);

    final turnUser = started['turnUserId'] as String;
    final actor = turnUser == a.userId ? a : b;
    final observer = turnUser == a.userId ? b : a;
    final advanced = await actor.rpc('catdex_battle_action', {
      'requestId': 'action-$suffix',
      'matchId': matchId,
      'expectedRevision': 0,
      'action': 'attack',
    });
    expect(advanced['revision'], 1);
    expect(advanced['turnUserId'], isNot(turnUser));

    final reconnected = await observer.rpc('catdex_battle_get', {
      'matchId': matchId,
      'cardId': '',
    });
    expect(reconnected, advanced);
  }, skip: !_runIntegration);
}

class _WireUser {
  _WireUser(this.token, this.userId);

  final String token;
  final String userId;

  static Future<_WireUser> create(String deviceId) async {
    final response = await http.post(
      Uri.parse('$_base/v2/account/authenticate/device?create=true'),
      headers: {
        HttpHeaders.authorizationHeader:
            'Basic ${base64Encode(utf8.encode('localdevkey:'))}',
        HttpHeaders.contentTypeHeader: 'application/json',
      },
      body: jsonEncode({'id': deviceId}),
    );
    expect(response.statusCode, 200, reason: response.body);
    final token = (jsonDecode(response.body) as Map)['token'] as String;
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
    ) as Map;
    return _WireUser(token, payload['uid'] as String);
  }

  Future<String> enroll(String fingerprint, {required int speed}) async {
    const lat = 51.5074;
    const lng = -0.1278;
    final result = await rpc('catdex_enroll', {
      'requestId': 'enroll-$fingerprint',
      'fingerprint': fingerprint,
      'name': 'Battle $fingerprint',
      'breed': 'Abyssinian',
      'breedConfidence': .95,
      'h3Cell': GeoCell.fromLatLng(lat, lng),
      'lat': lat,
      'lng': lng,
      'accuracyM': 5,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'baseAttack': 55,
      'baseDefense': 50,
      'baseSpeed': speed,
      'ability': 'Meteor Meow',
      'accentColor': '#EF4444',
    });
    return ((result['card'] as Map)['id']) as String;
  }

  Future<Map<String, dynamic>> rpc(
    String name,
    Map<String, dynamic> payload,
  ) async {
    final response = await http.post(
      Uri.parse('$_base/v2/rpc/$name'),
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $token',
        HttpHeaders.contentTypeHeader: 'application/json',
      },
      body: jsonEncode(jsonEncode(payload)),
    );
    expect(response.statusCode, 200, reason: response.body);
    final envelope = jsonDecode(response.body) as Map<String, dynamic>;
    return (jsonDecode(envelope['payload'] as String) as Map)
        .cast<String, dynamic>();
  }
}
