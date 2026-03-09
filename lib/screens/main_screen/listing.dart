import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'orders_history_screen.dart';
import '../../widgets/supabase_image.dart'; // IMPORTED shared widget

class ListingPage extends StatefulWidget {
  const ListingPage({super.key});

  @override
  State<ListingPage> createState() => _ListingPageState();
}

class _ListingPageState extends State<ListingPage> {
  final _supabase = Supabase.instance.client;
  late Stream<List<Map<String, dynamic>>> _productsStream;

  @override
  void initState() {
    super.initState();
    _productsStream = _fetchUserProducts();
  }

  Stream<List<Map<String, dynamic>>> _fetchUserProducts() {
    final currentUser = _supabase.auth.currentUser;
    return _supabase
        .from('products')
        .stream(primaryKey: ['id', 'description', 'sellerName'])
        .eq('seller_id', currentUser?.id ?? '')
        .order('created_at', ascending: false);
  }

  Future<void> _refreshProducts() async {
    setState(() {
      _productsStream = _fetchUserProducts();
    });
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<void> _updateQuantity(int productId, int currentQuantity, int change) async {
    int newQuantity = currentQuantity + change;
    if (newQuantity >= 0) {
      await _supabase
          .from('products')
          .update({'quantity': newQuantity})
          .eq('id', productId);
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final imageUrl = product['imageUrl'] as String?;
    final productId = product['id'];

    try {
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          // If it's a full URL, split to get the filename. If it's just the path, use it.
          final fileName = imageUrl.contains('/') ? imageUrl.split('/').last : imageUrl;
          await _supabase.storage.from('product_images').remove([fileName]);
        } catch (storageError) {
          debugPrint('Storage deletion error (continuing): $storageError');
        }
      }

      final response = await _supabase
          .from('products')
          .delete()
          .eq('id', productId)
          .eq('description', product['description'])
          .eq('sellerName', product['sellerName'])
          .select();

      if (response.isEmpty) {
        throw 'No permission to delete this product or product not found.';
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
    return RefreshIndicator(
      onRefresh: _refreshProducts,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _productsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
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
                  'You have not posted any products yet. Swipe down to refresh.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(8),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              final imagePath = product['imageUrl'] as String? ?? '';

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SupabaseImage( // UPDATED to use SupabaseImage
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
                      IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _updateQuantity(product['id'], (product['quantity'] as num).toInt(), -1)),
                      Text('${product['quantity']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _updateQuantity(product['id'], (product['quantity'] as num).toInt(), 1)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
