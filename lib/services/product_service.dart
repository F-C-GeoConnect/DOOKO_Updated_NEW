import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getProductsForHomepage() async {
    try {
      final response = await _supabase
          .from('products')
          .select('*') 
          .order('created_at', ascending: false);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching products: $e');
      rethrow;
    }
  }

  Future<String> uploadProductImage(File imageFile) async {
    try {
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.${imageFile.path.split('.').last}';
      await _supabase.storage.from('product_images').upload(fileName, imageFile);
      return fileName;
    } catch (e) {
      print('Error uploading image: $e');
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
        'total_quantity': totalQuantity, // Using total_quantity only
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getProductStockInfo(int productId) async {
    try {
      return await _supabase
          .from('products')
          .select('total_quantity, seller_id, productName')
          .eq('id', productId)
          .single();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateProductStock(int productId, double remainingQuantity) async {
    try {
      await _supabase.from('products').update({'total_quantity': remainingQuantity}).eq('id', productId);
    } catch (e) {
      rethrow;
    }
  }
}
