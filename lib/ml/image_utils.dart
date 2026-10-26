import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/scan_result.dart';

class ImageUtils {
  static img.Image? decodeBytes(Uint8List bytes) {
    return img.decodeImage(bytes);
  }

  /// Convert a camera preview frame (YUV420 / BGRA) to RGB [img.Image].
  static img.Image? convertCameraImage(
    CameraImage cameraImage, {
    required int sensorOrientation,
  }) {
    try {
      img.Image base;
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        base = _yuv420ToImage(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        base = _bgraToImage(cameraImage);
      } else {
        return null;
      }

      // Normalize orientation so "up" matches preview for portrait phones.
      if (sensorOrientation == 90) {
        return img.copyRotate(base, angle: 90);
      }
      if (sensorOrientation == 270) {
        return img.copyRotate(base, angle: -90);
      }
      if (sensorOrientation == 180) {
        return img.copyRotate(base, angle: 180);
      }
      return base;
    } catch (e, st) {
      debugPrint('convertCameraImage failed: $e\n$st');
      return null;
    }
  }

  static img.Image _bgraToImage(CameraImage cameraImage) {
    final bytes = cameraImage.planes[0].bytes;
    final w = cameraImage.width;
    final h = cameraImage.height;
    final out = img.Image(width: w, height: h);
    final stride = cameraImage.planes[0].bytesPerRow;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * stride + x * 4;
        if (i + 2 >= bytes.length) continue;
        final b = bytes[i];
        final g = bytes[i + 1];
        final r = bytes[i + 2];
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return out;
  }

  static img.Image _yuv420ToImage(CameraImage cameraImage) {
    final w = cameraImage.width;
    final h = cameraImage.height;
    final yPlane = cameraImage.planes[0];
    final uPlane = cameraImage.planes[1];
    final vPlane = cameraImage.planes[2];
    final out = img.Image(width: w, height: h);

    final yRow = yPlane.bytesPerRow;
    final uvRow = uPlane.bytesPerRow;
    final uvPixel = uPlane.bytesPerPixel ?? 1;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final yp = yPlane.bytes[y * yRow + x];
        final uvIndex = (y >> 1) * uvRow + (x >> 1) * uvPixel;
        final up = uPlane.bytes[uvIndex];
        final vp = vPlane.bytes[uvIndex];
        final r = (yp + 1.370705 * (vp - 128)).round().clamp(0, 255);
        final g = (yp - 0.337633 * (up - 128) - 0.698001 * (vp - 128))
            .round()
            .clamp(0, 255);
        final b = (yp + 1.732446 * (up - 128)).round().clamp(0, 255);
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return out;
  }

  static img.Image cropBox(img.Image full, DetectionBox box, {double pad = 0.05}) {
    final l = ((box.left - pad) * full.width).floor().clamp(0, full.width - 1);
    final t = ((box.top - pad) * full.height).floor().clamp(0, full.height - 1);
    final r = ((box.right + pad) * full.width).ceil().clamp(l + 1, full.width);
    final b = ((box.bottom + pad) * full.height).ceil().clamp(t + 1, full.height);
    return img.copyCrop(
      full,
      x: l,
      y: t,
      width: r - l,
      height: b - t,
    );
  }

  static Uint8List encodeJpeg(img.Image image, {int quality = 85}) {
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }

  /// Resize keeping aspect, letterbox to [size]x[size] with mean fill.
  static Float32List letterboxFloat(img.Image src, int size) {
    final scale = size / (src.width > src.height ? src.width : src.height);
    final nw = (src.width * scale).round().clamp(1, size);
    final nh = (src.height * scale).round().clamp(1, size);
    final resized = img.copyResize(src, width: nw, height: nh);
    final out = Float32List(size * size * 3);
    final padX = (size - nw) ~/ 2;
    final padY = (size - nh) ~/ 2;
    var i = 0;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (x >= padX && x < padX + nw && y >= padY && y < padY + nh) {
          final p = resized.getPixel(x - padX, y - padY);
          out[i++] = p.r / 255.0;
          out[i++] = p.g / 255.0;
          out[i++] = p.b / 255.0;
        } else {
          out[i++] = 0.5;
          out[i++] = 0.5;
          out[i++] = 0.5;
        }
      }
    }
    return out;
  }

  static Uint8List letterboxUint8(img.Image src, int size) {
    final scale = size / (src.width > src.height ? src.width : src.height);
    final nw = (src.width * scale).round().clamp(1, size);
    final nh = (src.height * scale).round().clamp(1, size);
    final resized = img.copyResize(src, width: nw, height: nh);
    final out = Uint8List(size * size * 3);
    final padX = (size - nw) ~/ 2;
    final padY = (size - nh) ~/ 2;
    var i = 0;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (x >= padX && x < padX + nw && y >= padY && y < padY + nh) {
          final p = resized.getPixel(x - padX, y - padY);
          out[i++] = p.r.toInt();
          out[i++] = p.g.toInt();
          out[i++] = p.b.toInt();
        } else {
          out[i++] = 128;
          out[i++] = 128;
          out[i++] = 128;
        }
      }
    }
    return out;
  }

  static Size sizeOf(img.Image image) =>
      Size(image.width.toDouble(), image.height.toDouble());
}
