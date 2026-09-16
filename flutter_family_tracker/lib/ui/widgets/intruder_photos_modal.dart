import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../services/geocoding_service.dart';
import '../../services/native_service.dart';

class IntruderPhotosModal extends StatefulWidget {
  const IntruderPhotosModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const IntruderPhotosModal(),
    );
  }

  @override
  State<IntruderPhotosModal> createState() => _IntruderPhotosModalState();
}

class _IntruderPhotosModalState extends State<IntruderPhotosModal> {
  List<Map<String, dynamic>> _photos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    setState(() => _isLoading = true);
    final photos = await NativeService.getIntruderPhotos();
    if (mounted) {
      setState(() {
        _photos = photos;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveToGallery(String filePath) async {
    final success = await NativeService.savePhotoToGallery(filePath);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: success ? AppColors.success : AppColors.danger,
          content: Text(success
              ? 'Photo successfully saved to your Phone Gallery!'
              : 'Failed to save photo to gallery.'),
        ),
      );
    }
  }

  Future<void> _deletePhoto(String filePath) async {
    await NativeService.deleteIntruderPhoto(filePath);
    _loadPhotos();
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Photos'),
        content: const Text(
            'Are you sure you want to delete all intruder photos from app memory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await NativeService.clearAllIntruderPhotos();
      _loadPhotos();
    }
  }

