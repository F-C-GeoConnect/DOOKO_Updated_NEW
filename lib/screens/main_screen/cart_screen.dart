import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:esewa_flutter/esewa_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/supabase_image.dart';
import '../product_profile.dart';

class CartScreen extends StatefulWidget {
  final CartItem? directItem;

  const CartScreen({super.key, this.directItem});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isProcessing = false;
  String _paymentMethod = 'COD';
  late String _orderId;
  
  final _addressController = TextEditingController();
  Position? _deliveryPosition;
  bool _isLocating = false;

  final NumberFormat _currencyFormat = NumberFormat.currency(
    symbol: 'Rs. ',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _orderId = "order_${DateTime.now().millisecondsSinceEpoch}";
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        final position = await Geolocator.getCurrentPosition();
        setState(() {
          _deliveryPosition = position;
          _addressController.text = "Pinned Location (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})";
        });
      }
    } catch (e) {
      debugPrint("Error getting location: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to get location: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _completeOrder(List<CartItem> itemsToOrder, double totalAmount, {dynamic paymentDetails}) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return;
    
    if (_addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a delivery address or pin your location.')));
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final List<Map<String, dynamic>> productDataList = [];

      for (var item in itemsToOrder) {
        // Fetch current stock from 'products' table
        final productData = await supabase.from('products').select('total_quantity, seller_id, productName').eq('id', item.id).single();
        
        if (productData['seller_id'] == user.id) {
          throw 'You cannot purchase your own product (${item.name}).';
        }
        
        final currentStock = (productData['total_quantity'] as num).toDouble();
        if (currentStock < item.quantity) {
          throw 'Sorry, ${item.name} only has $currentStock units left.';
        }
        productDataList.add(productData);
      }

      for (var i = 0; i < itemsToOrder.length; i++) {
        final item = itemsToOrder[i];
        final productData = productDataList[i];

        // 1. Create the order
        await supabase.from('orders').insert({
          'buyer_id': user.id,
          'seller_id': productData['seller_id'],
          'total_amount': item.price * item.quantity,
          'status': 'pending',
          'payment_method': _paymentMethod,
          'payment_details': paymentDetails,
          'delivery_address': _addressController.text.trim(),
          'delivery_lat': _deliveryPosition?.latitude,
          'delivery_lng': _deliveryPosition?.longitude,
          'items': [{
            'product_id': item.id,
            'product_name': item.name,
            'quantity': item.quantity,
            'price': item.price,
          }],
        });

        // 2. Decrease the stock in 'products' table immediately upon order placement
        final currentStock = (productData['total_quantity'] as num).toDouble();
        final newStock = currentStock - item.quantity;
        
        if (newStock <= 0) {
          // If stock hits 0, delete the listing
          await supabase.from('products').delete().eq('id', item.id);
        } else {
          // Update with reduced stock
          await supabase.from('products').update(
            {'total_quantity': newStock}
          ).eq('id', item.id);
        }
      }

      if (widget.directItem == null) {
        final cart = Provider.of<CartProvider>(context, listen: false);
        await cart.checkout(supabase, user.id);
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Order Placed!'),
            content: Text(_paymentMethod == 'ESEWA'
                ? 'Payment successful and order placed!'
                : 'Order placed successfully! Track your journey in "My Orders".'),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Checkout failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _confirmDelete(BuildContext context, CartProvider cart, int productId) async {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Item?'),
        content: const Text('Are you sure you want to remove this item from your cart?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              cart.removeItem(productId);
              Navigator.pop(ctx);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _navigateToProduct(int productId) async {
    try {
      final data = await Supabase.instance.client.from('products').select().eq('id', productId).single();
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => ProductProfilePage(product: data)));
      }
    } catch (e) {
      debugPrint("Error fetching product: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final List<CartItem> displayItems = widget.directItem != null 
        ? [widget.directItem!] 
        : cart.items.values.toList();
    
    final double totalAmount = widget.directItem != null 
        ? widget.directItem!.price * widget.directItem!.quantity 
        : cart.totalAmount;

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(widget.directItem != null ? "Checkout" : "My Cart", 
            style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: displayItems.isEmpty
          ? _buildEmptyCart(colorScheme)
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      _buildCartList(displayItems, cart, colorScheme),
                      _buildShippingInfo(colorScheme),
                      _buildPaymentSelection(colorScheme),
                    ],
                  ),
                ),
                _buildBottomSummary(totalAmount, colorScheme, displayItems),
              ],
            ),
    );
  }

  Widget _buildEmptyCart(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.shopping_basket_outlined, size: 80, color: colorScheme.primary.withOpacity(0.3)),
            ),
            const SizedBox(height: 24),
            const Text(
              "Your cart is empty!",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Looks like you haven't added anything to your cart yet.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text("Start Shopping", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartList(List<CartItem> items, CartProvider cart, ColorScheme colorScheme) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8.0),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        
        String imagePath = item.image;
        if (item.image.contains('product_images/')) {
          imagePath = item.image.split('product_images/').last;
        }

        return Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: InkWell(
            onTap: () => _navigateToProduct(item.id),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: (imagePath.isNotEmpty) 
                        ? SupabaseImage(
                            imagePath: imagePath, 
                            width: 80, 
                            height: 80, 
                            fit: BoxFit.cover,
                            bucket: 'product_images',
                          )
                        : Container(
                            width: 80, 
                            height: 80, 
                            color: Colors.grey[100],
                            child: const Icon(Icons.image_not_supported, color: Colors.grey),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(_currencyFormat.format(item.price), style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        if (widget.directItem == null)
                        Row(
                          children: [
                            _buildQtyBtn(Icons.remove, () => cart.decrementItem(item.id), colorScheme),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              child: Text('${item.quantity}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            ),
                            _buildQtyBtn(Icons.add, () => cart.incrementItem(item.id), colorScheme),
                          ],
                        )
                        else
                        Text("Quantity: ${item.quantity}", style: const TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  if (widget.directItem == null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(Icons.shopping_bag_outlined, size: 20, color: colorScheme.primary),
                        label: Text("BUY", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => CartScreen(directItem: item)));
                        },
                      ),
                      const SizedBox(height: 4),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                        onPressed: () => _confirmDelete(context, cart, item.id),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQtyBtn(IconData icon, VoidCallback onPressed, ColorScheme colorScheme) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18, color: Colors.black87),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildShippingInfo(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined, color: colorScheme.primary),
              const SizedBox(width: 8),
              const Text("Shipping Information", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _addressController,
            decoration: InputDecoration(
              labelText: "Delivery Address",
              hintText: "Enter your full address",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
              suffixIcon: IconButton(
                icon: _isLocating 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                  : Icon(Icons.my_location, color: colorScheme.primary),
                onPressed: _getCurrentLocation,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Use the icon to pin your current delivery location for faster service.",
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSelection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payment_outlined, color: colorScheme.primary),
              const SizedBox(width: 8),
              const Text("Payment Method", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          RadioListTile<String>(
            title: const Text('Cash on Delivery', style: TextStyle(fontSize: 15)),
            value: 'COD',
            groupValue: _paymentMethod,
            onChanged: (val) => setState(() => _paymentMethod = val!),
            activeColor: colorScheme.primary,
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<String>(
            title: const Text('eSewa Wallet', style: TextStyle(fontSize: 15)),
            value: 'ESEWA',
            groupValue: _paymentMethod,
            onChanged: (val) => setState(() => _paymentMethod = val!),
            activeColor: colorScheme.primary,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSummary(double amount, ColorScheme colorScheme, List<CartItem> itemsToOrder) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Total Payable", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(_currencyFormat.format(amount), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.primary)),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(child: _buildCheckoutButton(amount, colorScheme, itemsToOrder)),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutButton(double amount, ColorScheme colorScheme, List<CartItem> itemsToOrder) {
    if (_paymentMethod == 'ESEWA') {
      return SizedBox(
        height: 52,
        child: EsewaPayButton(
          paymentConfig: ESewaConfig.dev(
            amount: amount,
            successUrl: "https://developer.esewa.com.np/success",
            failureUrl: "https://developer.esewa.com.np/failure",
            secretKey: '8gBm/:&EnhH.1/q',
            productCode: "EPAYTEST",
            transactionUuid: _orderId,
          ),
          onSuccess: (resp) {
            _completeOrder(itemsToOrder, amount, paymentDetails: {"encoded_response": resp.data});
          },
          onFailure: (message) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Payment Failed: $message"), backgroundColor: Colors.red));
          },
        ),
      );
    } else {
      return ElevatedButton(
        onPressed: _isProcessing ? null : () => _completeOrder(itemsToOrder, amount),
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _isProcessing
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text("Place Order", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );
    }
  }
}
