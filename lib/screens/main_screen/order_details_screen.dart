import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class OrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _supabase = Supabase.instance.client;
  late Map<String, dynamic> _currentOrder;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Colors.orange;
      case 'accepted': return Colors.blue;
      case 'shipped': return Colors.purple;
      case 'out_for_delivery': return Colors.indigo;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  Map<String, String> _getDeliveryBoyInfo() {
    return {
      'name': 'Ram Bahadur',
      'phone': '+977-9801234567',
      'vehicle': 'Electric Scooter (BA 1 PA 1234)',
      'rating': '4.8 ★',
    };
  }

  @override
  Widget build(BuildContext context) {
    final items = _currentOrder['items'] as List<dynamic>;
    final status = _currentOrder['status'] ?? 'pending';
    final isBuyer = _currentOrder['buyer_id'] == _supabase.auth.currentUser?.id;
    final deliveryBoy = _getDeliveryBoyInfo();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Order Journey', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildStatusHeader(status),
            _buildOrderJourney(status),
            if (status == 'shipped' || status == 'out_for_delivery') _buildDeliveryBoyCard(deliveryBoy),
            _buildSectionHeader('Delivery Address'),
            _buildAddressCard(),
            _buildSectionHeader('Items Ordered'),
            _buildItemsList(items),
            _buildOrderSummary(),
            
            // Add Review Button if order is completed and user is buyer
            if (isBuyer && status == 'completed') ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ElevatedButton.icon(
                  onPressed: () => _showReviewDialog(items),
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Rate Products', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(String status) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text('Order ID: #${_currentOrder['id'].toString().substring(0, 8)}', 
            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 8),
          Text(status.toUpperCase(), 
            style: TextStyle(color: _getStatusColor(status), fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Placed on ${_formatDate(_currentOrder['created_at'])}', 
            style: TextStyle(color: Colors.grey[500], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildOrderJourney(String currentStatus) {
    final statuses = ['pending', 'accepted', 'shipped', 'out_for_delivery', 'completed'];
    int currentIndex = statuses.indexOf(currentStatus.toLowerCase());
    if (currentStatus.toLowerCase() == 'cancelled') currentIndex = -1;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Track Journey', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          ...statuses.asMap().entries.map((entry) {
            int idx = entry.key;
            String s = entry.value;
            bool isCompleted = idx <= currentIndex;
            bool isLast = idx == statuses.length - 1;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        color: isCompleted ? Colors.green : Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: isCompleted ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
                    ),
                    if (!isLast)
                      Container(width: 2, height: 40, color: isCompleted ? Colors.green : Colors.grey[300]),
                  ],
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_getStatusLabel(s), 
                      style: TextStyle(fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal, 
                      color: isCompleted ? Colors.black : Colors.grey)),
                    const SizedBox(height: 4),
                    if (isCompleted) 
                      Text('Successfully processed', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDeliveryBoyCard(Map<String, String> boy) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 25, backgroundColor: Colors.green[100], child: const Icon(Icons.person, color: Colors.green)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(boy['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('Delivery Partner • ${boy['rating']}', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                Text(boy['vehicle']!, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.phone, color: Colors.green),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Text(_currentOrder['delivery_address'] ?? 'No address provided', 
                style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList(List<dynamic> items) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            title: Text(item['product_name'] ?? 'Item'),
            subtitle: Text('Qty: ${item['quantity']}'),
            trailing: Text('Rs. ${(item['price'] * item['quantity']).toStringAsFixed(2)}', 
              style: const TextStyle(fontWeight: FontWeight.bold)),
          );
        },
      ),
    );
  }

  Widget _buildOrderSummary() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _buildSummaryRow('Subtotal', 'Rs. ${(_currentOrder['total_amount'] as num).toStringAsFixed(2)}'),
          _buildSummaryRow('Delivery Fee', 'Rs. 50.00'),
          const Divider(height: 24),
          _buildSummaryRow('Total', 'Rs. ${((_currentOrder['total_amount'] as num) + 50).toStringAsFixed(2)}', isBold: true),
          const SizedBox(height: 8),
          Text('Payment Method: ${_currentOrder['payment_method'] ?? 'COD'}', 
            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, 
            color: isBold ? Colors.green : Colors.black)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 0.5)),
      ),
    );
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending': return 'Order Placed';
      case 'accepted': return 'Order Accepted';
      case 'shipped': return 'Shipped from Farm';
      case 'out_for_delivery': return 'Out for Delivery';
      case 'completed': return 'Delivered';
      default: return status;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.parse(dateStr);
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showReviewDialog(List<dynamic> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _ReviewSheet(items: items, userId: _supabase.auth.currentUser!.id),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  final List<dynamic> items;
  final String userId;
  const _ReviewSheet({required this.items, required this.userId});

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final Map<dynamic, int> _ratings = {};
  final Map<dynamic, TextEditingController> _controllers = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    for (var item in widget.items) {
      final id = item['product_id'];
      _ratings[id] = 5;
      _controllers[id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _controllers.values.forEach((c) => c.dispose());
    super.dispose();
  }

  Future<void> _submitReviews() async {
    setState(() => _isSubmitting = true);
    final supabase = Supabase.instance.client;

    try {
      for (var item in widget.items) {
        final productId = item['product_id'];
        await supabase.from('product_reviews').upsert({
          'product_id': productId,
          'user_id': widget.userId,
          'rating': _ratings[productId],
          'comment': _controllers[productId]?.text.trim(),
        }, onConflict: 'product_id,user_id');
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for your reviews!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit reviews: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rate Your Products', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('How was the quality of the items you received?', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            ...widget.items.map((item) {
              final id = item['product_id'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['product_name'] ?? 'Product', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(5, (index) => IconButton(
                        onPressed: () => setState(() => _ratings[id] = index + 1),
                        icon: Icon(
                          index < (_ratings[id] ?? 0) ? Icons.star : Icons.star_border,
                          color: Colors.amber, size: 28,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _controllers[id],
                      decoration: InputDecoration(
                        hintText: 'Add a comment (optional)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitReviews,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSubmitting 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Submit Reviews', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