  void _openFullScreenViewer(int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenPhotoViewer(
          photos: _photos,
          initialIndex: initialIndex,
          onDelete: (path) async {
            await _deletePhoto(path);
          },
          onSaveToGallery: (path) => _saveToGallery(path),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle & Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.photo_library_rounded,
                              color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Intruder Photo Vault',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Stored securely in app private memory',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (_photos.isNotEmpty)
                      TextButton.icon(
                        onPressed: _clearAll,
                        icon: const Icon(Icons.delete_sweep_rounded,
                            color: AppColors.danger, size: 18),
                        label: const Text('Clear All',
                            style: TextStyle(
                                color: AppColors.danger, fontSize: 13)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Body Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _photos.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield_outlined,
                                size: 56,
                                color: AppColors.primary.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            const Text(
                              'No Intruder Snapshots',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'When someone fails your lockscreen password 2 times, secret front and rear photos and location coordinates will appear here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.82,
                        ),
                        itemCount: _photos.length,
                        itemBuilder: (ctx, index) {
                          final item = _photos[index];
                          final path = item['path'] as String;
                          final file = File(path);
                          final isFront = (item['isFront'] as bool?) ?? true;
                          final timestamp = item['timestamp'] as int? ?? 0;
                          final lat = (item['latitude'] as num?)?.toDouble() ?? 0.0;
                          final lng = (item['longitude'] as num?)?.toDouble() ?? 0.0;
                          final hasGps = lat != 0.0 && lng != 0.0;

                          final dateStr = timestamp > 0
                              ? DateTime.fromMillisecondsSinceEpoch(timestamp)
                                  .toString()
                                  .split('.')
                                  .first
                              : '';

                          return GestureDetector(
                            onTap: () => _openFullScreenViewer(index),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.cardBorder),
                                color: AppColors.bgSurfaceElevated,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (file.existsSync())
                                    Image.file(
                                      file,
                                      fit: BoxFit.cover,
                                    )
                                  else
                                    const Center(
                                        child: Icon(Icons.broken_image_rounded)),
                                  // Gradient Overlay at bottom
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [
                                            Colors.black.withValues(alpha: 0.9),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: isFront
                                                      ? AppColors.primary
                                                      : Colors.teal,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  isFront ? 'FRONT' : 'REAR',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              if (hasGps)
                                                const Icon(Icons.location_on_rounded, color: Colors.greenAccent, size: 14),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            dateStr,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full Screen Interactive Viewer with Swipe, Next/Back buttons, & Geocoding
// ---------------------------------------------------------------------------
class _FullScreenPhotoViewer extends StatefulWidget {
  final List<Map<String, dynamic>> photos;
  final int initialIndex;
  final Function(String path) onDelete;
  final Function(String path) onSaveToGallery;

  const _FullScreenPhotoViewer({
    required this.photos,
    required this.initialIndex,
    required this.onDelete,
    required this.onSaveToGallery,
  });

  @override
  State<_FullScreenPhotoViewer> createState() => _FullScreenPhotoViewerState();
}

class _FullScreenPhotoViewerState extends State<_FullScreenPhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;
  final Map<int, String> _addressCache = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _resolveAddress(_currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _resolveAddress(int index) async {
    if (index < 0 || index >= widget.photos.length) return;
    if (_addressCache.containsKey(index)) return;

    final item = widget.photos[index];
    final lat = (item['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (item['longitude'] as num?)?.toDouble() ?? 0.0;

    if (lat != 0.0 && lng != 0.0) {
      try {
        final address = await GeocodingService.getAddressFromCoordinates(lat, lng);
        if (mounted) {
          setState(() {
            _addressCache[index] = address.isNotEmpty ? address : 'Lat: ${lat.toStringAsFixed(4)}, Lon: ${lng.toStringAsFixed(4)}';
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _addressCache[index] = 'Lat: ${lat.toStringAsFixed(4)}, Lon: ${lng.toStringAsFixed(4)}';
          });
        }
      }
    }
  }

  void _nextPhoto() {
    if (_currentIndex < widget.photos.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevPhoto() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _openMapUrl(double lat, double lng) async {
    final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No photos available', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      );
    }

    final currentItem = widget.photos[_currentIndex];
    final path = currentItem['path'] as String;
    final isFront = (currentItem['isFront'] as bool?) ?? true;
    final timestamp = currentItem['timestamp'] as int? ?? 0;
    final lat = (currentItem['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (currentItem['longitude'] as num?)?.toDouble() ?? 0.0;
    final hasGps = lat != 0.0 && lng != 0.0;
    final address = _addressCache[_currentIndex] ?? (hasGps ? 'Resolving address...' : 'GPS unavailable during lock event');

    final dateFormatted = timestamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(timestamp).toString().split('.').first
        : '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Interactive PageView for swiping photos
            PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
                _resolveAddress(index);
              },
              itemBuilder: (ctx, index) {
                final item = widget.photos[index];
                final f = File(item['path'] as String);
                return Center(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 3.5,
                    child: f.existsSync()
                        ? Image.file(
                            f,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                          )
                        : const Center(
                            child: Text(
                              'Photo file not found',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                  ),
                );
              },
            ),

            // Top Navigation Bar
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.photos.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => widget.onSaveToGallery(path),
                        icon: const Icon(Icons.download_rounded, color: Colors.white),
                        tooltip: 'Save to Phone Gallery',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Delete Photo'),
                              content: const Text('Delete this intruder photo?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            widget.onDelete(path);
                            if (mounted) Navigator.pop(context);
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                        tooltip: 'Delete Photo',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Previous Button Overlay
            if (_currentIndex > 0)
              Positioned(
                left: 12,
                top: 0,
                bottom: 120,
                child: Center(
                  child: GestureDetector(
                    onTap: _prevPhoto,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 32),
                    ),
                  ),
                ),
              ),

            // Next Button Overlay
            if (_currentIndex < widget.photos.length - 1)
              Positioned(
                right: 12,
                top: 0,
                bottom: 120,
                child: Center(
                  child: GestureDetector(
                    onTap: _nextPhoto,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 32),
                    ),
                  ),
                ),
              ),

            // Bottom Information Overlay with Location & Geocoding Address
            Positioned(
              bottom: 12,
              left: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badge + Date Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isFront ? AppColors.primary : Colors.teal,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isFront ? '📷 FRONT CAMERA (FACE)' : '📸 REAR CAMERA (ENVIRONMENT)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          dateFormatted,
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Location / Geocoded Address
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          hasGps ? Icons.location_on_rounded : Icons.location_off_rounded,
                          color: hasGps ? Colors.greenAccent : Colors.grey,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                address,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (hasGps) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'GPS: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (hasGps) ...[
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => _openMapUrl(lat, lng),
                            icon: const Icon(Icons.map_rounded, size: 14),
                            label: const Text('Map'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
