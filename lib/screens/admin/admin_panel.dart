

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  // ── Dashboard stats ────────────────────────────────────────────────
  Map<String, int> _stats = {
    'users': 0,
    'products': 0,
    'orders': 0,
    'pending': 0,
    'revenue': 0,
    'banned': 0,
  };
  bool _statsLoading = true;

  // ── Search / filter state ──────────────────────────────────────────
  String _userSearch = '';
  String _productSearch = '';
  String _orderStatusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':       return Colors.orange;
      case 'accepted':      return Colors.blue;
      case 'shipped':       return Colors.purple;
      case 'out_for_delivery': return Colors.indigo;
      case 'completed':     return Colors.green;
      case 'cancelled':     return Colors.red;
      default:              return Colors.grey;
    }
  }

  final NumberFormat _currency =
  NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 0);

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final diff = DateTime.now().difference(d.toLocal());
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  // ── Data loaders ───────────────────────────────────────────────────

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final results = await Future.wait([
        _supabase.from('profiles').count(),
        _supabase.from('products').count(),
        _supabase.from('orders').count(),
        _supabase.from('orders').count().eq('status', 'pending'),
        _supabase.from('profiles').count().eq('is_banned', true),
      ]);

      // Revenue: sum of completed orders
      // OPTIMIZED: Select only total_amount
      final revenueData = await _supabase
          .from('orders')
          .select('total_amount')
          .eq('status', 'completed');

      int totalRevenue = 0;
      for (final row in revenueData as List) {
        totalRevenue +=
            (num.tryParse(row['total_amount'].toString()) ?? 0).toInt();
      }

      if (mounted) {
        setState(() {
          _stats = {
            'users':    results[0],
            'products': results[1],
            'orders':   results[2],
            'pending':  results[3],
            'revenue':  totalRevenue,
            'banned':   results[4],
          };
          _statsLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Stats error: $e');
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchUsers() async {
    // OPTIMIZED: Select only needed columns and added limit
    final data = await _supabase
        .from('profiles')
        .select('id, full_name, avatar_url, phone, address, is_admin, is_banned, is_verified')
        .order('full_name')
        .limit(100); 
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> _fetchProducts() async {
    // OPTIMIZED: Select only needed columns and added limit
    final data = await _supabase
        .from('products')
        .select('id, productName, price, imageUrl, sellerName, category, total_quantity, created_at, description')
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> _fetchOrders() async {
    // OPTIMIZED: Select specific columns instead of '*'
    var query = _supabase
        .from('orders')
        .select('id, status, total_amount, created_at, payment_method, delivery_address, items')
        .order('created_at', ascending: false)
        .limit(100);
    final data = await query;
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> _fetchRecentActivity() async {
    // OPTIMIZED: Already selecting specific columns
    final orders = await _supabase
        .from('orders')
        .select('id, status, total_amount, created_at, items')
        .order('created_at', ascending: false)
        .limit(20);
    return List<Map<String, dynamic>>.from(orders);
  }

  // ── Actions ────────────────────────────────────────────────────────

  Future<void> _deleteProduct(int id, String name) async {
    final ok = await _confirmDialog(
      'Delete Product',
      'Permanently delete "$name"? This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: Colors.red,
    );
    if (!ok) return;
    try {
      await _supabase.from('products').delete().eq('id', id);
      _showSnack('Product deleted.');
      setState(() {});
    } catch (e) {
      _showSnack('Error: $e', error: true);
    }
  }

  Future<void> _toggleBan(
      String userId, String name, bool currentBan) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (userId == currentUserId) {
      _showSnack('You cannot ban yourself!', error: true);
      return;
    }
    final action = currentBan ? 'Unban' : 'Ban';
    final ok = await _confirmDialog(
      '$action User',
      '$action "$name"?\n\n${currentBan ? 'They will regain access.' : 'They will be blocked from the app.'}',
      confirmLabel: action,
      confirmColor: currentBan ? Colors.green : Colors.red,
    );
    if (!ok) return;
    try {
      await _supabase
          .from('profiles')
          .update({'is_banned': !currentBan})
          .eq('id', userId);
      _showSnack('User ${currentBan ? "unbanned" : "banned"}.');
      setState(() {});
    } catch (e) {
      _showSnack('Error: $e', error: true);
    }
  }

  Future<void> _toggleVerify(
      String userId, String name, bool currentVerify) async {
    final action = currentVerify ? 'Unverify' : 'Verify';
    final ok = await _confirmDialog(
      '$action User',
      '$action seller "$name"?',
      confirmLabel: action,
      confirmColor: currentVerify ? Colors.orange : Colors.blue,
    );
    if (!ok) return;
    try {
      await _supabase
          .from('profiles')
          .update({'is_verified': !currentVerify})
          .eq('id', userId);
      _showSnack('User ${currentVerify ? "unverified" : "verified"}.');
      setState(() {});
    } catch (e) {
      _showSnack('Error: $e', error: true);
    }
  }

  Future<void> _toggleAdmin(
      String userId, String name, bool currentAdmin) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (userId == currentUserId) {
      _showSnack('You cannot change your own admin status!', error: true);
      return;
    }
    final action = currentAdmin ? 'Remove admin from' : 'Make admin';
    final ok = await _confirmDialog(
      'Change Admin Role',
      '$action "$name"?',
      confirmLabel: action,
      confirmColor: currentAdmin ? Colors.red : Colors.purple,
    );
    if (!ok) return;
    try {
      await _supabase
          .from('profiles')
          .update({'is_admin': !currentAdmin})
          .eq('id', userId);
      _showSnack(
          currentAdmin ? 'Admin role removed.' : 'Admin role granted.');
      setState(() {});
    } catch (e) {
      _showSnack('Error: $e', error: true);
    }
  }

  Future<void> _updateOrderStatus(dynamic orderId, String status) async {
    try {
      await _supabase
          .from('orders')
          .update({'status': status})
          .eq('id', orderId);
      _showSnack('Order updated to $status.');
      setState(() {});
    } catch (e) {
      _showSnack('Error: $e', error: true);
    }
  }

  Future<void> _deleteOrder(dynamic orderId) async {
    final ok = await _confirmDialog(
      'Delete Order',
      'Permanently delete order #$orderId?',
      confirmLabel: 'Delete',
      confirmColor: Colors.red,
    );
    if (!ok) return;
    try {
      await _supabase.from('orders').delete().eq('id', orderId);
      _showSnack('Order deleted.');
      setState(() {});
    } catch (e) {
      _showSnack('Error: $e', error: true);
    }
  }

  Future<void> _broadcastNotification(
      String title, String message, String type) async {
    try {
      final users = await _supabase.from('profiles').select('id');
      final batch = (users as List)
          .map((u) => {
        'user_id': u['id'],
        'title': title,
        'message': message,
        'type': type,
        'is_read': false,
      })
          .toList();
      // Insert in chunks of 50
      for (int i = 0; i < batch.length; i += 50) {
        final chunk = batch.sublist(
            i, i + 50 > batch.length ? batch.length : i + 50);
        await _supabase.from('notifications').insert(chunk);
      }
      _showSnack('Broadcast sent to ${batch.length} users.');
    } catch (e) {
      _showSnack('Error: $e', error: true);
    }
  }

  Future<void> _editProductDialog(Map<String, dynamic> product) async {
    final nameCtrl =
    TextEditingController(text: product['productName'] ?? '');
    final priceCtrl =
    TextEditingController(text: product['price']?.toString() ?? '');
    final descCtrl =
    TextEditingController(text: product['description'] ?? '');
    final qtyCtrl = TextEditingController(
        text: product['total_quantity']?.toString() ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Product',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(nameCtrl, 'Product Name', Icons.inventory_2),
              const SizedBox(height: 12),
              _dialogField(priceCtrl, 'Price (Rs.)', Icons.currency_rupee,
                  numeric: true),
              const SizedBox(height: 12),
              _dialogField(qtyCtrl, 'Quantity', Icons.scale, numeric: true),
              const SizedBox(height: 12),
              _dialogField(descCtrl, 'Description', Icons.description,
                  maxLines: 3),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    try {
      await _supabase.from('products').update({
        'productName': nameCtrl.text.trim(),
        'price': double.tryParse(priceCtrl.text) ?? product['price'],
        'description': descCtrl.text.trim(),
        'total_quantity':
        double.tryParse(qtyCtrl.text) ?? product['total_quantity'],
      }).eq('id', product['id']);
      _showSnack('Product updated.');
      setState(() {});
    } catch (e) {
      _showSnack('Error: $e', error: true);
    }
  }

  // ── UI helpers ─────────────────────────────────────────────────────

  TextField _dialogField(
      TextEditingController ctrl,
      String label,
      IconData icon, {
        bool numeric = false,
        int maxLines = 1,
      }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType:
      numeric ? TextInputType.number : TextInputType.multiline,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Future<bool> _confirmDialog(
      String title,
      String content, {
        required String confirmLabel,
        required Color confirmColor,
      }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: TextStyle(
                    color: confirmColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ──────────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Admin Control Panel',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              _loadStats();
              setState(() {});
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard, size: 18), text: 'Dashboard'),
            Tab(icon: Icon(Icons.receipt_long, size: 18), text: 'Orders'),
            Tab(icon: Icon(Icons.inventory, size: 18), text: 'Products'),
            Tab(icon: Icon(Icons.people, size: 18), text: 'Users'),
            Tab(icon: Icon(Icons.campaign, size: 18), text: 'Broadcast'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDashboardTab(),
          _buildOrdersTab(),
          _buildProductsTab(),
          _buildUsersTab(),
          _buildBroadcastTab(),
        ],
      ),
    );
  }

  // ── TAB 1: Dashboard ───────────────────────────────────────────────

  Widget _buildDashboardTab() {
    return RefreshIndicator(
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Overview'),
            const SizedBox(height: 12),
            _statsLoading
                ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: Colors.red),
                ))
                : _buildStatsGrid(),
            const SizedBox(height: 24),
            _sectionTitle('Recent Orders'),
            const SizedBox(height: 12),
            _buildRecentOrdersList(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final cards = [
      _StatCard('Total Users', _stats['users']!, Icons.people_alt,
          Colors.blue, null),
      _StatCard('Total Products', _stats['products']!, Icons.storefront,
          Colors.green, null),
      _StatCard('Total Orders', _stats['orders']!, Icons.receipt,
          Colors.purple, null),
      _StatCard('Pending Orders', _stats['pending']!, Icons.hourglass_top,
          Colors.orange, null),
      _StatCard('Revenue', _stats['revenue']!,
          Icons.currency_rupee, Colors.teal, 'Rs. '),
      _StatCard('Banned Users', _stats['banned']!, Icons.block,
          Colors.red, null),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemCount: cards.length,
      itemBuilder: (context, i) => _buildStatCard(cards[i]),
    );
  }

  Widget _buildStatCard(_StatCard s) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: s.color.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(s.icon, color: s.color, size: 26),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: s.color.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: Icon(s.icon, color: s.color, size: 14),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.prefix != null
                    ? '${s.prefix}${NumberFormat('#,##0').format(s.value)}'
                    : s.value.toString(),
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: s.color),
              ),
              Text(s.label,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentOrdersList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchRecentActivity(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.red));
        }
        final orders = snapshot.data!;
        if (orders.isEmpty) {
          return _emptyState('No recent orders', Icons.receipt_long);
        }
        return Column(
          children: orders
              .map((o) => _buildMiniOrderCard(o))
              .toList(),
        );
      },
    );
  }

  Widget _buildMiniOrderCard(Map<String, dynamic> order) {
    final status = order['status'] ?? 'pending';
    final color = _statusColor(status);
    final items = order['items'] as List<dynamic>? ?? [];
    final firstItem = items.isNotEmpty
        ? (items.first['product_name'] ?? 'Item')
        : 'Order';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1), shape: BoxShape.circle),
            child:
            Icon(Icons.shopping_bag_outlined, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order #${order['id']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                Text(firstItem,
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(status.toUpperCase(),
                    style: TextStyle(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 4),
              Text(
                _currency.format(
                    num.tryParse(order['total_amount'].toString()) ?? 0),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── TAB 2: Orders ──────────────────────────────────────────────────

  Widget _buildOrdersTab() {
    return Column(
      children: [
        // Status filter chips
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                'all', 'pending', 'accepted', 'shipped',
                'out_for_delivery', 'completed', 'cancelled'
              ]
                  .map((s) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                      s == 'all' ? 'All' : s.replaceAll('_', ' ').toUpperCase(),
                      style: const TextStyle(fontSize: 11)),
                  selected: _orderStatusFilter == s,
                  selectedColor: s == 'all'
                      ? Colors.red.shade100
                      : _statusColor(s).withOpacity(0.2),
                  onSelected: (_) =>
                      setState(() => _orderStatusFilter = s),
                ),
              ))
                  .toList(),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchOrders(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: Colors.red));
                }
                var orders = snapshot.data!;
                if (_orderStatusFilter != 'all') {
                  orders = orders
                      .where((o) => o['status'] == _orderStatusFilter)
                      .toList();
                }
                if (orders.isEmpty) {
                  return _emptyState('No orders found', Icons.receipt_long);
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length,
                  itemBuilder: (context, i) =>
                      _buildOrderCard(orders[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status'] ?? 'pending';
    final color = _statusColor(status);
    final items = order['items'] as List<dynamic>? ?? [];
    final totalAmount =
        num.tryParse(order['total_amount'].toString()) ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showOrderDetailsBottomSheet(order),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Order #${order['id']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withOpacity(0.4))),
                    child: Text(status.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Items summary
              ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record,
                        size: 6, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${item['product_name'] ?? 'Item'} × ${item['quantity']}',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.access_time,
                          size: 13, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(_timeAgo(order['created_at']),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  Text(
                    _currency.format(totalAmount),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Quick action row
              Row(
                children: [
                  _quickOrderBtn(
                      'Details', Icons.info_outline, Colors.blue,
                          () => _showOrderDetailsBottomSheet(order)),
                  const SizedBox(width: 8),
                  if (status == 'pending')
                    _quickOrderBtn('Accept', Icons.check_circle_outline,
                        Colors.green,
                            () => _updateOrderStatus(order['id'], 'accepted')),
                  if (status == 'accepted')
                    _quickOrderBtn('Ship', Icons.local_shipping_outlined,
                        Colors.purple,
                            () => _updateOrderStatus(order['id'], 'shipped')),
                  if (status == 'shipped')
                    _quickOrderBtn(
                        'Out for Del.',
                        Icons.delivery_dining,
                        Colors.indigo,
                            () => _updateOrderStatus(
                            order['id'], 'out_for_delivery')),
                  if (status == 'out_for_delivery')
                    _quickOrderBtn('Complete', Icons.done_all, Colors.green,
                            () => _updateOrderStatus(order['id'], 'completed')),
                  if (status != 'completed' && status != 'cancelled')
                    _quickOrderBtn('Cancel', Icons.cancel_outlined,
                        Colors.red,
                            () => _updateOrderStatus(order['id'], 'cancelled')),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 20),
                    onPressed: () => _deleteOrder(order['id']),
                    tooltip: 'Delete order',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickOrderBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _showOrderDetailsBottomSheet(Map<String, dynamic> order) {
    final status = order['status'] ?? 'pending';
    final color = _statusColor(status);
    final items = order['items'] as List<dynamic>? ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Order #${order['id']}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(status.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _detailRow(Icons.calendar_today, 'Created',
                  _timeAgo(order['created_at'])),
              _detailRow(Icons.payment, 'Payment',
                  order['payment_method'] ?? 'N/A'),
              _detailRow(Icons.location_on, 'Delivery',
                  order['delivery_address'] ?? 'N/A'),
              const Divider(height: 24),
              const Text('Items',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.eco,
                          color: Colors.green, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['product_name'] ?? 'Item',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          Text(
                              'Qty: ${item['quantity']}  ×  Rs. ${item['price']}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Text(
                      _currency.format(
                          (num.tryParse(item['price'].toString()) ?? 0) *
                              (num.tryParse(
                                  item['quantity'].toString()) ??
                                  0)),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    _currency.format(
                        num.tryParse(order['total_amount'].toString()) ??
                            0),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Update Status',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  'pending', 'accepted', 'shipped',
                  'out_for_delivery', 'completed', 'cancelled'
                ]
                    .map((s) => ChoiceChip(
                  label: Text(s.replaceAll('_', ' '),
                      style: const TextStyle(fontSize: 12)),
                  selected: status == s,
                  selectedColor:
                  _statusColor(s).withOpacity(0.2),
                  onSelected: (_) {
                    Navigator.pop(ctx);
                    _updateOrderStatus(order['id'], s);
                  },
                ))
                    .toList(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  // ── TAB 3: Products ────────────────────────────────────────────────

  Widget _buildProductsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search products…',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (v) => setState(() => _productSearch = v),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchProducts(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: Colors.red));
                }
                var products = snapshot.data!;
                if (_productSearch.isNotEmpty) {
                  final q = _productSearch.toLowerCase();
                  products = products
                      .where((p) =>
                  (p['productName'] ?? '')
                      .toString()
                      .toLowerCase()
                      .contains(q) ||
                      (p['sellerName'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(q))
                      .toList();
                }
                if (products.isEmpty) {
                  return _emptyState(
                      'No products found', Icons.inventory_2);
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  itemCount: products.length,
                  itemBuilder: (ctx, i) =>
                      _buildProductCard(products[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(Map<String, dynamic> p) {
    final imageUrl = p['imageUrl']?.toString() ?? '';
    final name = p['productName'] ?? 'No name';
    final price = num.tryParse(p['price'].toString()) ?? 0;
    final qty = p['total_quantity'] ?? 0;
    final seller = p['sellerName'] ?? 'Unknown';
    final category = p['category'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                imageUrl: imageUrl,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorWidget: (c, u, e) =>
                    _productPlaceholder(),
              )
                  : _productPlaceholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(seller,
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (category.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(category,
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.green)),
                        ),
                      const SizedBox(width: 6),
                      Text('Rs. ${_currency.format(price)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.green)),
                    ],
                  ),
                  Text('Stock: $qty',
                      style: TextStyle(
                          fontSize: 11,
                          color: (num.tryParse(qty.toString()) ?? 0) < 5
                              ? Colors.red
                              : Colors.grey.shade500)),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      color: Colors.blue, size: 20),
                  onPressed: () => _editProductDialog(p),
                  tooltip: 'Edit',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(height: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                  onPressed: () => _deleteProduct(p['id'], name),
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _productPlaceholder() {
    return Container(
      width: 64,
      height: 64,
      color: Colors.green.shade50,
      child: const Icon(Icons.eco, color: Colors.green, size: 32),
    );
  }

  // ── TAB 4: Users ───────────────────────────────────────────────────

  Widget _buildUsersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search users…',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (v) => setState(() => _userSearch = v),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchUsers(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: Colors.red));
                }
                var users = snapshot.data!;
                if (_userSearch.isNotEmpty) {
                  final q = _userSearch.toLowerCase();
                  users = users
                      .where((u) =>
                  (u['full_name'] ?? '')
                      .toString()
                      .toLowerCase()
                      .contains(q) ||
                      (u['phone'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(q))
                      .toList();
                }
                if (users.isEmpty) {
                  return _emptyState('No users found', Icons.people);
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  itemCount: users.length,
                  itemBuilder: (ctx, i) => _buildUserCard(users[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserCard(Map<String, dynamic> u) {
    final bool isAdmin = u['is_admin'] ?? false;
    final bool isBanned = u['is_banned'] ?? false;
    final bool isVerified = u['is_verified'] ?? false;
    final String userId = u['id'];
    final String name = u['full_name'] ?? 'No Name';
    final String avatarUrl = u['avatar_url'] ?? '';
    final String phone = u['phone'] ?? 'No phone';
    final String address = u['address'] ?? '';
    final currentUserId = _supabase.auth.currentUser?.id;
    final isCurrentUser = userId == currentUserId;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.green.shade50,
                  backgroundImage: avatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? Text(name[0].toUpperCase(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(name,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    decoration: isBanned
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: isBanned
                                        ? Colors.grey
                                        : Colors.black)),
                          ),
                          if (isVerified)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.verified,
                                  color: Colors.blue, size: 16),
                            ),
                          if (isAdmin)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.purple.withOpacity(0.1),
                                  borderRadius:
                                  BorderRadius.circular(6)),
                              child: const Text('ADMIN',
                                  style: TextStyle(
                                      color: Colors.purple,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold)),
                            ),
                          if (isBanned)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius:
                                  BorderRadius.circular(6)),
                              child: const Text('BANNED',
                                  style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold)),
                            ),
                          if (isCurrentUser)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius:
                                  BorderRadius.circular(6)),
                              child: const Text('YOU',
                                  style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(phone,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12)),
                      if (address.isNotEmpty)
                        Text(address,
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Action buttons row
            Row(
              children: [
                _userActionBtn(
                  isVerified ? 'Unverify' : 'Verify',
                  isVerified ? Icons.verified_outlined : Icons.verified,
                  isVerified ? Colors.orange : Colors.blue,
                      () => _toggleVerify(userId, name, isVerified),
                ),
                const SizedBox(width: 8),
                if (!isCurrentUser) ...[
                  _userActionBtn(
                    isBanned ? 'Unban' : 'Ban',
                    isBanned ? Icons.lock_open : Icons.block,
                    isBanned ? Colors.green : Colors.red,
                        () => _toggleBan(userId, name, isBanned),
                  ),
                  const SizedBox(width: 8),
                  _userActionBtn(
                    isAdmin ? 'Remove Admin' : 'Make Admin',
                    Icons.admin_panel_settings,
                    isAdmin ? Colors.red : Colors.purple,
                        () => _toggleAdmin(userId, name, isAdmin),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _userActionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── TAB 5: Broadcast ───────────────────────────────────────────────

  Widget _buildBroadcastTab() {
    final titleCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    String selectedType = 'general';

    final types = ['general', 'order', 'delivery', 'selling', 'availability'];

    return StatefulBuilder(
      builder: (context, setLocal) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200)),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange.shade700),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'This will send a notification to ALL users in the system.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle('Notification Type'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: types
                  .map((t) => ChoiceChip(
                label: Text(t.toUpperCase(),
                    style: const TextStyle(fontSize: 11)),
                selected: selectedType == t,
                selectedColor: Colors.red.shade100,
                onSelected: (_) =>
                    setLocal(() => selectedType = t),
              ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            _sectionTitle('Message'),
            const SizedBox(height: 10),
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: 'Title',
                prefixIcon: const Icon(Icons.title),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: msgCtrl,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'Message',
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 60),
                    child: Icon(Icons.message)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('Send to All Users',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  final msg = msgCtrl.text.trim();
                  if (title.isEmpty || msg.isEmpty) {
                    _showSnack('Please fill in title and message.',
                        error: true);
                    return;
                  }
                  final ok = await _confirmDialog(
                    'Send Broadcast',
                    'Send "$title" to all users?',
                    confirmLabel: 'Send',
                    confirmColor: Colors.red,
                  );
                  if (!ok) return;
                  await _broadcastNotification(title, msg, selectedType);
                  titleCtrl.clear();
                  msgCtrl.clear();
                },
              ),
            ),
            const SizedBox(height: 32),
            _sectionTitle('Recent Notifications'),
            const SizedBox(height: 12),
            _buildRecentNotifications(),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentNotifications() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _supabase
          .from('notifications')
          .select('id, title, message, created_at')
          .order('created_at', ascending: false)
          .limit(10),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.red));
        }
        final notifs = snapshot.data!;
        if (notifs.isEmpty) {
          return _emptyState('No notifications yet', Icons.notifications_off);
        }
        return Column(
          children: notifs
              .map((n) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade100)),
            child: Row(
              children: [
                const Icon(Icons.notifications_outlined,
                    size: 18, color: Colors.grey),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(n['title'] ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      Text(n['message'] ?? '',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Text(_timeAgo(n['created_at']),
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
              ],
            ),
          ))
              .toList(),
        );
      },
    );
  }

  // ── Shared widgets ─────────────────────────────────────────────────

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.3));
  }

  Widget _emptyState(String msg, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(msg,
              style: TextStyle(
                  fontSize: 16, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

// ── Data model for stat cards ────────────────────────────────────────

class _StatCard {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final String? prefix;

  const _StatCard(
      this.label, this.value, this.icon, this.color, this.prefix);
}
