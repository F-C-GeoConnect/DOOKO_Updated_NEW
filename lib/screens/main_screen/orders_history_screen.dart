import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'order_details_screen.dart';

class OrdersHistoryScreen extends StatefulWidget {
  const OrdersHistoryScreen({super.key});

  @override
  State<OrdersHistoryScreen> createState() => _OrdersHistoryScreenState();
}

class _OrdersHistoryScreenState extends State<OrdersHistoryScreen> {
  final _supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  final NumberFormat _currencyFormat = NumberFormat.currency(
    symbol: 'Rs. ',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _ordersFuture = _fetchOrders();
  }

  Future<List<Map<String, dynamic>>> _fetchOrders() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final data = await _supabase
          .from('orders')
          .select('*, items')
          .or('buyer_id.eq.$userId,seller_id.eq.$userId')
          .order('created_at', ascending: false);
      
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Error fetching orders: $e');
      return [];
    }
  }

  Future<void> _acceptOrder(Map<String, dynamic> order) async {
    final orderId = order['id'];
    final items = order['items'] as List<dynamic>? ?? [];

    try {
      // 1. Update order status to 'accepted'
      await _supabase
          .from('orders')
          .update({'status': 'accepted'})
          .eq('id', orderId);
      
      // 2. Decrease stock for each product in the order
      for (var item in items) {
        final productId = item['product_id'];
        final orderedQty = num.tryParse(item['quantity'].toString()) ?? 0;

        if (productId == null) continue;

        // Fetch current stock from 'products' table
        final productResponse = await _supabase
            .from('products')
            .select('total_quantity')
            .eq('id', productId)
            .maybeSingle();

        if (productResponse != null) {
          final currentStock = num.tryParse(productResponse['total_quantity'].toString()) ?? 0;
          final newStock = currentStock - orderedQty;

          if (newStock <= 0) {
            // If stock hits 0 or below, delete from listing
            await _supabase.from('products').delete().eq('id', productId);
          } else {
            // Otherwise update the quantity
            await _supabase
                .from('products')
                .update({'total_quantity': newStock})
                .eq('id', productId);
          }
        }
      }
      
      if (mounted) {
        setState(() {
          _ordersFuture = _fetchOrders();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order accepted and stock updated!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Error accepting order: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateOrderStatus(dynamic orderId, String newStatus) async {
    try {
      await _supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);
      
      if (mounted) {
        setState(() {
          _ordersFuture = _fetchOrders();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order marked as $newStatus')),
        );
      }
    } catch (e) {
      debugPrint('Error updating order: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('My Orders', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: RefreshIndicator(
        color: colorScheme.primary,
        onRefresh: () async {
          setState(() {
            _ordersFuture = _fetchOrders();
          });
        },
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _ordersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(color: colorScheme.primary));
            }
            
            final orders = snapshot.data ?? [];
    
            if (orders.isEmpty) {
              return _buildEmptyState(colorScheme);
            }
    
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                final orderId = order['id']; 
                final bool isBuyer = order['buyer_id'] == currentUserId;
                final String status = order['status'] ?? 'pending';
                final items = order['items'] as List<dynamic>;
                final createdAt = DateTime.tryParse(order['created_at'] ?? '')?.toLocal();
                
                final totalAmount = num.tryParse(order['total_amount'].toString()) ?? 0.0;

                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => OrderDetailScreen(order: order)),
                      ).then((_) => setState(() { _ordersFuture = _fetchOrders(); }));
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isBuyer ? 'PURCHASE' : 'INCOMING SALE',
                                    style: TextStyle(
                                      color: isBuyer ? Colors.blue.shade700 : Colors.orange.shade800,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  if (createdAt != null)
                                    Text(
                                      DateFormat('MMM dd, yyyy • hh:mm a').format(createdAt),
                                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                    ),
                                ],
                              ),
                              _buildStatusBadge(status),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12.0),
                            child: Divider(height: 1),
                          ),
                          ...items.map((item) {
                            final itemPrice = num.tryParse(item['price'].toString()) ?? 0.0;
                            final itemQty = num.tryParse(item['quantity'].toString()) ?? 0;
                            
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text('${itemQty}x', 
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(item['product_name'] ?? 'Unknown Product', 
                                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                                      overflow: TextOverflow.ellipsis),
                                  ),
                                  Text(_currencyFormat.format(itemPrice * itemQty),
                                    style: const TextStyle(fontWeight: FontWeight.w500)),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Amount', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                              Text(_currencyFormat.format(totalAmount),
                                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary, fontSize: 18)),
                            ],
                          ),
                          
                          if (!isBuyer && status == 'pending') ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _acceptOrder(order),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: const Text('Accept Order'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _updateOrderStatus(orderId, 'cancelled'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: const Text('Decline'),
                                  ),
                                ),
                              ],
                            )
                          ],

                          if (!isBuyer && status == 'accepted') ...[
                            const SizedBox(height: 16),
                            _buildAdminActionButton(orderId, 'shipped', 'Mark as Shipped', Colors.purple),
                          ],

                          if (!isBuyer && status == 'shipped') ...[
                            const SizedBox(height: 16),
                            _buildAdminActionButton(orderId, 'out_for_delivery', 'Out for Delivery', Colors.indigo),
                          ],

                          if (!isBuyer && status == 'out_for_delivery') ...[
                            const SizedBox(height: 16),
                            _buildAdminActionButton(orderId, 'completed', 'Mark as Delivered', Colors.green),
                          ],
                          
                          const SizedBox(height: 12),
                          Center(
                            child: Text('Tap to view delivery journey', 
                              style: TextStyle(color: colorScheme.primary.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.receipt_long_outlined, size: 80, color: colorScheme.primary.withOpacity(0.3)),
            ),
            const SizedBox(height: 24),
            const Text('No orders yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Your order history will appear here.', 
              style: TextStyle(color: Colors.grey[600], fontSize: 15)),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('Explore Products'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminActionButton(dynamic orderId, String nextStatus, String label, Color color) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => _updateOrderStatus(orderId, nextStatus),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'pending': color = Colors.orange; break;
      case 'accepted': color = Colors.blue; break;
      case 'shipped': color = Colors.purple; break;
      case 'out_for_delivery': color = Colors.indigo; break;
      case 'completed': color = Colors.green; break;
      case 'cancelled': color = Colors.red; break;
      default: color = Colors.grey;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }
}
