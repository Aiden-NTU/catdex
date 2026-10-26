import 'dart:convert';
import 'dart:typed_data';

import 'package:catdex/models/cat.dart';
import 'package:catdex/models/scan_result.dart';
import 'package:image/image.dart' as img;

CollectedCat catFixture({
  String id = 'cat-1',
  String name = 'Mochi',
  String breed = 'Mixed',
  int stars = 3,
  int attack = 70,
  int defense = 60,
  int speed = 50,
  String ability = 'Pounce',
  Float32List? embedding,
}) {
  return CollectedCat(
    id: id,
    name: name,
    breed: breed,
    breedConfidence: 0.9,
    embedding: embedding ?? Float32List.fromList([0.6, 0.8]),
    createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    statsJson: jsonEncode({
      'attack': attack,
      'defense': defense,
      'speed': speed,
      'battlePower': attack + defense + speed,
      'ability': ability,
    }),
    stars: stars,
    h3Cell: 'g_100_-20',
    lat: 0.5025,
    lng: -0.0975,
  );
}

DetectionBox boxFixture({
  double left = 0.2,
  double top = 0.2,
  double right = 0.7,
  double bottom = 0.7,
  double score = 0.9,
}) {
  return DetectionBox(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    score: score,
  );
}

img.Image checkerboardImage({
  int width = 64,
  int height = 64,
  int tile = 2,
  int dark = 40,
  int light = 220,
}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = ((x ~/ tile) + (y ~/ tile)).isEven ? dark : light;
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

img.Image solidImage(int value, {int width = 64, int height = 64}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(value, value, value));
  return image;
}
