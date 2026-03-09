import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:esewa_flutter/esewa_flutter.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/supabase_image.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isProcessing = false;
  String _paymentMethod = 'COD';
  late String _orderId;

  @override
  void initState() {
    super.initState();
    _orderId = "order_${DateTime.now().millisecondsSinceEpoch}";
  }

  Future<void> _completeOrder(CartProvider cart, {dynamic paymentDetails}) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return;
    setState(() => _isProcessing = true);

    try {
      final cartItems = cart.items.values.toList();
      final List<Map<String, dynamic>> productDataList = [];

      for (var item in cartItems) {
        final productData = await supabase.from('products').select('quantity, seller_id, productName').eq('id', item.id).single();
        if (productData['seller_id'] == user.id) throw 'You cannot purchase your own product (${item.name}).';
        if (productData['quantity'] < item.quantity) throw 'Sorry, ${item.name} only has ${productData['quantity']} units left.';
        productDataList.add(productData);
      }

      for (var i = 0; i < cartItems.length; i++) {
        final item = cartItems[i];
        final productData = productDataList[i];

        await supabase.from('orders').insert({
          'buyer_id': user.id,
          'seller_id': productData['seller_id'],
          'total_amount': item.price * item.quantity,
          'status': 'pending',
          'payment_method': _paymentMethod,
          'payment_details': paymentDetails,
          'items': [{
            'product_id': item.id,
            'product_name': item.name,
            'quantity': item.quantity,
            'price': item.price,
          }],
        });

        await supabase.from('products').update({'quantity': (productData['quantity'] as int) - item.quantity}).eq('id', item.id);
      }

      await cart.checkout(supabase, user.id);

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Order Placed!'),
            content: Text(_paymentMethod == 'ESEWA'
                ? 'Payment successful and order placed!'
                : 'Order placed successfully! The farmers have been notified.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: const Text('OK'),
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Checkout failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final cartItems = cart.items.values.toList();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("My Cart", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: cartItems.isEmpty
          ? _buildEmptyCart()
          : Column(
        children: [
          Expanded(child: _buildCartList(cartItems, cart)),
          _buildPaymentSelection(),
          _buildBottomSummary(cart),
        ],
      ),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text("Your cart is empty!", style: TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildCartList(List<CartItem> cartItems, CartProvider cart) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8.0),
      itemCount: cartItems.length,
      itemBuilder: (ctx, i) {
        final item = cartItems[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SupabaseImage(
                imagePath: item.image,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
            title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Rs. ${item.price.toStringAsFixed(2)}", style: const TextStyle(color: Colors.green)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.green), onPressed: () => cart.decrementItem(item.id)),
                Text('${item.quantity}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.green), onPressed: () => cart.incrementItem(item.id)),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => cart.removeItem(item.id)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaymentSelection() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Select Payment Method", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          RadioListTile<String>(
            title: const Text('Cash on Delivery'),
            value: 'COD',
            groupValue: _paymentMethod,
            onChanged: (val) => setState(() => _paymentMethod = val!),
          ),
          RadioListTile<String>(
            title: const Text('eSewa Payment'),
            value: 'ESEWA',
            groupValue: _paymentMethod,
            onChanged: (val) => setState(() => _paymentMethod = val!),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSummary(CartProvider cart) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Total Amount", style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text("Rs. ${cart.totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            Flexible(child: _buildCheckoutButton(cart)),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutButton(CartProvider cart) {
    if (_paymentMethod == 'ESEWA') {
      return SizedBox(
        width: 160,
        height: 50,
        child: EsewaPayButton(
          paymentConfig: ESewaConfig.dev(
            amount: cart.totalAmount.toDouble(),
            successUrl: "https://developer.esewa.com.np/success",
            failureUrl: "https://developer.esewa.com.np/failure",
            secretKey: '8gBm/:&EnhH.1/q',
            productCode: "EPAYTEST",
            transactionUuid: _orderId,
          ),
          onSuccess: (resp) {
            _completeOrder(cart, paymentDetails: {"encoded_response": resp.data});
          },
          onFailure: (message) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Payment Failed: $message"), backgroundColor: Colors.red));
          },
        ),
      );
    } else {
      return ElevatedButton(
        onPressed: _isProcessing ? null : () => _completeOrder(cart),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isProcessing
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text("Place Order", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      );
    }
  }
}
