// lib/screens/product_profile.dart

import 'package:flutter/material.dart';
import 'package:untitled1/providers/cart_provider.dart';
import 'package:provider/provider.dart';
import 'farmer_profile_page.dart';
import 'main_screen/chat_page.dart';
import 'main_screen/cart_screen.dart';
import '../widgets/product_rating.dart';
import '../widgets/supabase_image.dart';
import '../widgets/user_avatar.dart';
import '../widgets/rating_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductProfilePage extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductProfilePage({super.key, required this.product});

  @override
  State<ProductProfilePage> createState() => _ProductProfilePageState();
}

class _ProductProfilePageState extends State<ProductProfilePage> {
  late Map<String, dynamic> _currentProduct;
  int _quantity = 1;
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isSellerVerified = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Start with the data we have
    _currentProduct = Map<String, dynamic>.from(widget.product);
    
    // If we already have stock and description, we can skip the initial full-screen loader
    final dynamic qty = _currentProduct['total_quantity'];
    if (qty != null && _currentProduct.containsKey('description')) {
      _isLoading = false;
    }
    
    _loadData();
  }

  Future<void> _loadData() async {
    final dynamic rawId = _currentProduct['id'];
    int? productId;
    if (rawId is num) {
      productId = rawId.toInt();
    } else if (rawId != null) {
      productId = int.tryParse(rawId.toString()) ?? num.tryParse(rawId.toString())?.toInt();
    }

    if (productId == null || productId == 0) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await _supabase
          .from('products')
          .select('*, profiles:seller_id(is_verified)')
          .eq('id', productId)
          .maybeSingle();
      
      if (mounted) {
        if (response != null) {
          setState(() {
            // Update everything with the live database response
            _currentProduct = {
              ..._currentProduct,
              ...Map<String, dynamic>.from(response),
            };
            if (response['profiles'] != null) {
              _isSellerVerified = response['profiles']['is_verified'] ?? false;
            }
          });
        }
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching live data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _daysAgo() {
    final createdAtString = _currentProduct['created_at'] as String?;
    if (createdAtString == null) return 'Unknown';
    final createdAt = DateTime.parse(createdAtString);
    final difference = DateTime.now().difference(createdAt);
    if (difference.inDays > 1) return '${difference.inDays} days ago';
    if (difference.inDays == 1) return '1 day ago';
    return 'Today';
  }

  @override
  Widget build(BuildContext context) {
    final dynamic rawId = _currentProduct['id'];
    final int productId = rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '0') ?? 0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: Colors.green,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProductHeader(),
                    const SizedBox(height: 24),
                    _buildActionButtons(),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Product Details'),
                    _buildProductDetails(),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Shipping Details'),
                    _buildShippingDetails(),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Product Reviews'),
                    _ProductReviewsSection(
                      productId: productId,
                      sellerId: _currentProduct['seller_id'] as String? ?? '',
                    ),
                    const SizedBox(height: 24),
                    _buildMessageButton(),
                    const SizedBox(height: 16),
                    _buildShowProfileButton(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildProductHeader() {
    final productName = (_currentProduct['productName'] as String?)?.trim() ?? 'Unnamed Product';
    final imageUrl = (_currentProduct['imageUrl'] as String?)?.trim() ?? '';
    final priceValue = _currentProduct['price'];
    final dynamic rawId = _currentProduct['id'];
    final int productId = rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '0') ?? 0;
    final category = _currentProduct['category'] as String? ?? 'Others';
    
    // Robust parsing of quantity - handle double/num correctly
    final dynamic rawQty = _currentProduct['total_quantity'];
    num totalQty = 0;
    if (rawQty is num) {
      totalQty = rawQty;
    } else if (rawQty != null) {
      totalQty = num.tryParse(rawQty.toString()) ?? 0;
    }

    double price = 0.0;
    if (priceValue is num && priceValue > 0) price = priceValue.toDouble();

    String imagePath = imageUrl;
    if (imageUrl.contains('product_images/')) {
      imagePath = imageUrl.split('product_images/').last;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: imagePath.isNotEmpty
              ? SupabaseImage(
            imagePath: imagePath,
            height: 80,
            width: 80,
            fit: BoxFit.cover,
            bucket: 'product_images',
          )
              : const Icon(Icons.image_not_supported, size: 80),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(productName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              _buildCategoryBadge(category),
              const SizedBox(height: 4),
              Text(
                'In Stock: ${totalQty.toStringAsFixed(totalQty % 1 == 0 ? 0 : 1)}',
                style: TextStyle(
                    color: totalQty > 0 ? Colors.blue : Colors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ProductRating(productId: productId, iconSize: 16, fontSize: 13),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Rs.${price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.green, size: 24),
                  onPressed: () {
                    if (_quantity > 1) setState(() => _quantity--);
                  },
                ),
                Text('$_quantity', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  icon: const Icon(Icons.add_circle, color: Colors.green, size: 24),
                  onPressed: () {
                    if (_quantity < totalQty) {
                      setState(() => _quantity++);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot exceed available stock')));
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryBadge(String category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Text(category, style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildActionButtons() {
    final cart = Provider.of<CartProvider>(context, listen: false);
    final dynamic rawId = _currentProduct['id'];
    final int productId = rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '0') ?? 0;
    final sellerId = _currentProduct['seller_id'] as String? ?? '';
    final currentUserId = _supabase.auth.currentUser?.id;

    if (productId == 0 || currentUserId == sellerId) return const SizedBox.shrink();

    final isAdded = cart.isItemInCart(productId);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              cart.toggleCartStatus(productId, _currentProduct['productName'] ?? '', (_currentProduct['price'] as num?)?.toDouble() ?? 0.0, _currentProduct['imageUrl'] ?? '', sellerId);
              setState(() {});
            },
            style: OutlinedButton.styleFrom(
              backgroundColor: isAdded ? Colors.red.shade50 : Colors.white,
              side: BorderSide(color: isAdded ? Colors.red : Colors.green),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(isAdded ? 'REMOVE' : 'ADD TO DOOKO', style: TextStyle(color: isAdded ? Colors.red : Colors.green, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => CartScreen(directItem: CartItem(id: productId, name: _currentProduct['productName'] ?? '', price: (_currentProduct['price'] as num?)?.toDouble() ?? 0.0, image: _currentProduct['imageUrl'] ?? '', quantity: _quantity, sellerId: sellerId))));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('BUY NOW', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildProductDetails() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(_currentProduct['productName'] ?? 'Unnamed', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                Text(_daysAgo(), style: const TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            Text(_currentProduct['description'] ?? 'No description.'),
          ],
        ),
      ),
    );
  }

  Widget _buildShippingDetails() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_currentProduct['sellerName'] ?? 'Unknown Seller', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (_isSellerVerified) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified, color: Colors.green, size: 18),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text('Farmer\'s Location: ${_currentProduct['location'] ?? 'Unknown'}'),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageButton() {
    return OutlinedButton(
      onPressed: () {
        if (_currentProduct['seller_id'] != null && _currentProduct['sellerName'] != null) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(receiverId: _currentProduct['seller_id'], farmerName: _currentProduct['sellerName'])));
        }
      },
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.green),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text('Message', style: TextStyle(color: Colors.green, fontSize: 16)),
    );
  }

  Widget _buildShowProfileButton() {
    return OutlinedButton(
      onPressed: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => FarmerProfilePage(farmerId: _currentProduct['seller_id'] ?? '', farmerName: _currentProduct['sellerName'] ?? 'Unknown')));
      },
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.green),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text('Show Farmer\'s Profile', style: TextStyle(color: Colors.green, fontSize: 16)),
    );
  }
}

