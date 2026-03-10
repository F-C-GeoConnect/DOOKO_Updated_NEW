import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:untitled1/screens/product_profile.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/refreshable_scaffold.dart';
import '../../widgets/product_rating.dart';
import '../../widgets/supabase_image.dart';
import '../../widgets/shimmer_loading.dart';
import '../../services/product_service.dart';
import 'cart_screen.dart';
import 'notifications_screen.dart';
import 'map.dart';
import 'dart:async';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _productService = ProductService();
  late Future<List<Map<String, dynamic>>> _productsFuture;
  final _searchController = TextEditingController();

  double _searchRadius = 20;
  Position? _currentUserPosition;
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

  List<Map<String, dynamic>> _notifications = [];
  RealtimeChannel? _notificationsChannel;

  @override
  void initState() {
    super.initState();
    _productsFuture = _productService.getProductsForHomepage();
    _initRealtimeNotifications();

    _searchController.addListener(() {
      setState(() {});
    });

    _determinePosition().then((position) {
      if (mounted) {
        setState(() {
          _currentUserPosition = position;
        });
      }
    }).catchError((e) {
      if (mounted) {
        debugPrint('Could not get location: $e');
      }
    });
  }

  Future<void> _handleRefresh() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) await _fetchNotifications(userId);

    final position = await _determinePosition();
    setState(() {
      _currentUserPosition = position;
      _productsFuture = _productService.getProductsForHomepage();
    });
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('Location services are disabled.');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied)
        return Future.error('Location permissions are denied.');
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    }

    return await Geolocator.getCurrentPosition();
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  /// Safely extracts lat/lng from:
  /// 1. Flat latitude/longitude fields (num)
  /// 2. WKT POINT string: "POINT(lng lat)"
  /// 3. WKB hex string: "0101000020E6100000..." (PostGIS binary)
  _LatLng? _getCoordinates(Map<String, dynamic> product) {
    try {
      // 1. Flat fields
      final rawLat = product['latitude'];
      final rawLng = product['longitude'];
      if (rawLat != null && rawLng != null) {
        return _LatLng(
          (rawLat as num).toDouble(),
          (rawLng as num).toDouble(),
        );
      }

      final location = product['location'] as String?;
      if (location == null) return null;

      // 2. WKT POINT format
      if (location.contains('POINT')) {
        final raw =
        location.replaceAll('POINT(', '').replaceAll(')', '').trim();
        final parts = raw.split(' ');
        if (parts.length >= 2) {
          final lng = double.tryParse(parts[0]);
          final lat = double.tryParse(parts[1]);
          if (lat != null && lng != null) return _LatLng(lat, lng);
        }
      }

      // 3. WKB hex format (PostGIS) — e.g. "0101000020E6100000..."
      //    Byte layout (little-endian EWKB with SRID):
      //    [1 byte]  byte order = 01 (little-endian)
      //    [4 bytes] geometry type = 01000020 (Point with SRID flag)
      //    [4 bytes] SRID = E6100000 (4326)
      //    [8 bytes] X / longitude  ← bytes 10–17
      //    [8 bytes] Y / latitude   ← bytes 18–25
      if (location.length >= 50) {
        final hex = location.trim().toUpperCase();
        final lng = _parseWkbDouble(hex, 18); // X = longitude
        final lat = _parseWkbDouble(hex, 34); // Y = latitude
        if (lat != null && lng != null) return _LatLng(lat, lng);
      }
    } catch (e) {
      debugPrint('Error parsing coordinates: $e');
    }
    return null;
  }

  /// Reads 8 bytes (16 hex chars) from [hex] starting at char offset [charOffset],
  /// interprets them as a little-endian IEEE 754 double.
  double? _parseWkbDouble(String hex, int charOffset) {
    try {
      if (hex.length < charOffset + 16) return null;
      final chunk = hex.substring(charOffset, charOffset + 16);
      // Reverse byte order (little-endian → big-endian)
      final bytes = List<int>.generate(8, (i) {
        return int.parse(chunk.substring((7 - i) * 2, (7 - i) * 2 + 2), radix: 16);
      });
      // Reconstruct the 64-bit double from bytes
      int bits = 0;
      for (final b in bytes) {
        bits = (bits << 8) | b;
      }
      final byteData = ByteData(8);
      byteData.setInt64(0, bits, Endian.big);
      return byteData.getFloat64(0, Endian.big);
    } catch (e) {
      debugPrint('WKB double parse error: $e');
      return null;
    }
  }

  void _showRadiusFilter() {
    double tempRadius = _searchRadius;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Filter by Radius'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      'Show products within ${tempRadius.toStringAsFixed(0)} km'),
                  Slider(
                    value: tempRadius,
                    min: 1,
                    max: 100,
                    divisions: 99,
                    activeColor: Colors.green,
                    label: tempRadius.round().toString(),
                    onChanged: (v) => setModalState(() => tempRadius = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel')),
                TextButton(
                  onPressed: () {
                    setState(() => _searchRadius = tempRadius);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _initRealtimeNotifications() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _fetchNotifications(userId);
    _notificationsChannel = Supabase.instance.client
        .channel('notifications:$userId')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId),
      callback: (payload) => _fetchNotifications(userId),
    )
        .subscribe();
  }

  Future<void> _fetchNotifications(String userId) async {
    try {
      final data = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      if (mounted)
        setState(() => _notifications = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    }
  }

  Future<void> _markAllNotificationsAsRead() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
      _fetchNotifications(userId);
    } catch (e) {
      debugPrint('Error marking notifications as read: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notificationsChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount =
        _notifications.where((n) => n['is_read'] == false).length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('DOKO',
                style: TextStyle(
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 24)),
            Row(
              children: [
                Consumer<CartProvider>(
                  builder: (context, cart, child) => Stack(
                    children: [
                      IconButton(
                        icon: Icon(Icons.shopping_basket_outlined,
                            color: Colors.grey.shade700),
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const CartScreen())),
                      ),
                      if (cart.itemCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(8)),
                            constraints: const BoxConstraints(
                                minWidth: 16, minHeight: 16),
                            child: Text(cart.itemCount.toString(),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 10),
                                textAlign: TextAlign.center),
                          ),
                        ),
                    ],
                  ),
                ),
                Stack(
                  children: [
                    IconButton(
                      icon: Icon(Icons.notifications_outlined,
                          color: Colors.grey.shade700),
                      onPressed: () async {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                const NotificationsScreen()))
                            .then((_) => _markAllNotificationsAsRead());
                      },
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(8)),
                          constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                              unreadCount > 99
                                  ? '99+'
                                  : unreadCount.toString(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      body: RefreshableWrapper(
        onRefresh: _handleRefresh,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchBar(),
              const SizedBox(height: 20),
              _buildCategorySection(),
              const SizedBox(height: 20),
              const PromoBanner(),
              const SizedBox(height: 20),
              _buildSectionHeader('Browse Products'),
              const SizedBox(height: 10),
              _buildProductGrid(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search...',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.grey[200],
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none),
        suffixIcon: IconButton(
            icon: const Icon(Icons.filter_list), onPressed: _showRadiusFilter),
      ),
    );
  }

  Widget _buildCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Categories',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final cat = _categories[index];
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedCategory = cat;
                    });
                  },
                  selectedColor: Colors.green.shade100,
                  checkmarkColor: Colors.green,
                  labelStyle: TextStyle(
                    color:
                    isSelected ? Colors.green.shade800 : Colors.black87,
                    fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  backgroundColor: Colors.grey[100],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style:
            const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        IconButton(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (context) => const MapPage())),
          icon: const Icon(Icons.map_outlined, color: Colors.green),
        ),
      ],
    );
  }

  Widget _buildProductGrid() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _productsFuture,
      builder: (context, snapshot) {
        // Show shimmer while location or products are loading
        if (_currentUserPosition == null ||
            snapshot.connectionState == ConnectionState.waiting) {
          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                childAspectRatio: 0.8),
            itemCount: 6,
            itemBuilder: (context, index) => const ProductCardShimmer(),
          );
        }

        if (snapshot.hasError)
          return Center(child: Text('Error: ${snapshot.error}'));

        final allProducts = snapshot.data ?? [];
        if (allProducts.isEmpty)
          return const Center(child: Text('No products available yet.'));

        // ── FILTER ──────────────────────────────────────────────────────────
        final filteredProducts = allProducts.where((product) {
          // 1. Search text match
          final productName =
          (product['productName'] as String? ?? '').toLowerCase();
          final searchText = _searchController.text.trim().toLowerCase();
          final matchesSearch =
              searchText.isEmpty || productName.contains(searchText);

          // 2. Category match — compare original-case strings directly
          final productCategory =
          (product['category'] as String? ?? '').trim();
          final matchesCategory = _selectedCategory == 'All' ||
              productCategory == _selectedCategory;

          // 3. Radius match — products WITHOUT coordinates are excluded
          final coords = _getCoordinates(product);
          if (coords == null) return false;
          final distance = _calculateDistance(
            _currentUserPosition!.latitude,
            _currentUserPosition!.longitude,
            coords.latitude,
            coords.longitude,
          );
          final matchesRadius = distance <= _searchRadius;

          return matchesSearch && matchesCategory && matchesRadius;
        }).toList();

        // ── SORT: nearest first ──────────────────────────────────────────────
        filteredProducts.sort((a, b) {
          final coordsA = _getCoordinates(a);
          final coordsB = _getCoordinates(b);
          if (coordsA == null) return 1;
          if (coordsB == null) return -1;
          final distA = _calculateDistance(
              _currentUserPosition!.latitude,
              _currentUserPosition!.longitude,
              coordsA.latitude,
              coordsA.longitude);
          final distB = _calculateDistance(
              _currentUserPosition!.latitude,
              _currentUserPosition!.longitude,
              coordsB.latitude,
              coordsB.longitude);
          return distA.compareTo(distB);
        });

        if (filteredProducts.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Text(
                'No products found in this category or radius.\nTry increasing the radius or selecting "All".',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 0.8),
          itemCount: filteredProducts.length,
          itemBuilder: (context, index) {
            final product = filteredProducts[index];
            final coords = _getCoordinates(product);
            final distance = coords == null
                ? null
                : _calculateDistance(
              _currentUserPosition!.latitude,
              _currentUserPosition!.longitude,
              coords.latitude,
              coords.longitude,
            );
            return ProductCard(product: product, distance: distance);
          },
        );
      },
    );
  }
}

