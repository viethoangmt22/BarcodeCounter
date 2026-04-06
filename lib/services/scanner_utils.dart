import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerUtils {
  /// Defines common scanner settings for high-speed robust detection.
  static const int detectionTimeoutMs = 100;
  static const DetectionSpeed detectionSpeed = DetectionSpeed.unrestricted;

  /// Common ROI rectangle (centered 50% of the image).
  static Rect getCenterRoi(Size imageSize) {
    if (imageSize.isEmpty) return Rect.zero;
    return Rect.fromLTWH(
      imageSize.width * 0.25,
      imageSize.height * 0.25,
      imageSize.width * 0.5,
      imageSize.height * 0.5,
    );
  }

  /// Checks if a barcode's center point is within the 50% center ROI.
  static bool isInsideCenterRoi(Barcode barcode, Size imageSize) {
    final corners = barcode.corners;
    if (corners.isEmpty || imageSize.isEmpty) {
      return false;
    }

    final minX = corners.map((p) => p.dx).reduce(min);
    final maxX = corners.map((p) => p.dx).reduce(max);
    final minY = corners.map((p) => p.dy).reduce(min);
    final maxY = corners.map((p) => p.dy).reduce(max);

    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final roiRect = getCenterRoi(imageSize);

    return roiRect.contains(center);
  }

  /// Extracts unique, sorted, non-empty barcodes that are within the center ROI.
  /// Falls back to all detected barcodes if ROI coordinates are unavailable.
  static List<String> pickDetectedCodes(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) {
      return const [];
    }

    final imageSize = capture.size;
    final centerCodes = <String>{};
    for (final barcode in capture.barcodes) {
      if (isInsideCenterRoi(barcode, imageSize)) {
        final value = (barcode.rawValue ?? '').trim();
        if (value.isNotEmpty) {
          centerCodes.add(value);
        }
      }
    }

    if (centerCodes.isNotEmpty) {
      return centerCodes.toList()..sort();
    }

    // Fallback: Some devices or formats might not provide corner points.
    return capture.barcodes
        .map((e) => (e.rawValue ?? '').trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  /// Calculates the center offset of a barcode.
  static Offset? getBarcodeCenter(Barcode barcode) {
    final corners = barcode.corners;
    if (corners.isEmpty) {
      return null;
    }

    final minX = corners.map((p) => p.dx).reduce(min);
    final maxX = corners.map((p) => p.dx).reduce(max);
    final minY = corners.map((p) => p.dy).reduce(min);
    final maxY = corners.map((p) => p.dy).reduce(max);
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }
}
