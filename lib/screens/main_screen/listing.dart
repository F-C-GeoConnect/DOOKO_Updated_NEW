import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'orders_history_screen.dart';
import '../../widgets/supabase_image.dart';
import '../../services/product_service.dart';

class ListingPage extends StatefulWidget {
  const ListingPage({super.key});

  @override
  State<ListingPage> createState() => _ListingPageState();
}

class _ListingPageState extends State<ListingPage> {
  final _supabase = Supabase.instance.client;
  
  // OPTIMIZED: Switch from Stream to 15s polling to drastically reduce egress
  Future<List<Map<String, dynamic>>>? _productsFuture;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _refreshProducts();
    // Polling every 15 seconds as recommended for best balance of UX and egress
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshProducts());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _refreshProducts() {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return;

    // OPTIMIZED: Selecting only essential columns and limiting results to 100
    setState(() {
      _productsFuture = _supabase
          .from('products')
          .select('id, productName, price, imageUrl, total_quantity, created_at')
          .eq('seller_id', currentUser.id)
          .order('created_at', ascending: false)
          .limit(100);
    });
  }

  Future<void> _updateQuantity(int productId, int currentQuantity, int change) async {
    int newQuantity = currentQuantity + change;
    if (newQuantity >= 0) {
      try {
        await _supabase
            .from('products')
            .update({'total_quantity': newQuantity})
            .eq('id', productId);
        _refreshProducts();
      } catch (e) {
        debugPrint('Error updating quantity: $e');
      }
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final imageUrl = product['imageUrl'] as String?;
    final productId = product['id'];
    final userId = _supabase.auth.currentUser?.id;

    if (userId == null) return;

    try {
      final response = await _supabase
          .from('products')
          .delete()
          .eq('id', productId)
          .eq('seller_id', userId)
          .select('id');

      if (response.isEmpty) {
        throw 'No permission to delete this product.';
      }

      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          final fileName = ProductService.getStoragePath(imageUrl);
          await _supabase.storage.from('product_images').remove([fileName]);
        } catch (storageError) {
          debugPrint('Storage deletion error: $storageError');
        }
      }

      _refreshProducts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product deleted successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete product: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showDeleteConfirmationDialog(Map<String, dynamic> product) async {
    final productName = product['productName'] ?? 'the product';
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete "$productName"?'),
          actions: <Widget>[
            TextButton(child: const Text('No'), onPressed: () => Navigator.of(context).pop()),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Yes'),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteProduct(product);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Activity', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            labelColor: Colors.green,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.green,
            tabs: [
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'My Listings'),
              Tab(icon: Icon(Icons.shopping_bag_outlined), text: 'My Orders'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildListingsTab(),
            const OrdersHistoryScreen(),
          ],
        ),
      ),
    );
  }

  Widget _buildListingsTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _productsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Something went wrong: ${snapshot.error}'));
        }

        final products = snapshot.data ?? [];

        if (products.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'You have not posted any products yet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            final quantity = (product['total_quantity'] ?? 0) as num;
            final imagePath = ProductService.getStoragePath(product['imageUrl']);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SupabaseImage(
                    imagePath: imagePath,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                  ),
                ),
                title: Text(product['productName'] ?? 'No Name', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Rs.${product['price'] ?? 0}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _showDeleteConfirmationDialog(product)),
                    IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _updateQuantity(product['id'], quantity.toInt(), -1)),
                    Text('$quantity', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _updateQuantity(product['id'], quantity.toInt(), 1)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
