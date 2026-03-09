import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../product_profile.dart';
import '../../widgets/supabase_image.dart'; // IMPORTED shared widget

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late Future<Position> _locationFuture;

  @override
  void initState() {
    super.initState();
    _locationFuture = _determinePosition();
  }

  Future<void> _retryLocation() async {
    setState(() {
      _locationFuture = _determinePosition();
    });
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    }
    return await Geolocator.getCurrentPosition();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products Near You'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Products',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: FutureBuilder<Position>(
        future: _locationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.green));
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_off, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _retryLocation,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    ),
                    if (snapshot.error.toString().contains('disabled')) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Geolocator.openLocationSettings(),
                        child: const Text('Open Settings'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Could not fetch location.'));
          }

          final userLocation = LatLng(snapshot.data!.latitude, snapshot.data!.longitude);
          return ProductMap(userLocation: userLocation);
        },
      ),
    );
  }
}

class ProductMap extends StatefulWidget {
  final LatLng userLocation;
  const ProductMap({super.key, required this.userLocation});

  @override
  State<ProductMap> createState() => _ProductMapState();
}

class _ProductMapState extends State<ProductMap> {
  final MapController _mapController = MapController();
  late Future<List<Map<String, dynamic>>> _productsFuture;

  @override
  void initState() {
    super.initState();
    _productsFuture = _getProductsForMap();
  }

  Future<List<Map<String, dynamic>>> _getProductsForMap() async {
    try {
      final response = await Supabase.instance.client.rpc('get_products_for_map');
      return (response as List).map((item) => item as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('Error calling RPC: $e');
      return [];
    }
  }

  // Helper to get signed URL for Map Markers
  Future<String> _getSignedUrl(String path) async {
    if (path.startsWith('http')) return path;
    return await Supabase.instance.client.storage
        .from('product_images')
        .createSignedUrl(path, 3600);
  }

  Marker _createProductMarker(BuildContext context, Map<String, dynamic> product) {
    final latitude = product['latitude'] as double? ?? 0.0;
    final longitude = product['longitude'] as double? ?? 0.0;
    final imagePath = product['imageUrl'] as String? ?? '';
    final name = product['productName'] ?? 'No Name';

    double distanceInMeters = Geolocator.distanceBetween(
      widget.userLocation.latitude,
      widget.userLocation.longitude,
      latitude,
      longitude,
    );
    String distanceString = distanceInMeters < 1000
        ? '${distanceInMeters.toStringAsFixed(0)}m away'
        : '${(distanceInMeters / 1000).toStringAsFixed(1)}km away';

    return Marker(
      width: 60,
      height: 70,
      point: LatLng(latitude, longitude),
      child: GestureDetector(
        onTap: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (context) {
              return Card(
                margin: const EdgeInsets.all(16.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SupabaseImage( // UPDATED to use SupabaseImage
                        imagePath: imagePath,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Rs. ${product['price'] ?? 0}'),
                        Text(distanceString, style: TextStyle(color: Colors.green.shade700, fontSize: 12)),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ProductProfilePage(product: product)),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
        child: Semantics(
          label: 'Product: $name at $distanceString',
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              const Positioned(
                bottom: 0,
                child: Icon(Icons.location_on, color: Colors.green, size: 50),
              ),
              FutureBuilder<String>(
                future: _getSignedUrl(imagePath),
                builder: (context, snapshot) {
                  return Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2)),
                      ],
                      border: Border.all(color: Colors.green, width: 2),
                      image: snapshot.hasData
                          ? DecorationImage(
                              image: NetworkImage(snapshot.data!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: !snapshot.hasData
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 1))
                        : null,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _productsFuture,
          builder: (context, snapshot) {
            final products = snapshot.data ?? [];
            final productMarkers = products.map((product) => _createProductMarker(context, product)).toList();

            return FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.userLocation,
                initialZoom: 13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.geo_connect.app',
                ),
                MarkerLayer(markers: productMarkers),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: widget.userLocation,
                      child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 44),
                    )
                  ],
                )
              ],
            );
          },
        ),
        Positioned(
          bottom: 24,
          right: 16,
          child: FloatingActionButton(
            backgroundColor: Colors.white,
            foregroundColor: Colors.green,
            onPressed: () {
              _mapController.move(widget.userLocation, 14.0);
            },
            tooltip: 'Recenter to my location',
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}
