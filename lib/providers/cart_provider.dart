import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/chat_service.dart'; // Import ChatService to use its helper

class CartItem {
  final int id;
  final String name;
  final double price;
  final String image;
  final String sellerId; // Added sellerId
  int quantity;

  CartItem({
    required this.id,
    required this.name,
    required this.price,
    required this.image,
    required this.quantity,
    required this.sellerId, // Added sellerId
  });
}

class CartProvider with ChangeNotifier {
  final Map<int, CartItem> _items = {};

  // Returns a copy of the internal map (Map<int, CartItem>)
  Map<int, CartItem> get items => {..._items};

  // Use this for the count badge on your cart icon
  int get itemCount => _items.length;

  // Use this for displaying total in cart screen
  double get totalAmount {
    double total = 0.0;
    _items.forEach((key, cartItem) {
      total += cartItem.price * cartItem.quantity;
    });
    return total;
  }

  bool isItemInCart(int productId) {
    return _items.containsKey(productId);
  }

  // Call this from product cards to add/remove items
  void toggleCartStatus(
      int productId, String name, double price, String image, String sellerId) { // Added sellerId
    if (isItemInCart(productId)) {
      _items.remove(productId);
    } else {
      _items.putIfAbsent(
        productId,
            () => CartItem(
          id: productId,
          name: name,
          price: price,
          image: image,
          quantity: 1,
          sellerId: sellerId, // Added sellerId
        ),
      );
    }
    notifyListeners();
  }

  // Call this from the cart screen + button
  void incrementItem(int productId) {
    if (!_items.containsKey(productId)) return;
    _items[productId]!.quantity++;
    notifyListeners();
  }

  // Call this from the cart screen - button
  void decrementItem(int productId) {
    if (!_items.containsKey(productId)) return;
    if (_items[productId]!.quantity > 1) {
      _items[productId]!.quantity--;
    } else {
      _items.remove(productId);
    }
    notifyListeners();
  }

  // Call this from the cart screen delete button
  void removeItem(int productId) {
    _items.remove(productId);
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  // New checkout method
  Future<void> checkout(SupabaseClient supabase, String currentUserId) async {
    if (_items.isEmpty) {
      print("Cart is empty. No items to checkout.");
      return;
    }

    final Set<String> distinctSellerIds = {};
    _items.forEach((key, cartItem) {
      distinctSellerIds.add(cartItem.sellerId);
    });

    for (final sellerId in distinctSellerIds) {
      // Use the official helper for consistent conversation ID generation
      final conversationId = ChatService.buildConversationId(
        currentUserId,
        sellerId,
      );
      
      try {
        // 1. Send the automated Chat Message
        await supabase.from('messages').insert({
          'sender_id': currentUserId,
          'receiver_id': sellerId,
          'content': "Hey, I'm interested in your product.",
          'conversation_id': conversationId,
        });
        print("Message sent to seller: $sellerId");

        // 2. Send the In-App Notification (Bell icon)
        await supabase.from('notifications').insert({
          'user_id': sellerId,
          'title': 'New Order Received!',
          'message': 'Someone just placed an order for your products.',
          'type': 'order',
          'is_read': false,
        });
        print("Notification sent to seller: $sellerId");

      } catch (e) {
        print("Error during checkout notifications for seller $sellerId: $e");
      }
    }

    _items.clear();
    notifyListeners();
    print("Checkout complete and cart cleared.");
  }
}
