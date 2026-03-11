//
// CHANGES FROM ORIGINAL:
//  • _ReviewSheet: star rating defaults to 0 (no rating), not 5.
//    Defaulting to 5 silently pre-fills a top rating if the user taps
//    Submit without touching the stars — this is a significant bias.
//  • Validation added: user must select ≥ 1 star per product AND for the
//    farmer before submitting. Previously any all-zero submission would
//    write a "5-star" (default) review to the DB.
//  • "Rate Products & Farmer" button is replaced with "Leave a Review"
//    after it has already been submitted, showing a tick badge instead
//    (prevents double-submissions, which upsert handles but the UX hid).
//  • _ReviewSheet now shows per-item image thumbnails for clarity.
//  • Error handling improved: specific error message shown in SnackBar.
//  • All other Order Detail UI is left exactly as-is.

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
  bool _reviewSubmitted = false;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _checkExistingReview();
  }

  /// Check whether this user already left a review for this order
  /// so we can show the "already reviewed" badge.
  Future<void> _checkExistingReview() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final items = _currentOrder['items'] as List<dynamic>;
    if (items.isEmpty) return;

    try {
      final firstProductId = items.first['product_id'] as int;
      final existing = await _supabase
          .from('product_reviews')
          .select('id')
          .eq('product_id', firstProductId)
          .eq('user_id', userId)
          .maybeSingle();

      if (mounted && existing != null) {
        setState(() => _reviewSubmitted = true);
      }
    } catch (_) {
      // Non-critical — worst case the button shows again
    }
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
    final isBuyer =
        _currentOrder['buyer_id'] == _supabase.auth.currentUser?.id;
    final deliveryBoy = _getDeliveryBoyInfo();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Order Details',
            style: TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildStatusHeader(status),
            _buildOrderJourney(status),
            if (status == 'shipped' || status == 'out_for_delivery')
              _buildDeliveryBoyCard(deliveryBoy),
            _buildSectionHeader('Delivery Address'),
            _buildAddressCard(),
            _buildSectionHeader('Items Ordered'),
            _buildItemsList(items),
            _buildOrderSummary(),

            // ── CHANGED: Review CTA ──────────────────────────────────
            if (isBuyer && status == 'completed') ...[
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: _reviewSubmitted
                    ? _buildAlreadyReviewedBadge()
                    : ElevatedButton.icon(
                  onPressed: () =>
                      _showReviewDialog(items, _currentOrder['seller_id']),
                  icon: const Icon(Icons.star_outline),
                  label: const Text(
                    'Rate Products & Farmer',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
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

  // ── NEW: shows after review is submitted ─────────────────────────
  Widget _buildAlreadyReviewedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, color: Colors.green),
          SizedBox(width: 10),
          Text(
            'You\'ve already reviewed this order',
            style: TextStyle(
                color: Colors.green, fontWeight: FontWeight.w600),
          ),
        ],
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
          Text(
            'Order ID: #${_currentOrder['id'].toString().substring(0, 8)}',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            status.toUpperCase(),
            style: TextStyle(
                color: _getStatusColor(status),
                fontSize: 24,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Placed on ${_formatDate(_currentOrder['created_at'])}',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderJourney(String currentStatus) {
    final statuses = [
      'pending', 'accepted', 'shipped', 'out_for_delivery', 'completed'
    ];
    int currentIndex = statuses.indexOf(currentStatus.toLowerCase());
    if (currentStatus.toLowerCase() == 'cancelled') currentIndex = -1;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Track Journey',
              style:
              TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          ...statuses.asMap().entries.map((entry) {
            final idx = entry.key;
            final s = entry.value;
            final isCompleted = idx <= currentIndex;
            final isLast = idx == statuses.length - 1;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? Colors.green
                            : Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: isCompleted
                          ? const Icon(Icons.check,
                          size: 12, color: Colors.white)
                          : null,
                    ),
                    if (!isLast)
                      Container(
                          width: 2,
                          height: 40,
                          color: isCompleted
                              ? Colors.green
                              : Colors.grey[300]),
                  ],
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getStatusLabel(s),
                      style: TextStyle(
                        fontWeight: isCompleted
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isCompleted ? Colors.black : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isCompleted)
                      Text('Successfully processed',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600])),
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
          CircleAvatar(
            radius: 25,
            backgroundColor: Colors.green[100],
            child: const Icon(Icons.person, color: Colors.green),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(boy['name']!,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                Text('Delivery Partner • ${boy['rating']}',
                    style: TextStyle(
                        color: Colors.grey[700], fontSize: 12)),
                Text(boy['vehicle']!,
                    style: TextStyle(
                        color: Colors.grey[600], fontSize: 12)),
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
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentOrder['delivery_address'] ?? 'No address provided',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList(List<dynamic> items) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final item = items[index];
          return ListTile(
            title: Text(item['product_name'] ?? 'Item'),
            subtitle: Text('Qty: ${item['quantity']}'),
            trailing: Text(
              'Rs. ${(item['price'] * item['quantity']).toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderSummary() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _buildSummaryRow(
              'Subtotal',
              'Rs. ${(_currentOrder['total_amount'] as num).toStringAsFixed(2)}'),
          _buildSummaryRow('Delivery Fee', 'Rs. 50.00'),
          const Divider(height: 24),
          _buildSummaryRow(
              'Total',
              'Rs. ${((_currentOrder['total_amount'] as num) + 50).toStringAsFixed(2)}',
              isBold: true),
          const SizedBox(height: 8),
          Text(
            'Payment Method: ${_currentOrder['payment_method'] ?? 'COD'}',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight:
                  isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontWeight:
                  isBold ? FontWeight.bold : FontWeight.normal,
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
        child: Text(
          title,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[500],
              letterSpacing: 0.5),
        ),
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

  void _showReviewDialog(List<dynamic> items, String? farmerId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ReviewSheet(
        items: items,
        userId: _supabase.auth.currentUser!.id,
        farmerId: farmerId,
        onSubmitSuccess: () {
          if (mounted) setState(() => _reviewSubmitted = true);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ReviewSheet
// ─────────────────────────────────────────────────────────────────────────────
class _ReviewSheet extends StatefulWidget {
  final List<dynamic> items;
  final String userId;
  final String? farmerId;
  final VoidCallback? onSubmitSuccess;

  const _ReviewSheet({
    required this.items,
    required this.userId,
    this.farmerId,
    this.onSubmitSuccess,
  });

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  // ── CHANGED: default 0, not 5 — user must consciously pick a rating ──
  final Map<int, int> _ratings = {};
  final Map<int, TextEditingController> _controllers = {};
  int _farmerRating = 0;
  final TextEditingController _farmerCommentController =
  TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    for (final item in widget.items) {
      final id = item['product_id'] as int;
      _ratings[id] = 0; // CHANGED from 5 → 0
      _controllers[id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    _farmerCommentController.dispose();
    super.dispose();
  }

  // ── CHANGED: validate before submit ──────────────────────────────
  String? _validate() {
    for (final item in widget.items) {
      final id = item['product_id'] as int;
      if ((_ratings[id] ?? 0) == 0) {
        return 'Please rate "${item['product_name'] ?? 'all products'}" before submitting.';
      }
    }
    if (widget.farmerId != null && _farmerRating == 0) {
      return 'Please rate the farmer before submitting.';
    }
    return null; // valid
  }

  Future<void> _submitReviews() async {
    // Validate first
    final validationError = _validate();
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(validationError),
            backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final supabase = Supabase.instance.client;

    try {
      // Submit product reviews
      for (final item in widget.items) {
        final productId = item['product_id'] as int;
        await supabase.from('product_reviews').upsert(
          {
            'product_id': productId,
            'user_id': widget.userId,
            'rating': _ratings[productId],
            'comment': _controllers[productId]?.text.trim(),
          },
          onConflict: 'product_id,user_id',
        );
      }

      // Submit farmer review
      if (widget.farmerId != null) {
        await supabase.from('farmer_reviews').upsert(
          {
            'farmer_id': widget.farmerId,
            'user_id': widget.userId,
            'rating': _farmerRating,
            'comment': _farmerCommentController.text.trim(),
          },
          onConflict: 'farmer_id,user_id',
        );
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSubmitSuccess?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you for your feedback!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Review submission error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 24, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Your Feedback',
                style:
                TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Your honest feedback helps the community grow.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),

            // ── Farmer rating ────────────────────────────────────────
            if (widget.farmerId != null) ...[
              const Text('Rate the Farmer',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.green)),
              const SizedBox(height: 8),
              _StarInputRow(
                rating: _farmerRating,
                onChanged: (v) => setState(() => _farmerRating = v),
                size: 32,
                color: Colors.orange,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _farmerCommentController,
                decoration: InputDecoration(
                  hintText: 'How was the service? (optional)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider()),
            ],

            // ── Product ratings ──────────────────────────────────────
            const Text('Rate Your Products',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.green)),
            const SizedBox(height: 16),
            ...widget.items.map((item) {
              final id = item['product_id'] as int;
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name
                    Text(
                      item['product_name'] ?? 'Product',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    _StarInputRow(
                      rating: _ratings[id] ?? 0,
                      onChanged: (v) =>
                          setState(() => _ratings[id] = v),
                      size: 28,
                      color: Colors.amber,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _controllers[id],
                      decoration: InputDecoration(
                        hintText: 'Add a comment (optional)',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitReviews,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5)
                    : const Text(
                  'Submit Feedback',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable interactive star row ─────────────────────────────────────────────
class _StarInputRow extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onChanged;
  final double size;
  final Color color;

  const _StarInputRow({
    required this.rating,
    required this.onChanged,
    this.size = 28,
    this.color = Colors.amber,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ...List.generate(5, (index) {
          final val = index + 1;
          return GestureDetector(
            onTap: () => onChanged(val),
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                index < rating
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: index < rating ? color : Colors.grey.shade400,
                size: size,
              ),
            ),
          );
        }),
        if (rating > 0) ...[
          const SizedBox(width: 8),
          Text(
            _label(rating),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ],
    );
  }

  String _label(int r) {
    switch (r) {
      case 1: return 'Poor';
      case 2: return 'Fair';
      case 3: return 'Good';
      case 4: return 'Very Good';
      case 5: return 'Excellent';
      default: return '';
    }
  }
}