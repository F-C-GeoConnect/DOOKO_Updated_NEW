import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../providers/cart_provider.dart';
import '../../widgets/product_rating.dart';
import '../../widgets/supabase_image.dart'; // IMPORTED shared widget
import '../product_profile.dart';
import 'cart_screen.dart';
import 'notifications_screen.dart';
import 'map.dart'; 

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Map<String, dynamic>>> _productsFuture;
  final _searchController = TextEditingController();
  
  double _searchRadius = 20;
  Position? _currentUserPosition;

  List<Map<String, dynamic>> _notifications = [];
  RealtimeChannel? _notificationsChannel;

  @override
  void initState() {
    super.initState();
    _productsFuture = _getProducts();
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

  Future<List<Map<String, dynamic>>> _getProducts() async {
    try {
      final response = await Supabase.instance.client.rpc('get_products_for_homepage');
      final products = (response as List).map((item) => item as Map<String, dynamic>).toList();
      
      products.sort((a, b) {
        final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(0);
        final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(0);
        return dateB.compareTo(dateA);
      });
      
      return products;
    } catch (e) {
      debugPrint('Error fetching products via RPC: $e');
      return [];
    }
  }

  Future<void> _handleRefresh() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) await _fetchNotifications(userId);
    
    final position = await _determinePosition();
    setState(() {
      _currentUserPosition = position;
      _productsFuture = _getProducts();
    });
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('Location services are disabled.');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return Future.error('Location permissions are denied.');
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    }

    return await Geolocator.getCurrentPosition();
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 + c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
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
                  Text('Show products within ${tempRadius.toStringAsFixed(0)} km'),
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
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
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
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
          callback: (payload) => _fetchNotifications(userId),
        )
        .subscribe();
  }

  Future<void> _fetchNotifications(String userId) async {
    try {
      final data = await Supabase.instance.client.from('notifications').select().eq('user_id', userId).order('created_at', ascending: false);
      if (mounted) setState(() => _notifications = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    }
  }

  Future<void> _markAllNotificationsAsRead() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client.from('notifications').update({'is_read': true}).eq('user_id', userId).eq('is_read', false);
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
    final unreadCount = _notifications.where((n) => n['is_read'] == false).length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('DOOKO', style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 24)),
            Row(
              children: [
                Consumer<CartProvider>(
                  builder: (context, cart, child) => Stack(
                    children: [
                      IconButton(
                        icon: Icon(Icons.shopping_basket_outlined, color: Colors.grey.shade700),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CartScreen())),
                      ),
                      if (cart.itemCount > 0)
                        Positioned(
                          right: 8, top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(cart.itemCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10), textAlign: TextAlign.center),
                          ),
                        ),
                    ],
                  ),
                ),
                Stack(
                  children: [
                    IconButton(
                      icon: Icon(Icons.notifications_outlined, color: Colors.grey.shade700),
                      onPressed: () async {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsScreen())).then((_) => _markAllNotificationsAsRead());
                      },
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 8, top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(unreadCount > 99 ? '99+' : unreadCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchBar(),
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
        suffixIcon: IconButton(icon: const Icon(Icons.filter_list), onPressed: _showRadiusFilter),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        IconButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MapPage())),
          icon: const Icon(Icons.map_outlined, color: Colors.green),
        ),
      ],
    );
  }

  Widget _buildProductGrid() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _productsFuture,
      builder: (context, snapshot) {
        if (_currentUserPosition == null) return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Fetching your location...')));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.green));
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));

        final allProducts = snapshot.data ?? [];
        if (allProducts.isEmpty) return const Center(child: Text('No products available yet.'));

        final filteredProducts = allProducts.where((product) {
          final productName = product['productName'] as String? ?? '';
          final matchesSearch = productName.toLowerCase().contains(_searchController.text.toLowerCase());

          final lat = (product['latitude'] as num?)?.toDouble();
          final lng = (product['longitude'] as num?)?.toDouble();
          if (lat == null || lng == null) return matchesSearch;

          final distance = _calculateDistance(_currentUserPosition!.latitude, _currentUserPosition!.longitude, lat, lng);
          return matchesSearch && (distance <= _searchRadius);
        }).toList();

        if (filteredProducts.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text('No products found within your search radius.', textAlign: TextAlign.center)));
        }

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 0.8),
          itemCount: filteredProducts.length,
          itemBuilder: (context, index) => ProductCard(product: filteredProducts[index]),
        );
      },
    );
  }
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
        child: Container(
          decoration: BoxDecoration(color: Colors.amber[100]),
          child: Image.network(
            'https://clipart-library.com/2023/5f0d0ab64520712d29e2c2fd_NEW20Summer20Market20Logo20white.png',
            fit: BoxFit.fill,
            errorBuilder: (context, error, stackTrace) => Center(child: Text('Summer Market', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange[900]))),
          ),
        ),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  const ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final imagePath = product['imageUrl'] as String? ?? 'https://i.imgur.com/S8A4L5p.png';
    final productId = (product['id'] as num?)?.toInt() ?? 0;
    final productName = product['productName'] as String? ?? 'No Name';
    final price = (product['price'] as num?)?.toDouble() ?? 0.0;
    final sellerId = product['seller_id'] as String? ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProductProfilePage(product: product))),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        elevation: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  SizedBox.expand(
                    child: SupabaseImage(imagePath: imagePath), // Using shared widget
                  ),
                  Positioned(
                    top: 5, right: 5,
                    child: Container(
                      decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle),
                      child: Consumer<CartProvider>(
                        builder: (context, cart, child) {
                          final isAdded = cart.isItemInCart(productId);
                          return IconButton(
                            iconSize: 20,
                            icon: Icon(isAdded ? Icons.shopping_cart : Icons.shopping_cart_outlined, color: isAdded ? Colors.red : Colors.black54),
                            onPressed: () => cart.toggleCartStatus(productId, productName, price, imagePath, sellerId),
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
                  Text(productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('Rs.${price.toStringAsFixed(2)}', style: TextStyle(color: Colors.grey.shade800, fontSize: 14)),
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
