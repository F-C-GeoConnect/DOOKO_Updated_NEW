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
      body: FutureBuilder<Position>(
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
          return ProductMap(userLocation: userLocation);
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

  void _openProductSheet(BuildContext context, Map<String, dynamic> product,
      String imagePath, String name, String distanceString) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ProductBottomSheet(
          product: product,
          imagePath: imagePath,
          name: name,
          distanceString: distanceString,
          onTap: () async {
            // 1. Close the sheet
            Navigator.pop(sheetContext);

            // 2. Show a loading overlay
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => const Center(
                child: CircularProgressIndicator(color: Colors.green),
              ),
            );

            // 3. Robust parsing of product ID
            final dynamic rawId = product['id'];
            int? productId;
            if (rawId is num) {
              productId = rawId.toInt();
            } else if (rawId != null) {
              productId = int.tryParse(rawId.toString()) ?? 
                          num.tryParse(rawId.toString())?.toInt();
            }
            
            Map<String, dynamic>? fullProduct;
            if (productId != null) {
              try {
                // Fetch full product details including total_quantity
                fullProduct = await Supabase.instance.client
                    .from('products')
                    .select('*, profiles:seller_id(is_verified)')
                    .eq('id', productId)
                    .maybeSingle();
              } catch (e) {
                debugPrint('Error fetching full product: $e');
              }
            }

            // 4. Dismiss loading overlay
            if (context.mounted) Navigator.pop(context);

            if (!context.mounted) return;

            // 5. Navigate with the FULL data (including total_quantity)
            // If fullProduct fetch failed, we fallback to 'product' data
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductProfilePage(product: fullProduct ?? product),
              ),
            );
          },
        );
      },
    );
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
        onTap: () => _openProductSheet(
          context,
          product,
          imagePath,
          name,
          distanceString,
        ),
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
                  BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2)),
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
            final productMarkers = allProducts
                .map((product) => _createProductMarker(context, product))
                .toList();

            return FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.userLocation,
                initialZoom: 13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.untitled1',
                ),
                MarkerLayer(markers: productMarkers),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: widget.userLocation,
                      child: const Icon(
                          Icons.person_pin_circle, color: Colors.blue, size: 44),
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

class _ProductBottomSheet extends StatelessWidget {
  final Map<String, dynamic> product;
  final String imagePath;
  final String name;
  final String distanceString;
  final VoidCallback onTap;

  const _ProductBottomSheet({
    required this.product,
    required this.imagePath,
    required this.name,
    required this.distanceString,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imagePath.isNotEmpty
                  ? SupabaseImage(imagePath: imagePath, width: 56, height: 56)
                  : Container(
                width: 56,
                height: 56,
                color: Colors.grey[200],
                child: const Icon(Icons.image),
              ),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Rs. ${product['price'] ?? 0}'),
                Text(
                  distanceString,
                  style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StockDisplay(productId: product['id']),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StockDisplay extends StatelessWidget {
  final dynamic productId;
  const _StockDisplay({required this.productId});

  @override
  Widget build(BuildContext context) {
    // Ensure we have an integer ID for the query
    final int? id = productId is num ? productId.toInt() : int.tryParse(productId?.toString() ?? '');

    if (id == null) return const SizedBox.shrink();

    return FutureBuilder<Map<String, dynamic>?>(
      future: Supabase.instance.client
          .from('products')
          .select('total_quantity')
          .eq('id', id)
          .maybeSingle(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green),
          );
        }
        final qty = snapshot.data?['total_quantity'] ?? 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: qty > 0 ? Colors.green.shade50 : Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: qty > 0 ? Colors.green.shade100 : Colors.red.shade100),
          ),
          child: Text(
            '$qty left',
            style: TextStyle(
              color: qty > 0 ? Colors.green.shade700 : Colors.red.shade700,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }
}