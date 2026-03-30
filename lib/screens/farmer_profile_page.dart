// lib/screens/farmer_profile_page.dart


import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_screen/chat_page.dart';
import '../widgets/seller_rating.dart';
import '../widgets/user_avatar.dart';
import '../widgets/rating_summary.dart';

class FarmerProfilePage extends StatefulWidget {
  final String farmerId;
  final String farmerName;

  const FarmerProfilePage({
    super.key,
    required this.farmerId,
    required this.farmerName,
  });

  @override
  State<FarmerProfilePage> createState() => _FarmerProfilePageState();
}

class _FarmerProfilePageState extends State<FarmerProfilePage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();

  int _userSelectedRating = 0;
  List<Map<String, dynamic>> _comments = [];
  List<Map<String, dynamic>> _farmerProducts = [];
  Map<String, dynamic>? _farmerProfile;
  bool _isLoading = true;

  // ── NEW: star filter state ──────────────────────────────────────────
  int? _activeStarFilter;

  List<Map<String, dynamic>> get _filteredComments {
    if (_activeStarFilter == null) return _comments;
    return _comments
        .where((r) => (r['rating'] as num).toInt() == _activeStarFilter)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _fetchFarmerProfile(),
      _fetchFarmerReviews(),
      _fetchFarmerProducts(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchFarmerProfile() async {
    try {
      // OPTIMIZED: Select only needed columns
      final data = await _supabase
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', widget.farmerId)
          .single();
      if (mounted) setState(() => _farmerProfile = data);
    } catch (e) {
      debugPrint('Error fetching farmer profile: $e');
    }
  }

  Future<void> _fetchFarmerProducts() async {
    try {
      // OPTIMIZED: Select only needed columns
      final data = await _supabase
          .from('products')
          .select('productName, price, imageUrl')
          .eq('sellerID', widget.farmerId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _farmerProducts = List<Map<String, dynamic>>.from(data as List);
        });
      }
    } catch (e) {
      debugPrint('Error fetching farmer products: $e');
    }
  }

  Future<void> _fetchFarmerReviews({bool updateController = true}) async {
    try {
      // Step 1: fetch reviews without join (farmer_reviews may have no FK to profiles)
      final reviewData = await _supabase
          .from('farmer_reviews')
          .select('id, farmer_id, user_id, rating, comment, created_at')
          .eq('farmer_id', widget.farmerId)
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> reviewList =
      List<Map<String, dynamic>>.from(reviewData as List);

      // Step 2: fetch profiles separately
      if (reviewList.isNotEmpty) {
        final userIds = reviewList.map((r) => r['user_id'] as String).toSet().toList();
        final profileData = await _supabase
            .from('profiles')
            .select('id, full_name, avatar_url')
            .inFilter('id', userIds);
        final profiles = { for (var p in (profileData as List)) p['id']: p };
        for (final r in reviewList) {
          r['profiles'] = profiles[r['user_id']];
        }
      }

      final currentUserId = _supabase.auth.currentUser?.id;
      int foundRating = 0;
      String foundComment = '';

      for (final review in reviewList) {
        if (currentUserId != null && review['user_id'] == currentUserId) {
          foundRating = review['rating'] as int;
          foundComment = review['comment'] ?? '';
        }
      }

      if (mounted) {
        setState(() {
          _userSelectedRating = foundRating;
          if (updateController) {
            // Only pre-fill the field on initial load or when editing
            _commentController.text = foundComment;
            _commentController.selection = TextSelection.fromPosition(
              TextPosition(offset: _commentController.text.length),
            );
          } else {
            // After a submit or delete — keep the field empty
            _commentController.clear();
          }
          _comments = reviewList;
        });
      }
    } catch (e) {
      debugPrint('Error fetching reviews: $e');
    }
  }

  // ── CHANGED: validation before submit ──────────────────────────────
  Future<void> _submitReview() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // Hard block — farmer cannot review themselves
    if (user.id == widget.farmerId) {
      _showSnack('You cannot review your own profile.', isError: true);
      return;
    }

    if (_userSelectedRating == 0) {
      _showSnack('Please select a star rating first.', isError: true);
      return;
    }

    final commentText = _commentController.text.trim();
    if (commentText.isNotEmpty && commentText.length < 5) {
      _showSnack('Comment must be at least 5 characters.', isError: true);
      return;
    }

    try {
      await _supabase.from('farmer_reviews').upsert(
        {
          'farmer_id': widget.farmerId,
          'user_id': user.id,
          'rating': _userSelectedRating,
          'comment': commentText,
        },
        onConflict: 'farmer_id,user_id',
      );

      // Clear the input field after posting — comment now lives in the review card only
      _commentController.clear();
      await _fetchFarmerReviews(updateController: false);

      if (mounted) {
        _showSnack('Review posted!');
        _commentFocusNode.unfocus();
      }
    } catch (e) {
      debugPrint('Error submitting review: $e');
      _showSnack('Failed to post review. Please try again.', isError: true);
    }
  }

  // ── CHANGED: added confirmation dialog before delete ───────────────
  Future<void> _deleteReview() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Review?'),
        content: const Text(
            'This will permanently remove your review. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase
          .from('farmer_reviews')
          .delete()
          .match({'farmer_id': widget.farmerId, 'user_id': userId});

      setState(() {
        _userSelectedRating = 0;
        _commentController.clear();
      });

      await _fetchFarmerReviews(updateController: false);

      if (mounted) _showSnack('Review deleted.');
    } catch (e) {
      debugPrint('Error deleting review: $e');
      _showSnack('Failed to delete review.', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
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
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: Colors.green))
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFarmerHeader(context),
            const SizedBox(height: 10),
            // ── CHANGED: inline star input replaces tappable row ──
            // Only consumers can rate — hide for the farmer themselves
            if (_supabase.auth.currentUser?.id != widget.farmerId)
              _buildInlineRatingInput(),
            const SizedBox(height: 20),
            _buildSalesStatsCard(_farmerProducts.length),
            const SizedBox(height: 20),
            _buildSectionTitle('Farmer\'s Products'),
            _farmerProducts.isEmpty
                ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No listings yet'),
              ),
            )
                : Column(
              children: _farmerProducts
                  .map((p) => _buildProductItem(
                p['productName'] ?? 'Unnamed',
                'Rs. ${p['price']}',
                p['imageUrl'] ?? '',
              ))
                  .toList(),
            ),
            const SizedBox(height: 32),
            const Text('Reviews',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            const SizedBox(height: 12),
            if (_comments.isNotEmpty) ...[
              // ── CHANGED: wire up star filter ──────────────────
              RatingSummary(
                reviews: _comments,
                activeStarFilter: _activeStarFilter,
                onStarFilter: (star) =>
                    setState(() => _activeStarFilter = star),
              ),
              if (_activeStarFilter != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Chip(
                    label: Text('$_activeStarFilter★ only'),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () =>
                        setState(() => _activeStarFilter = null),
                    backgroundColor:
                    Colors.green.withOpacity(0.1),
                    side: BorderSide(
                        color: Colors.green.shade200),
                  ),
                ),
              const SizedBox(height: 24),
            ],
            // Hide comment input for the farmer viewing their own profile
            if (_supabase.auth.currentUser?.id != widget.farmerId)
              _buildDescriptionInputBar(),
            const SizedBox(height: 24),
            _buildCommentsList(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── NEW: inline star input row ─────────────────────────────────────
  Widget _buildInlineRatingInput() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Row(
        children: [
          const Text(
            'Your Rating:',
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ...List.generate(5, (index) {
                  final starValue = index + 1;
                  return GestureDetector(
                    onTap: () => setState(() => _userSelectedRating = starValue),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(
                        index < _userSelectedRating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: Colors.orangeAccent,
                        size: 26,
                      ),
                    ),
                  );
                }),
                if (_userSelectedRating > 0) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() => _userSelectedRating = 0),
                    child: const Icon(Icons.close, size: 16, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              focusNode: _commentFocusNode,
              decoration: const InputDecoration(
                hintText: 'Write a public review...',
                border: InputBorder.none,
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.green),
            onPressed: _submitReview,
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsList() {
    final displayed = _filteredComments;

    if (displayed.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            _activeStarFilter != null
                ? 'No $_activeStarFilter-star reviews yet.'
                : 'No reviews yet. Be the first to rate!',
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final currentUserId = _supabase.auth.currentUser?.id;

    return Column(
      children: displayed.map((review) {
        final profile = review['profiles'] as Map<String, dynamic>?;
        final reviewerName = profile?['full_name'] ?? 'Verified User';
        final avatarUrl = profile?['avatar_url'] ?? '';
        final rating = review['rating'] as int;
        final isMyReview =
            currentUserId != null && review['user_id'] == currentUserId;

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(
                      avatarUrl: avatarUrl, name: reviewerName, radius: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(reviewerName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        Text(
                          _formatReviewDate(review['created_at']),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  // Star display
                  Row(
                    children: List.generate(
                      5,
                          (i) => Icon(
                        i < rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 14,
                        color: Colors.orangeAccent,
                      ),
                    ),
                  ),
                  // Edit / Delete menu (own review only)
                  if (isMyReview)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          size: 20, color: Colors.grey),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      onSelected: (value) {
                        if (value == 'edit') {
                          setState(() {
                            _userSelectedRating = review['rating'] as int;
                            _commentController.text =
                                review['comment'] ?? '';
                            _commentController.selection =
                                TextSelection.fromPosition(TextPosition(
                                    offset: _commentController.text.length));
                          });
                          _commentFocusNode.requestFocus();
                        } else if (value == 'delete') {
                          _deleteReview();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                ],
              ),
              if ((review['comment'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Text(
                    review['comment'],
                    style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.4),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Divider(indent: 48, color: Colors.black12),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFarmerHeader(BuildContext context) {
    final avatarUrl = _farmerProfile?['avatar_url'] ?? '';
    final name = _farmerProfile?['full_name'] ?? widget.farmerName;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        children: [
          UserAvatar(avatarUrl: avatarUrl, name: name, radius: 25),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      const Text('Rating ',
                          style:
                          TextStyle(color: Colors.grey, fontSize: 12)),
                      SellerRating(sellerId: widget.farmerId),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.message_outlined, color: Colors.green),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatPage(
                    receiverId: widget.farmerId,
                    farmerName: widget.farmerName),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesStatsCard(int totalSold) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long, color: Colors.green),
          const SizedBox(width: 12),
          const Expanded(
              child: Text('Total Products Listed',
                  style: TextStyle(fontSize: 16))),
          Text('$totalSold listing${totalSold == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
          child: Text(title,
              style: const TextStyle(
                  color: Colors.green, fontWeight: FontWeight.bold))),
    );
  }

  // ── CHANGED: trailing icon from delete→chevron (not the farmer's own listing)
  Widget _buildProductItem(
      String name, String quantityInfo, String imagePath) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: imagePath.isNotEmpty
              ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              imagePath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
              const Icon(Icons.image),
            ),
          )
              : const Icon(Icons.image),
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(quantityInfo,
            style: const TextStyle(color: Colors.grey)),
        // FIXED: was Icons.delete_outline (red) — wrong for a consumer viewing
        // another farmer's products. Changed to read-only chevron.
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }
}
