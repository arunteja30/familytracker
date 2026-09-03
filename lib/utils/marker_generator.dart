import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../constants/app_colors.dart';

class MarkerGenerator {
  // Generate a custom map marker with Member Avatar + Name Label Pill by default
  static Future<BitmapDescriptor> createCustomMemberMarker({
    required String name,
    String? localPhotoPath,
    Color pinColor = AppColors.primary,
  }) async {
    final displayName = name.isNotEmpty ? name : 'Member';
    final initial = displayName[0].toUpperCase();

    const double markerWidth = 140;
    const double markerHeight = 110;
    const double avatarRadius = 26;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Draw avatar outer shadow & border
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
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

    // 4. Draw pointer pin triangle
    final path = Path();
    path.moveTo(markerWidth / 2 - 8, avatarRadius * 2 + 2);
    path.lineTo(markerWidth / 2 + 8, avatarRadius * 2 + 2);
    path.lineTo(markerWidth / 2, avatarRadius * 2 + 12);
    path.close();
    canvas.drawPath(path, Paint()..color = pinColor);

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
        center: const Offset(markerWidth / 2, avatarRadius * 2 + 24),
        width: badgeWidth < 60 ? 60 : badgeWidth,
        height: badgeHeight,
      ),
      const Radius.circular(10),
    );

    // Pill shadow
    canvas.drawRRect(
      badgeRect.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withOpacity(0.2)
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
        ..color = pinColor.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Pill Text
    namePainter.paint(
      canvas,
      Offset(
        (markerWidth - namePainter.width) / 2,
        avatarRadius * 2 + 24 - (namePainter.height / 2),
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
    return BitmapDescriptor.bytes(uint8list);
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