class _ProductReviewsSection extends StatefulWidget {
  final int productId;
  final String sellerId;

  const _ProductReviewsSection({required this.productId, required this.sellerId});

  @override
  State<_ProductReviewsSection> createState() => _ProductReviewsSectionState();
}

class _ProductReviewsSectionState extends State<_ProductReviewsSection> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  bool _hasError = false;
  int? _activeStarFilter;

  List<Map<String, dynamic>> get _filteredReviews {
    if (_activeStarFilter == null) return _reviews;
    return _reviews.where((r) => (r['rating'] as num).toInt() == _activeStarFilter).toList();
  }

  @override
  void initState() {
    super.initState();
    if (widget.productId > 0) _fetchReviews();
  }

  Future<void> _fetchReviews() async {
    setState(() { _loading = true; _hasError = false; });
    try {
      final reviewData = await _supabase.from('product_reviews').select('id, product_id, user_id, rating, comment, created_at').eq('product_id', widget.productId).order('created_at', ascending: false);
      final reviews = List<Map<String, dynamic>>.from(reviewData as List);
      if (reviews.isEmpty) {
        if (mounted) setState(() { _reviews = []; _loading = false; });
        return;
      }
      final userIds = reviews.map((r) => r['user_id'] as String).toSet().toList();
      final profileData = await _supabase.from('profiles').select('id, full_name, avatar_url').inFilter('id', userIds);
      final profiles = { for (var p in (profileData as List)) p['id']: p };
      final merged = reviews.map((r) {
        final profile = profiles[r['user_id']] as Map<String, dynamic>?;
        return { ...r, 'profiles': profile };
      }).toList();
      if (mounted) setState(() { _reviews = merged; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.productId <= 0) return const Padding(padding: EdgeInsets.all(16), child: Text('No reviews available.'));
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId != null && currentUserId == widget.sellerId) {
      return Container(margin: const EdgeInsets.symmetric(vertical: 8), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)), child: Row(children: [Icon(Icons.info_outline, color: Colors.grey.shade500, size: 18), const SizedBox(width: 10), const Expanded(child: Text('You cannot review your own product.', style: TextStyle(color: Colors.grey)))]));
    }
    if (_loading) return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.green)));
    if (_hasError) return Padding(padding: const EdgeInsets.all(16), child: Column(children: [const Text('Could not load reviews.', style: TextStyle(color: Colors.grey)), const SizedBox(height: 8), TextButton.icon(onPressed: _fetchReviews, icon: const Icon(Icons.refresh, color: Colors.green), label: const Text('Retry', style: TextStyle(color: Colors.green)))]));
    if (_reviews.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('No reviews yet. Be the first to buy and rate!', style: TextStyle(color: Colors.grey)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [RatingSummary(reviews: _reviews, activeStarFilter: _activeStarFilter, onStarFilter: (star) => setState(() => _activeStarFilter = star)), if (_activeStarFilter != null) Padding(padding: const EdgeInsets.only(top: 8), child: Chip(label: Text('$_activeStarFilter★ only'), deleteIcon: const Icon(Icons.close, size: 16), onDeleted: () => setState(() => _activeStarFilter = null), backgroundColor: Colors.green.withOpacity(0.1), side: BorderSide(color: Colors.green.shade200))), const SizedBox(height: 24), if (_filteredReviews.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('No $_activeStarFilter-star reviews yet.', style: const TextStyle(color: Colors.grey))) else ListView.separated(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _filteredReviews.length, separatorBuilder: (_, __) => const Divider(height: 32), itemBuilder: (_, index) => _buildReviewItem(_filteredReviews[index]))]);
  }

  Widget _buildReviewItem(Map<String, dynamic> review) {
    final profile = review['profiles'] as Map<String, dynamic>?;
    final reviewerName = profile?['full_name'] ?? 'Verified Buyer';
    final avatarUrl = profile?['avatar_url'] ?? '';
    final rating = (review['rating'] as num).toInt();
    final comment = review['comment']?.toString() ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [UserAvatar(avatarUrl: avatarUrl, name: reviewerName, radius: 18), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(reviewerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), Text(_formatReviewDate(review['created_at']), style: TextStyle(fontSize: 11, color: Colors.grey[600]))])), Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) => Icon(i < rating ? Icons.star_rounded : Icons.star_outline_rounded, color: Colors.amber, size: 14)))]), if (comment.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10, left: 48), child: Text(comment, style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.3)))]);
  }

  String _formatReviewDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      final diff = DateTime.now().difference(date);
      if (diff.inDays >= 1) return '${diff.inDays}d ago';
      if (diff.inHours >= 1) return '${diff.inHours}h ago';
      if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
      return 'Just now';
    } catch (_) { return ''; }
  }
}
