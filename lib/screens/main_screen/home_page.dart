import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
import '../product_profile.dart';
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
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  List<Map<String, dynamic>> _allProducts = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  final int _pageSize = 10;

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
    _initData();
    _initRealtimeNotifications();

    _searchController.addListener(() {
      setState(() {});
    });

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        if (!_isLoadingMore && _hasMore) {
          _loadMoreProducts();
        }
      }
    });
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    try {
      _currentUserPosition = await _determinePosition();
    } catch (e) {
      debugPrint('Could not get location: $e');
    }
    await _refreshProducts();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _refreshProducts() async {
    _currentOffset = 0;
    _hasMore = true;
    try {
      final products = await _productService.getProductsForHomepage(offset: 0, limit: _pageSize);
      if (mounted) {
        setState(() {
          _allProducts = products;
          _hasMore = products.length == _pageSize;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing products: $e');
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    _currentOffset += _pageSize;

    try {
      final newProducts = await _productService.getProductsForHomepage(
          offset: _currentOffset,
          limit: _pageSize
      );

      if (mounted) {
        setState(() {
          _allProducts.addAll(newProducts);
          _hasMore = newProducts.length == _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading more products: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _handleRefresh() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) _fetchNotifications(userId);

    try {
      _currentUserPosition = await _determinePosition();
    } catch (e) {
      debugPrint('Location refresh error: $e');
    }
    await _refreshProducts();
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

  _LatLng? _getCoordinates(Map<String, dynamic> product) {
    try {
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

      if (location.length >= 50) {
        final hex = location.trim().toUpperCase();
        final lng = _parseWkbDouble(hex, 18);
        final lat = _parseWkbDouble(hex, 34);
        if (lat != null && lng != null) return _LatLng(lat, lng);
      }
    } catch (e) {
      debugPrint('Error parsing coordinates: $e');
    }
    return null;
  }

  double? _parseWkbDouble(String hex, int charOffset) {
    try {
      if (hex.length < charOffset + 16) return null;
      final chunk = hex.substring(charOffset, charOffset + 16);
      final bytes = List<int>.generate(8, (i) {
        return int.parse(chunk.substring((7 - i) * 2, (7 - i) * 2 + 2), radix: 16);
      });
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
      // OPTIMIZED: Selecting only is_read to reduce egress on the home page notification badge
      final data = await Supabase.instance.client
          .from('notifications')
          .select('is_read')
          .eq('user_id', userId);
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
    _scrollController.dispose();
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
            Text('DOOKO',
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
          controller: _scrollController,
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
              if (_isLoadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(color: Colors.green)),
                ),
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
        suffixIcon: GestureDetector(
          onTap: _showRadiusFilter,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Filter',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.filter_list),
              const SizedBox(width: 8),
            ],
          ),
        ),
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
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (context) => const MapPage())),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Map',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.map_outlined, color: Colors.green),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductGrid() {
    if (_isLoading && _allProducts.isEmpty) {
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

    if (_currentUserPosition == null && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredProducts = _allProducts.where((product) {
      final productName =
      (product['productName'] as String? ?? '').toLowerCase();
      final searchText = _searchController.text.trim().toLowerCase();
      final matchesSearch =
          searchText.isEmpty || productName.contains(searchText);

      final productCategory =
      (product['category'] as String? ?? '').trim();
      final matchesCategory = _selectedCategory == 'All' ||
          productCategory == _selectedCategory;

      final coords = _getCoordinates(product);
      if (coords == null) return false;

      if (_currentUserPosition == null) return matchesSearch && matchesCategory;

      final distance = _calculateDistance(
        _currentUserPosition!.latitude,
        _currentUserPosition!.longitude,
        coords.latitude,
        coords.longitude,
      );
      final matchesRadius = distance <= _searchRadius;

      return matchesSearch && matchesCategory && matchesRadius;
    }).toList();

    if (_currentUserPosition != null) {
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
    }

    if (filteredProducts.isEmpty && !_isLoading) {
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
        final distance = (coords == null || _currentUserPosition == null)
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
  }
}

class _LatLng {
  final double latitude;
  final double longitude;
  _LatLng(this.latitude, this.longitude);
}

class PromoBanner extends StatelessWidget {
  const PromoBanner({super.key});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 150,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Image.asset(
          'assets/farmers_market.jpeg',
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (context, error, stackTrace) => Container(
            decoration: BoxDecoration(
                color: Colors.amber[100],
                borderRadius: BorderRadius.circular(15)),
            child: Center(
              child: Text('Farmers Market',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[900])),
            ),
          ),
        ),
      ),
    );
  }
}

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
    final isVerified = product['profiles']?['is_verified'] ?? false;

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
                  if (isVerified)
                    Positioned(
                      bottom: 5,
                      left: 5,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.verified, color: Colors.green, size: 16),
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
