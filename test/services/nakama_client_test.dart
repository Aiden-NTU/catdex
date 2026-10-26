import 'dart:convert';

import 'package:catdex/config/nakama_config.dart';
import 'package:catdex/services/nakama_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('authenticates device and sends the Nakama RPC envelope', () async {
    final requests = <http.Request>[];
    final httpClient = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/v2/account/authenticate/device') {
        return http.Response(
          jsonEncode({
            'token': _jwt(DateTime.now().add(const Duration(hours: 1))),
            'refresh_token': _jwt(DateTime.now().add(const Duration(days: 1))),
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'payload': jsonEncode({
            'cards': [
              {'id': 'card-1', 'name': 'Mochi', 'level': 2, 'xp': 120},
            ],
          }),
        }),
        200,
      );
    });
    final client = NakamaClient(
      config: _config(),
      preferences: await SharedPreferences.getInstance(),
      httpClient: httpClient,
    );

    final inventory = await client.getInventory();

    expect(inventory.cards.single.id, 'card-1');
    expect(requests, hasLength(2));
    expect(
      requests.first.headers['authorization'],
      'Basic ${base64Encode(utf8.encode('localdevkey:'))}',
    );
    expect(jsonDecode(requests.first.body), contains('id'));
    expect(requests.last.headers['authorization'], startsWith('Bearer '));
    final payload = jsonDecode(requests.last.body) as String;
    expect(jsonDecode(payload), isEmpty);
  });

  test('refreshes an expired access token before RPC', () async {
    final expired = _jwt(DateTime.now().subtract(const Duration(minutes: 1)));
    final refresh = _jwt(DateTime.now().add(const Duration(days: 1)));
    SharedPreferences.setMockInitialValues({
      'catdex_nakama_token': expired,
      'catdex_nakama_refresh_token': refresh,
    });
    var refreshCalls = 0;
    final httpClient = MockClient((request) async {
      if (request.url.path == '/v2/account/session/refresh') {
        refreshCalls++;
        expect(jsonDecode(request.body), {'token': refresh});
        return http.Response(
          jsonEncode({
            'token': _jwt(DateTime.now().add(const Duration(hours: 1))),
            'refresh_token': refresh,
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'payload': jsonEncode({'cards': <Object>[]}),
        }),
        200,
      );
    });
    final client = NakamaClient(
      config: _config(),
      preferences: await SharedPreferences.getInstance(),
      httpClient: httpClient,
    );

    await client.getInventory();

    expect(refreshCalls, 1);
  });

  test('queues mutating calls offline and bounds the outbox', () async {
    final preferences = await SharedPreferences.getInstance();
    final client = NakamaClient(
      config: NakamaConfig(
        url: 'http://localhost:7350',
        serverKey: 'localdevkey',
        developmentMode: true,
        outboxLimit: 2,
      ),
      preferences: preferences,
      httpClient: MockClient(
        (_) async => throw http.ClientException('offline'),
      ),
    );

    for (var i = 0; i < 3; i++) {
      await expectLater(
        client.upsertInventory([
          {'id': 'card-$i'},
        ]),
        throwsA(isA<NakamaQueuedException>()),
      );
    }

    final outbox = preferences.getStringList('catdex_nakama_outbox_v1')!;
    expect(outbox, hasLength(2));
    expect(outbox.first, contains('card-1'));
    expect(outbox.last, contains('card-2'));
  });

  test(
    'rejects plaintext transport outside explicit development mode',
    () async {
      final client = NakamaClient(
        config: const NakamaConfig(
          url: 'http://nakama.example.test',
          serverKey: 'secret',
        ),
        preferences: await SharedPreferences.getInstance(),
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

      await expectLater(
        client.getInventory(),
        throwsA(isA<NakamaConfigurationException>()),
      );
    },
  );

  test('parses authoritative care action and economy state', () async {
    final httpClient = MockClient((request) async {
      if (request.url.path == '/v2/account/authenticate/device') {
        return http.Response(
          jsonEncode({
            'token': _jwt(DateTime.now().add(const Duration(hours: 1))),
            'refresh_token': _jwt(DateTime.now().add(const Duration(days: 1))),
          }),
          200,
        );
      }
      expect(request.url.path, '/v2/rpc/catdex_care_action');
      final payload = jsonDecode(request.body) as String;
      expect(jsonDecode(payload), containsPair('action', 'train'));
      return http.Response(
        jsonEncode({
          'payload': jsonEncode({
            'card': {
              'id': 'cat-1',
              'level': 2,
              'xp': 120,
              'energy': 80,
              'abilityMastery': 10,
            },
            'account': {
              'pawCoins': 4,
              'dailyEarned': 4,
              'dailyCap': 100,
              'treats': 5,
              'groomingSupplies': 3,
            },
            'action': 'train',
            'xpAwarded': 30,
            'coinsAwarded': 4,
          }),
        }),
        200,
      );
    });
    final client = NakamaClient(
      config: _config(),
      preferences: await SharedPreferences.getInstance(),
      httpClient: httpClient,
    );

    final result = await client.careAction(
      cardId: 'cat-1',
      action: 'train',
      requestId: 'request-1',
    );

    expect(result.card.level, 2);
    expect(result.card.abilityMastery, 10);
    expect(result.account.pawCoins, 4);
    expect(result.xpAwarded, 30);
  });

  test('sends privacy-bounded event contribution context', () async {
    late Map<String, dynamic> sent;
    final httpClient = MockClient((request) async {
      if (request.url.path == '/v2/account/authenticate/device') {
        return http.Response(
          jsonEncode({
            'token': _jwt(DateTime.now().add(const Duration(hours: 1))),
            'refresh_token': _jwt(DateTime.now().add(const Duration(days: 1))),
          }),
          200,
        );
      }
      sent = (jsonDecode(jsonDecode(request.body) as String) as Map)
          .cast<String, dynamic>();
      return http.Response(
        jsonEncode({
          'payload': jsonEncode({
            'eventId': 'event-1',
            'progress': 12,
            'goal': 100,
            'accepted': 1,
            'remainingCap': 9,
            'personalReward': 1,
            'communityReward': 0,
            'idempotent': false,
          }),
        }),
        200,
      );
    });
    final client = NakamaClient(
      config: _config(),
      preferences: await SharedPreferences.getInstance(),
      httpClient: httpClient,
    );

    final result = await client.contributeEvent(
      eventId: 'event-1',
      requestId: 'request-1',
      amount: 1,
      h3Cell: '89194ad',
      lat: 51.5074,
      lng: -0.1278,
      accuracyM: 12,
      type: 'checkpoint',
      checkpointId: 'accessible',
      stationary: true,
    );

    expect(sent, containsPair('h3Cell', '89194ad'));
    expect(sent, isNot(contains('userId')));
    expect(sent, containsPair('stationary', true));
    expect(result.remainingCap, 9);
  });
}

NakamaConfig _config() => const NakamaConfig(
  url: 'http://localhost:7350',
  serverKey: 'localdevkey',
  developmentMode: true,
);

String _jwt(DateTime expiry) {
  String part(Map<String, Object> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.'
      '${part({'exp': expiry.millisecondsSinceEpoch ~/ 1000})}.signature';
}