// ── Helper class ─────────────────────────────────────────────────────────────

class _LatLng {
  final double latitude;
  final double longitude;
  _LatLng(this.latitude, this.longitude);
}

// ── PromoBanner ───────────────────────────────────────────────────────────────

class PromoBanner extends StatelessWidget {
  const PromoBanner({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
          color: Colors.amber[100],
          borderRadius: BorderRadius.circular(15)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: CachedNetworkImage(
          imageUrl:
          'https://clipart-library.com/2023/5f0d0ab64520712d29e2c2fd_NEW20Summer20Market20Logo20white.png',
          fit: BoxFit.cover,
          errorWidget: (context, url, error) => Center(
              child: Text('Summer Market',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[900]))),
        ),
      ),
    );
  }
}

// ── ProductCard ───────────────────────────────────────────────────────────────

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final double? distance;

  const ProductCard({super.key, required this.product, this.distance});

  @override
  Widget build(BuildContext context) {
    final imageUrl = product['imageUrl'] as String? ?? '';
    final productId = (product['id'] as num?)?.toInt() ?? 0;
    final productName = product['productName'] as String? ?? 'No Name';
    final price = (product['price'] as num?)?.toDouble() ?? 0.0;
    final sellerId = product['seller_id'] as String? ?? '';

    final NumberFormat currencyFormat =
    NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);

    String imagePath = imageUrl;
    if (imageUrl.contains('product_images/')) {
      imagePath = imageUrl.split('product_images/').last;
    }

    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => ProductProfilePage(product: product))),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        elevation: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  SizedBox.expand(
                    child: (imagePath.isNotEmpty)
                        ? SupabaseImage(
                        imagePath: imagePath,
                        bucket: 'product_images',
                        fit: BoxFit.cover)
                        : const Icon(Icons.image_not_supported,
                        size: 40, color: Colors.grey),
                  ),
                  if (distance != null)
                    Positioned(
                      top: 5,
                      left: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(10)),
                        child: Text('${distance!.toStringAsFixed(1)} km',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Container(
                      decoration: const BoxDecoration(
                          color: Colors.white70, shape: BoxShape.circle),
                      child: Consumer<CartProvider>(
                        builder: (context, cart, child) {
                          final isAdded = cart.isItemInCart(productId);
                          return IconButton(
                            iconSize: 20,
                            icon: Icon(
                                isAdded
                                    ? Icons.shopping_cart
                                    : Icons.shopping_cart_outlined,
                                color:
                                isAdded ? Colors.red : Colors.black54),
                            onPressed: () => cart.toggleCartStatus(
                                productId, productName, price, imageUrl, sellerId),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(6),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(productName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(currencyFormat.format(price),
                      style: TextStyle(
                          color: Colors.grey.shade800, fontSize: 14)),
                  const SizedBox(height: 4),
                  ProductRating(productId: productId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}