import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../constants/app_colors.dart';

class MarkerGenerator {
  static const int _maxMarkerCacheSize = 80;

  // LRU cache for generated marker BitmapDescriptors (LinkedHashMap preserves insertion/access order)
  static final LinkedHashMap<String, BitmapDescriptor> _markerCache =
      LinkedHashMap<String, BitmapDescriptor>();

  // In-memory cache for decoded profile photos to prevent redundant disk I/O and GPU re-decoding
  static final Map<String, ui.Image> _decodedImageCache = {};

  // Clear cache if needed (e.g., when profile photo is updated)
  static void clearCache([String? memberPhone]) {
    if (memberPhone != null) {
      _markerCache.removeWhere((key, _) => key.contains(memberPhone));
      _decodedImageCache.removeWhere((key, _) => key.contains(memberPhone));
    } else {
      _markerCache.clear();
      _decodedImageCache.clear();
    }
  }

  // Generate a custom map marker with Member Avatar + Name & Last Updated Details Label Pill (Cached)
  static Future<BitmapDescriptor> createCustomMemberMarker({
    required String name,
    String? localPhotoPath,
    Color pinColor = AppColors.primary,
    bool isHighlighted = false,
    String lastUpdated = '',
    int batteryPercentage = 0,
    bool isMoving = false,
  }) async {
    final displayName = name.isNotEmpty ? name : 'Member';
    final initial = displayName[0].toUpperCase();

    // 0. Cache Check for instant 0ms retrieval
    final cacheKey = '${displayName}_${pinColor.toARGB32()}_${localPhotoPath ?? ''}_hl_${isHighlighted}_lu_${lastUpdated}_bat_${batteryPercentage}_mov_$isMoving';
    if (_markerCache.containsKey(cacheKey)) {
      final cached = _markerCache.remove(cacheKey)!;
      _markerCache[cacheKey] = cached; // Refresh LRU position
      return cached;
    }

    const double markerWidth = 150;
    const double markerHeight = 125;
    const double avatarRadius = 26;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Draw avatar outer shadow & border
    if (isHighlighted) {
      final glowPaint = Paint()
        ..color = const Color(0xFFF59E0B).withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(
        const Offset(markerWidth / 2, avatarRadius + 4),
        avatarRadius + 8,
        glowPaint,
      );

      final outerGoldRing = Paint()
        ..color = const Color(0xFFF59E0B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;
      canvas.drawCircle(
        const Offset(markerWidth / 2, avatarRadius + 4),
        avatarRadius + 3.5,
        outerGoldRing,
      );
    }

    if (isMoving) {
      final movingRing = Paint()
        ..color = const Color(0xFF10B981)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(
        const Offset(markerWidth / 2, avatarRadius + 4),
        avatarRadius + (isHighlighted ? 6.0 : 3.0),
        movingRing,
      );
    }

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(
      const Offset(markerWidth / 2, avatarRadius + 4),
      avatarRadius + 2,
      shadowPaint,
    );

    // Avatar background circle
    final circlePaint = Paint()..color = isHighlighted ? const Color(0xFFF59E0B) : pinColor;
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

    // 2. Check if local photo exists (using decoded image cache)
    bool photoDrawn = false;
    if (!kIsWeb && localPhotoPath != null && localPhotoPath.isNotEmpty) {
      ui.Image? img = _decodedImageCache[localPhotoPath];
      if (img == null) {
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
            img = frameInfo.image;
            _decodedImageCache[localPhotoPath] = img;
          } catch (_) {}
        }
      }

      if (img != null) {
        try {
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

    // 5. Draw Name & Last Updated Details Badge Pill at bottom
    final namePainter = TextPainter(
      text: TextSpan(
        text: displayName.length > 12
            ? '${displayName.substring(0, 10)}...'
            : displayName,
        style: TextStyle(
          color: isHighlighted ? const Color(0xFF78350F) : AppColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    namePainter.layout();

    String detailsText = '';
    if (isMoving) {
      detailsText = '🚗 Moving • ${lastUpdated.isNotEmpty ? lastUpdated : "Now"}';
    } else if (lastUpdated.isNotEmpty) {
      detailsText = '🕒 $lastUpdated${batteryPercentage > 0 ? " • ⚡$batteryPercentage%" : ""}';
    } else if (batteryPercentage > 0) {
      detailsText = '⚡ $batteryPercentage%';
    }

    TextPainter? detailsPainter;
    if (detailsText.isNotEmpty) {
      detailsPainter = TextPainter(
        text: TextSpan(
          text: detailsText,
          style: TextStyle(
            color: isHighlighted
                ? const Color(0xFF92400E)
                : const Color(0xFF475569),
            fontSize: 8.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      detailsPainter.layout();
    }

    final double contentWidth = detailsPainter != null
        ? (detailsPainter.width > namePainter.width ? detailsPainter.width : namePainter.width)
        : namePainter.width;
    final badgeWidth = (contentWidth + 16).clamp(64.0, 140.0);
    final badgeHeight = detailsPainter != null ? 32.0 : 22.0;

    final badgeCenterY = avatarRadius * 2 + 18 + badgeHeight / 2;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(markerWidth / 2, badgeCenterY),
        width: badgeWidth,
        height: badgeHeight,
      ),
      const Radius.circular(10),
    );

    // Pill shadow
    canvas.drawRRect(
      badgeRect.shift(const Offset(0, 2)),
      Paint()
        ..color = isHighlighted
            ? const Color(0xFFF59E0B).withValues(alpha: 0.45)
            : Colors.black.withValues(alpha: 0.2)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, isHighlighted ? 5 : 3),
    );

    // Pill background
    canvas.drawRRect(
      badgeRect,
      Paint()..color = isHighlighted ? const Color(0xFFFEF3C7) : Colors.white,
    );

    // Pill border
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = isHighlighted ? const Color(0xFFF59E0B) : pinColor.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHighlighted ? 2.2 : 1.5,
    );

    // Pill Texts
    if (detailsPainter != null) {
      namePainter.paint(
        canvas,
        Offset(
          (markerWidth - namePainter.width) / 2,
          badgeCenterY - badgeHeight / 2 + 3,
        ),
      );
      detailsPainter.paint(
        canvas,
        Offset(
          (markerWidth - detailsPainter.width) / 2,
          badgeCenterY - badgeHeight / 2 + 17,
        ),
      );
    } else {
      namePainter.paint(
        canvas,
        Offset(
          (markerWidth - namePainter.width) / 2,
          badgeCenterY - (namePainter.height / 2),
        ),
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
    if (_markerCache.length >= _maxMarkerCacheSize) {
      _markerCache.remove(_markerCache.keys.first);
    }
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
