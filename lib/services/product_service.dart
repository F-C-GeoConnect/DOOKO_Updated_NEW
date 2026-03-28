import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Helper to get the storage path from a full URL or path string
  static String getStoragePath(String? urlOrPath) {
    if (urlOrPath == null || urlOrPath.isEmpty) return '';
    if (urlOrPath.contains('product_images/')) {
      return urlOrPath.split('product_images/').last;
    }
    return urlOrPath;
  }

  Future<List<Map<String, dynamic>>> getProductsForHomepage({int offset = 0, int limit = 10}) async {
    try {
      // OPTIMIZED: Selecting only necessary columns to reduce egress
      final response = await _supabase
          .from('products')
          .select('id, productName, price, imageUrl, seller_id, location, latitude, longitude, category, profiles:seller_id(is_verified)')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      // Fallback to RPC if the join/range fails (though it shouldn't if schema is correct)
      try {
        final response = await _supabase.rpc('get_products_for_homepage');
        return (response as List).map((item) => item as Map<String, dynamic>).toList();
      } catch (rpcError) {
        rethrow;
      }
    }
  }

  Future<String> uploadProductImage(File imageFile) async {
    try {
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.${imageFile.path.split('.').last}';
      await _supabase.storage.from('product_images').upload(fileName, imageFile);
      return _supabase.storage.from('product_images').getPublicUrl(fileName);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> postProduct({
    required String name,
    required double price,
    required String description,
    required String imageUrl,
    required String category,
    required String unit,
    required double totalQuantity,
    required String locationString,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    try {
      await _supabase.from('products').insert({
        'productName': name,
        'price': price,
        'description': description,
        'imageUrl': imageUrl,
        'sellerName': user.userMetadata?['full_name'] ?? 'Anonymous Seller',
        'sellerID': user.id,
        'seller_id': user.id,
        'location': locationString,
        'unit': unit,
        'category': category,
        'total_quantity': totalQuantity,
      });
    } catch (e) {
      rethrow;
    }
  }

  /// OPTIMAL: Atomic stock reduction using RPC
  Future<void> reduceStockAtomic(int productId, double amount) async {
    try {
      await _supabase.rpc('reduce_stock', params: {
        'p_id': productId,
        'p_amount': amount,
      });
    } catch (e) {
      throw 'Failed to update stock: $e';
    }
  }

  Future<void> updateProductStock(int productId, double newQuantity) async {
    try {
      await _supabase.from('products').update({'total_quantity': newQuantity}).eq('id', productId);
    } catch (e) {
      rethrow;
    }
  }
}
