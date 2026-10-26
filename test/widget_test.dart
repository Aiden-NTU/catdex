import 'package:catdex/models/cat.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  test('collection card model survives its persistence boundary', () {
    final original = catFixture(
      id: 'smoke-cat',
      name: 'Pixel',
      breed: 'Siamese',
      stars: 5,
      attack: 91,
      defense: 62,
      speed: 88,
    );

    final restored = CollectedCat.fromMap(original.toMap());

    expect(restored.id, original.id);
    expect(restored.embedding, orderedEquals(original.embedding));
    expect(restored.createdAt, original.createdAt);
    expect(restored.battlePower, 241);
    expect(restored.toSyncJson(), containsPair('stars', 5));
    expect(restored.toSyncJson()['stats'], containsPair('ability', 'Pounce'));
  });
}
