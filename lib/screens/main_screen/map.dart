import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../product_profile.dart';
import '../../widgets/supabase_image.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late Future<Position> _locationFuture;
  String _selectedCategory = 'All';

  final List<String> _categories = [
    'All',
    'Vegetables',
    'Fruits',
    'Dairy',
    'Grains',
    'Meat & Fish',
    'Honey',
    'Others'
  ];

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
        title: const Text('Products Map', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Products',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCategoryFilter(),
          Expanded(
            child: FutureBuilder<Position>(
              future: _locationFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.green));
                }
                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error.toString());
                }
                if (!snapshot.hasData) {
                  return const Center(child: Text('Could not fetch location.'));
                }

                final userLocation = LatLng(snapshot.data!.latitude, snapshot.data!.longitude);
                return ProductMap(
                  userLocation: userLocation, 
                  selectedCategory: _selectedCategory,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 60,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              label: Text(cat, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedCategory = cat;
                });
              },
              selectedColor: Colors.green.shade100,
              checkmarkColor: Colors.green,
              backgroundColor: Colors.grey[100],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _retryLocation,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductMap extends StatefulWidget {
  final LatLng userLocation;
  final String selectedCategory;
  
  const ProductMap({
    super.key, 
    required this.userLocation,
    required this.selectedCategory,
  });

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

  @override
  void didUpdateWidget(ProductMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCategory != widget.selectedCategory) {
      // Re-fetch or re-filter products when category changes
      // In this case, we re-fetch to keep it simple, but filtering locally is also possible
      _productsFuture = _getProductsForMap();
    }
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

  Marker _createProductMarker(BuildContext context, Map<String, dynamic> product) {
    final latitude = product['latitude'] as double? ?? 0.0;
    final longitude = product['longitude'] as double? ?? 0.0;
    final imageUrl = product['imageUrl'] as String? ?? '';
    final name = product['productName'] ?? 'No Name';

    String imagePath = imageUrl;
    if (imageUrl.contains('product_images/')) {
      imagePath = imageUrl.split('product_images/').last;
    }

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
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: imagePath.isNotEmpty 
                        ? SupabaseImage(imagePath: imagePath, width: 56, height: 56)
                        : Container(width: 56, height: 56, color: Colors.grey[200], child: const Icon(Icons.image)),
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Rs. ${product['price'] ?? 0}'),
                        Text(distanceString, style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
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
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            const Positioned(
              bottom: 0,
              child: Icon(Icons.location_on, color: Colors.green, size: 50),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2)),
                ],
                border: Border.all(color: Colors.green, width: 2),
              ),
              child: ClipOval(
                child: imagePath.isNotEmpty 
                  ? SupabaseImage(imagePath: imagePath, width: 40, height: 40)
                  : const Icon(Icons.person, color: Colors.grey),
              ),
            ),
          ],
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
            final allProducts = snapshot.data ?? [];
            
            // Apply category filtering
            final filteredProducts = allProducts.where((p) {
              if (widget.selectedCategory == 'All') return true;
              return p['category'] == widget.selectedCategory;
            }).toList();

            final productMarkers = filteredProducts.map((product) => _createProductMarker(context, product)).toList();

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
