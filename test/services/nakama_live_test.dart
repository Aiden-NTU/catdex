import 'dart:io';

import 'package:catdex/config/nakama_config.dart';
import 'package:catdex/game/geo_cell.dart';
import 'package:catdex/services/nakama_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _runIntegration = bool.fromEnvironment('CATDEX_RUN_NAKAMA_INTEGRATION');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('authenticates and calls the local Nakama runtime', () async {
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = null;
    final client = NakamaClient(
      config: const NakamaConfig(
        url: 'http://127.0.0.1:7350',
        serverKey: 'localdevkey',
        developmentMode: true,
      ),
      preferences: await SharedPreferences.getInstance(),
      httpClient: IOClient(HttpClient()),
    );
    final suffix = const Uuid().v4();
    const lat = 51.5074;
    const lng = -0.1278;
    final cell = GeoCell.fromLatLng(lat, lng);
    final card = {
      'id': 'wire-$suffix',
      'name': 'Wire Cat',
      'breed': 'Abyssinian',
      'breedConfidence': 0.9,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'stats': {'attack': 60, 'defense': 55, 'speed': 65, 'battlePower': 180},
      'stars': 2,
      'h3Cell': 'integration-cell',
      'wins': 0,
      'losses': 0,
    };

    expect(await client.healthcheck(), isTrue);
    expect(await client.upsertInventory([card]), 1);
    expect(
      (await client.getInventory()).cards.map((item) => item.id),
      contains(card['id']),
    );

    final requestId = 'enroll-$suffix';
    final enrolled = await client.enroll(
      requestId: requestId,
      fingerprint: 'integration-$suffix',
      name: 'Server Cat',
      breed: 'Abyssinian',
      breedConfidence: 0.95,
      h3Cell: cell,
      lat: lat,
      lng: lng,
      accuracyM: 5,
      capturedAt: DateTime.now().toUtc(),
      baseAttack: 60,
      baseDefense: 55,
      baseSpeed: 65,
    );
    expect(enrolled.card.id, isNotEmpty);
    final replayed = await client.enroll(
      requestId: requestId,
      fingerprint: 'changed-on-replay-$suffix',
      name: 'Changed',
      breed: 'Abyssinian',
      breedConfidence: 0.95,
      h3Cell: 'deliberately-wrong',
      lat: 0,
      lng: 0,
      accuracyM: 999,
      capturedAt: DateTime.utc(2000),
      baseAttack: 60,
      baseDefense: 55,
      baseSpeed: 65,
    );
    expect(replayed.idempotent, isTrue);
    expect(replayed.card.id, enrolled.card.id);
    await expectLater(
      client.enroll(
        requestId: 'mismatch-$suffix',
        fingerprint: 'mismatch-$suffix',
        name: 'Mismatch',
        breed: 'Abyssinian',
        breedConfidence: 0.95,
        h3Cell: 'deliberately-wrong',
        lat: lat,
        lng: lng,
        accuracyM: 5,
        capturedAt: DateTime.now().toUtc(),
        baseAttack: 60,
        baseDefense: 55,
        baseSpeed: 65,
      ),
      throwsA(isA<NakamaException>()),
    );
    final fed = await client.feed(cardId: enrolled.card.id, amount: 2);
    expect(fed.xpAwarded, 20);
    final careBefore = await client.getCareState(enrolled.card.id);
    expect(careBefore.card.energy, inInclusiveRange(0, 100));
    final careRequest = 'care-$suffix';
    final trained = await client.careAction(
      cardId: enrolled.card.id,
      action: 'train',
      requestId: careRequest,
    );
    expect(trained.xpAwarded, 30);
    expect(trained.card.abilityMastery, 10);
    expect(trained.account.pawCoins, greaterThanOrEqualTo(0));
    final replayedCare = await client.careAction(
      cardId: enrolled.card.id,
      action: 'train',
      requestId: careRequest,
    );
    expect(replayedCare.idempotent, isTrue);
    expect(replayedCare.card.xp, trained.card.xp);
    await expectLater(
      client.nearbyEvents(['integration-cell']),
      throwsA(isA<NakamaException>()),
    );

    final nearby = await client.nearbyEvents(GeoCell.neighborhood(cell));
    final active = nearby.where((event) => event.state == 'active').toList();
    if (active.isNotEmpty) {
      final event = active.first;
      final type = switch (event.kind) {
        'cat_cafe_rally' => 'feed',
        'cardboard_fortress' => 'squad',
        _ => 'checkpoint',
      };
      final eventRequest = 'event-$suffix';
      final contribution = await client.contributeEvent(
        requestId: eventRequest,
        eventId: event.id,
        amount: 1,
        h3Cell: cell,
        lat: lat,
        lng: lng,
        accuracyM: 5,
        type: type,
        squadId: type == 'squad' ? 'integration' : '',
        checkpointId: type == 'checkpoint' ? 'accessible' : '',
        stationary: type == 'checkpoint',
      );
      expect(contribution.accepted, 1);
      final replay = await client.contributeEvent(
        requestId: eventRequest,
        eventId: event.id,
        amount: 1,
        h3Cell: cell,
        lat: lat,
        lng: lng,
        accuracyM: 5,
        type: type,
        squadId: type == 'squad' ? 'integration' : '',
        checkpointId: type == 'checkpoint' ? 'accessible' : '',
        stationary: type == 'checkpoint',
      );
      expect(replay.idempotent, isTrue);
    }
  }, skip: !_runIntegration);
}
