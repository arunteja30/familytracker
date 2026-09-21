import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../constants/app_colors.dart';

class MarkerGenerator {
  // In-memory cache for generated marker BitmapDescriptors
  static final Map<String, BitmapDescriptor> _markerCache = {};

  // Clear cache if needed (e.g., when profile photo is updated)
  static void clearCache([String? memberPhone]) {
    if (memberPhone != null) {
      _markerCache.removeWhere((key, _) => key.contains(memberPhone));
    } else {
      _markerCache.clear();
    }
  }

  // Generate a custom map marker with Member Avatar + Name Label Pill (Cached)
  static Future<BitmapDescriptor> createCustomMemberMarker({
    required String name,
    String? localPhotoPath,
    Color pinColor = AppColors.primary,
  }) async {
    final displayName = name.isNotEmpty ? name : 'Member';
    final initial = displayName[0].toUpperCase();

    // 0. Cache Check for instant 0ms retrieval
    final cacheKey = '${displayName}_${pinColor.toARGB32()}_${localPhotoPath ?? ''}';
    if (_markerCache.containsKey(cacheKey)) {
      return _markerCache[cacheKey]!;
    }

    const double markerWidth = 140;
    const double markerHeight = 110;
    const double avatarRadius = 26;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Draw avatar outer shadow & border
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(
      const Offset(markerWidth / 2, avatarRadius + 4),
      avatarRadius + 2,
      shadowPaint,
    );

    // Avatar background circle
    final circlePaint = Paint()..color = pinColor;
    canvas.drawCircle(
      const Offset(markerWidth / 2, avatarRadius + 4),
      avatarRadius,
      circlePaint,
    );

    // Avatar inner white ring
    final innerRingPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(
      const Offset(markerWidth / 2, avatarRadius + 4),
      avatarRadius - 2,
      innerRingPaint,
    );

    // 2. Check if local photo exists
    bool photoDrawn = false;
    if (!kIsWeb && localPhotoPath != null && localPhotoPath.isNotEmpty) {
      final file = File(localPhotoPath);
      if (file.existsSync()) {
        try {
          final bytes = await file.readAsBytes();
          final codec = await ui.instantiateImageCodec(
            bytes,
            targetWidth: (avatarRadius * 2).toInt(),
            targetHeight: (avatarRadius * 2).toInt(),
          );
          final frameInfo = await codec.getNextFrame();
          final img = frameInfo.image;

          canvas.save();
          final clipPath = Path()
            ..addOval(Rect.fromCircle(
              center: const Offset(markerWidth / 2, avatarRadius + 4),
              radius: avatarRadius - 3,
            ));
          canvas.clipPath(clipPath);
          canvas.drawImage(
            img,
            Offset(
              markerWidth / 2 - img.width / 2,
              (avatarRadius + 4) - img.height / 2,
            ),
            Paint(),
          );
          canvas.restore();
          photoDrawn = true;
        } catch (_) {}
      }
    }

    // 3. Draw initial letter if photo wasn't drawn
    if (!photoDrawn) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (markerWidth - textPainter.width) / 2,
          (avatarRadius + 4) - (textPainter.height / 2),
        ),
      );
    }

    // 4. Draw Pin Stick / Needle pointing down
    final needlePaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(markerWidth / 2 - 2, avatarRadius * 2 + 2),
        const Offset(markerWidth / 2 + 2, avatarRadius * 2 + 2),
        [
          const Color(0xFF64748B),
          const Color(0xFF334155),
          const Color(0xFF1E293B),
        ],
      )
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      const Offset(markerWidth / 2, avatarRadius * 2 + 2),
      const Offset(markerWidth / 2, avatarRadius * 2 + 18),
      needlePaint,
    );

    // Specular highlight spot on sphere
    canvas.drawCircle(
      const Offset(markerWidth / 2 - avatarRadius * 0.35, avatarRadius + 4 - avatarRadius * 0.35),
      avatarRadius * 0.28,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );

    // 5. Draw Name Badge Pill at bottom
    final namePainter = TextPainter(
      text: TextSpan(
        text: displayName.length > 12
            ? '${displayName.substring(0, 10)}...'
            : displayName,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    namePainter.layout();

    final badgeWidth = namePainter.width + 16;
    const badgeHeight = 22.0;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: const Offset(markerWidth / 2, avatarRadius * 2 + 30),
        width: badgeWidth < 60 ? 60 : badgeWidth,
        height: badgeHeight,
      ),
      const Radius.circular(10),
    );

    // Pill shadow
    canvas.drawRRect(
      badgeRect.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Pill background
    canvas.drawRRect(
      badgeRect,
      Paint()..color = Colors.white,
    );

    // Pill border
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = pinColor.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Pill Text
    namePainter.paint(
      canvas,
      Offset(
        (markerWidth - namePainter.width) / 2,
        avatarRadius * 2 + 30 - (namePainter.height / 2),
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      markerWidth.toInt(),
      markerHeight.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      return BitmapDescriptor.defaultMarker;
    }

    final Uint8List uint8list = byteData.buffer.asUint8List();
    final descriptor = BitmapDescriptor.bytes(uint8list);
    _markerCache[cacheKey] = descriptor;
    return descriptor;
  }

  /// Generate a 3D Pushpin / Stick Pin marker (like the red ball stick pin in reference image)
  static Future<BitmapDescriptor> createPushpinMarker({
    required Color pinColor,
    String badgeText = '',
    bool isSelected = false,
  }) async {
    final cacheKey = 'pushpin_${pinColor.toARGB32()}_${badgeText}_$isSelected';
    if (_markerCache.containsKey(cacheKey)) {
      return _markerCache[cacheKey]!;
    }

    const double markerWidth = 110;
    const double markerHeight = 100;
    const double sphereRadius = 16;
    const double sphereCenterX = markerWidth / 2;
    final double sphereCenterY = badgeText.isNotEmpty ? 42.0 : 26.0;
    const double needleLength = 26.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Draw top label pill if present
    if (badgeText.isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: badgeText,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFCD34D) : Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final pillWidth = textPainter.width + 14;
      const pillHeight = 19.0;
      final pillRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(sphereCenterX, 13),
          width: pillWidth < 40 ? 40 : pillWidth,
          height: pillHeight,
        ),
        const Radius.circular(10),
      );

      // Pill shadow & fill
      canvas.drawRRect(
        pillRect.shift(const Offset(0, 1.5)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.drawRRect(
        pillRect,
        Paint()..color = isSelected ? const Color(0xFF1E293B) : const Color(0xFF0F172A).withValues(alpha: 0.9),
      );
      if (isSelected) {
        canvas.drawRRect(
          pillRect,
          Paint()
            ..color = const Color(0xFFF59E0B)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      textPainter.paint(
        canvas,
        Offset(
          sphereCenterX - (textPainter.width / 2),
          13 - (textPainter.height / 2),
        ),
      );
    }

    // 2. Needle Shadow on Ground
    final groundContactY = sphereCenterY + sphereRadius + needleLength;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(sphereCenterX + 1, groundContactY),
        width: 10,
        height: 4,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // 3. Pin Needle / Stick (Metallic Grey)
    final needlePaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(sphereCenterX - 2, sphereCenterY),
        Offset(sphereCenterX + 2, sphereCenterY),
        [
          const Color(0xFF64748B),
          const Color(0xFF334155),
          const Color(0xFF1E293B),
        ],
      )
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(sphereCenterX, sphereCenterY + sphereRadius - 2),
      Offset(sphereCenterX, groundContactY),
      needlePaint,
    );

    // 4. Outer Sphere Shadow
    canvas.drawCircle(
      Offset(sphereCenterX, sphereCenterY + 2),
      sphereRadius + (isSelected ? 3 : 1.5),
      Paint()
        ..color = isSelected
            ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
            : Colors.black.withValues(alpha: 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, isSelected ? 6 : 4),
    );

    // 5. 3D Spherical Head (Radial Gradient)
    final sphereCenter = Offset(sphereCenterX, sphereCenterY);
    final spherePaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(sphereCenterX - sphereRadius * 0.35, sphereCenterY - sphereRadius * 0.35),
        sphereRadius * 1.35,
        [
          Color.lerp(pinColor, Colors.white, 0.45)!,
          pinColor,
          Color.lerp(pinColor, Colors.black, 0.45)!,
        ],
        [0.0, 0.55, 1.0],
      );

    canvas.drawCircle(sphereCenter, sphereRadius, spherePaint);

    // 6. Specular Highlight Dot (matching reference image)
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75);
    canvas.drawCircle(
      Offset(sphereCenterX - sphereRadius * 0.32, sphereCenterY - sphereRadius * 0.32),
      sphereRadius * 0.32,
      highlightPaint,
    );

    // 7. Selected Golden Ring
    if (isSelected) {
      canvas.drawCircle(
        sphereCenter,
        sphereRadius + 2,
        Paint()
          ..color = const Color(0xFFF59E0B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      markerWidth.toInt(),
      markerHeight.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      return BitmapDescriptor.defaultMarker;
    }

    final Uint8List uint8list = byteData.buffer.asUint8List();
    final descriptor = BitmapDescriptor.bytes(uint8list);
    _markerCache[cacheKey] = descriptor;
    return descriptor;
  }

  static Color getMarkerColor(String relationship) {
    switch (relationship.toLowerCase()) {
      case 'father':
      case 'dad':
        return const Color(0xFF1E88E5);
      case 'mother':
      case 'mom':
        return const Color(0xFFE91E63);
      case 'brother':
      case 'son':
        return const Color(0xFF43A047);
      case 'sister':
      case 'daughter':
        return const Color(0xFFFF9800);
      case 'spouse':
      case 'wife':
      case 'husband':
        return const Color(0xFF8E24AA);
      default:
        return AppColors.primary;
    }
  }
}
