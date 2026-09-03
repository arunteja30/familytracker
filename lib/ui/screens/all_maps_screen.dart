import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../constants/app_colors.dart';
import '../../models/family_member_model.dart';
import '../../models/location_details_model.dart';

class AllMapsScreen extends StatefulWidget {
  final String familyName;
  final List<FamilyMemberModel> members;
  final Map<String, LocationDetailsModel> locations;

  const AllMapsScreen({
    super.key,
    required this.familyName,
    required this.members,
    required this.locations,
  });

  @override
  State<AllMapsScreen> createState() => _AllMapsScreenState();
}

class _AllMapsScreenState extends State<AllMapsScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  MapType _currentMapType = MapType.normal;
  final Set<Marker> _markers = {};
  FamilyMemberModel? _selectedMember;

  @override
  void initState() {
    super.initState();
    _buildMarkers();
  }

  void _buildMarkers() {
    _markers.clear();
    for (var member in widget.members) {
      final loc = widget.locations[member.mobile];
      if (loc != null && (loc.latitude != 0.0 || loc.longitude != 0.0)) {
        _markers.add(
          Marker(
            markerId: MarkerId(member.mobile),
            position: LatLng(loc.latitude, loc.longitude),
            infoWindow: InfoWindow(
              title: member.name,
              snippet: '${loc.batteryPercentage}% Battery • ${loc.address}',
            ),
            onTap: () {
              setState(() => _selectedMember = member);
            },
          ),
        );
      }
    }
  }

  Future<void> _focusMember(FamilyMemberModel member) async {
    final loc = widget.locations[member.mobile];
    if (loc != null && (loc.latitude != 0.0 || loc.longitude != 0.0)) {
      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(loc.latitude, loc.longitude),
            zoom: 16,
          ),
        ),
      );
      setState(() => _selectedMember = member);
    }
  }

  Future<void> _fitAllBounds() async {
    if (_markers.isEmpty) return;
    final GoogleMapController controller = await _controller.future;

    if (_markers.length == 1) {
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _markers.first.position,
            zoom: 15,
          ),
        ),
      );
      return;
    }

    double minLat = _markers.first.position.latitude;
    double maxLat = _markers.first.position.latitude;
    double minLng = _markers.first.position.longitude;
    double maxLng = _markers.first.position.longitude;

    for (var marker in _markers) {
      if (marker.position.latitude < minLat) minLat = marker.position.latitude;
      if (marker.position.latitude > maxLat) maxLat = marker.position.latitude;
      if (marker.position.longitude < minLng) minLng = marker.position.longitude;
      if (marker.position.longitude > maxLng) maxLng = marker.position.longitude;
    }

    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    LatLng initialPos = const LatLng(17.3850, 78.4867); // Default Hyderabad
    if (_markers.isNotEmpty) {
      initialPos = _markers.first.position;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.familyName} Map'),
        actions: [
          PopupMenuButton<MapType>(
            icon: const Icon(Icons.layers_rounded),
            onSelected: (type) => setState(() => _currentMapType = type),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: MapType.normal,
                child: Text('Normal Map'),
              ),
              const PopupMenuItem(
                value: MapType.satellite,
                child: Text('Satellite Map'),
              ),
              const PopupMenuItem(
                value: MapType.terrain,
                child: Text('Terrain Map'),
              ),
              const PopupMenuItem(
                value: MapType.hybrid,
                child: Text('Hybrid Map'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen_rounded),
            onPressed: _fitAllBounds,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: initialPos,
              zoom: 12,
            ),
            mapType: _currentMapType,
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
              Future.delayed(const Duration(milliseconds: 500), _fitAllBounds);
            },
          ),

          // Horizontal Member Selector at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.members.length,
                itemBuilder: (context, index) {
                  final member = widget.members[index];
                  final loc = widget.locations[member.mobile];
                  final isSelected = _selectedMember?.mobile == member.mobile;

                  return GestureDetector(
                    onTap: () => _focusMember(member),
                    child: Container(
                      width: 170,
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.cardBorder,
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor:
                                    AppColors.primaryLight.withOpacity(0.2),
                                child: Text(
                                  member.name.isNotEmpty
                                      ? member.name[0].toUpperCase()
                                      : 'M',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  member.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            loc != null && loc.batteryPercentage > 0
                                ? '⚡ ${loc.batteryPercentage}% • ${loc.address}'
                                : 'No GPS data',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
