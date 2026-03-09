import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrdersHistoryScreen extends StatefulWidget {
  const OrdersHistoryScreen({super.key});

  @override
  State<OrdersHistoryScreen> createState() => _OrdersHistoryScreenState();
}

class _OrdersHistoryScreenState extends State<OrdersHistoryScreen> {
  final _supabase = Supabase.instance.client;
  late final Stream<List<Map<String, dynamic>>> _ordersStream;

  @override
  void initState() {
    super.initState();
    final userId = _supabase.auth.currentUser?.id;

    _ordersStream = _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((listOfMaps) {
      final uid = userId;
      if (uid == null) return <Map<String, dynamic>>[];
      return listOfMaps
          .where((m) => m['buyer_id'] == uid || m['seller_id'] == uid)
          .toList();
    });
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    try {
      await _supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order marked as $newStatus')),
        );
      }
    } catch (e) {
      debugPrint('Error updating order: $e');
    }
  }

  void _showRatingDialog(Map<String, dynamic> item) {
    int selectedRating = 0;
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Rate ${item['product_name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) => IconButton(
                  icon: Icon(
                    index < selectedRating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 32,
                  ),
                  onPressed: () => setState(() => selectedRating = index + 1),
                )),
              ),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(hintText: 'Write a review...', border: OutlineInputBorder()),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selectedRating == 0 ? null : () async {
                try {
                  final userId = _supabase.auth.currentUser?.id;
                  await _supabase.from('product_reviews').upsert({
                    'product_id': item['product_id'],
                    'user_id': userId,
                    'rating': selectedRating,
                    'comment': commentController.text,
                  }, onConflict: 'product_id,user_id');
                  
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thank you for your review!'), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  debugPrint('Error submitting review: $e');
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _supabase.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('My Orders', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.green));
          }
          
          final orders = snapshot.data ?? [];

          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('No orders yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final bool isBuyer = order['buyer_id'] == currentUserId;
              final String status = order['status'] ?? 'pending';
              final items = order['items'] as List<dynamic>;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isBuyer ? 'Purchase' : 'Incoming Sale',
                            style: TextStyle(
                              color: isBuyer ? Colors.blue : Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          _buildStatusBadge(status),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...items.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text('${item['quantity']}x ${item['product_name']}', style: const TextStyle(fontWeight: FontWeight.w500))),
                            Text('Rs. ${(item['price'] * item['quantity']).toStringAsFixed(2)}'),
                            if (isBuyer && status == 'completed') ...[
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => _showRatingDialog(item),
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                child: const Text('Rate', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ]
                          ],
                        ),
                      )),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('Rs. ${order['total_amount'].toStringAsFixed(2)}', 
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                        ],
                      ),
                      
                      if (!isBuyer && status == 'pending') ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _updateOrderStatus(order['id'], 'accepted'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                child: const Text('Accept', style: TextStyle(color: Colors.white)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _updateOrderStatus(order['id'], 'cancelled'),
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                child: const Text('Decline'),
                              ),
                            ),
                          ],
                        )
                      ],
                      
                      if (!isBuyer && status == 'accepted') ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => _updateOrderStatus(order['id'], 'completed'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                            child: const Text('Mark as Completed', style: TextStyle(color: Colors.white)),
                          ),
                        )
                      ],
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

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status) {
      case 'pending': color = Colors.orange; break;
      case 'accepted': color = Colors.blue; break;
      case 'completed': color = Colors.green; break;
      case 'cancelled': color = Colors.red; break;
      default: color = Colors.grey;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
