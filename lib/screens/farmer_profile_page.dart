import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_screen/chat_page.dart';
import '../widgets/seller_rating.dart';

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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _fetchFarmerReviews(),
      _fetchFarmerProducts(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchFarmerProducts() async {
    try {
      final data = await _supabase
          .from('products')
          .select()
          .eq('sellerID', widget.farmerId)
          .order('created_at', ascending: false);

      if (data != null) {
        setState(() {
          _farmerProducts = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('Error fetching farmer products: $e');
    }
  }

  Future<void> _fetchFarmerReviews({bool updateController = true}) async {
    try {
      final reviews = await _supabase
          .from('farmer_reviews')
          .select('*, profiles(full_name)')
          .eq('farmer_id', widget.farmerId)
          .order('created_at', ascending: false);

      if (reviews != null) {
        final List<dynamic> reviewList = reviews as List;
        final currentUserId = _supabase.auth.currentUser?.id;

        int foundRating = 0;
        String foundComment = '';

        for (var review in reviewList) {
          if (currentUserId != null && review['user_id'] == currentUserId) {
            foundRating = review['rating'] as int;
            foundComment = review['comment'] ?? '';
          }
        }

        setState(() {
          _userSelectedRating = foundRating;
          if (updateController) {
            _commentController.text = foundComment;
            _commentController.selection = TextSelection.fromPosition(
              TextPosition(offset: _commentController.text.length),
            );
          }
          _comments = List<Map<String, dynamic>>.from(reviewList);
        });
      }
    } catch (e) {
      debugPrint('Error fetching reviews: $e');
    }
  }

  Future<void> _submitReview() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    if (_userSelectedRating == 0) {
      _showRatingDialog();
      return;
    }

    try {
      final commentText = _commentController.text.trim();

      await _supabase.from('farmer_reviews').upsert({
        'farmer_id': widget.farmerId,
        'user_id': user.id,
        'rating': _userSelectedRating,
        'comment': commentText,
      }, onConflict: 'farmer_id,user_id');

      // Clear only the text, keep the rating selection visible
      setState(() {
        _commentController.clear();
      });

      // Refresh list to show the new "physical" comment
      await _fetchFarmerReviews(updateController: false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Review posted!'), backgroundColor: Colors.green),
        );
        _commentFocusNode.unfocus();
      }
    } catch (e) {
      debugPrint('Error submitting review: $e');
    }
  }

  Future<void> _deleteReview() async {
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Review deleted'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      debugPrint('Error deleting review: $e');
    }
  }

  void _showRatingDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Center(child: Text('Rate Farmer')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('How was your experience?', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) => IconButton(
                    icon: Icon(
                      index < _userSelectedRating ? Icons.star : Icons.star_border,
                      color: Colors.orangeAccent,
                      size: 32,
                    ),
                    onPressed: () {
                      setDialogState(() => _userSelectedRating = index + 1);
                      setState(() {});
                    },
                  )),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int totalSold = _farmerProducts.length;

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
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFarmerHeader(context),
            const SizedBox(height: 10),
            _buildRatingSection(),
            const SizedBox(height: 20),
            _buildSalesStatsCard(totalSold),
            const SizedBox(height: 20),
            _buildSectionTitle('Farmer\'s Products'),
            _farmerProducts.isEmpty
                ? const Center(child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Text('No listings yet'),
            ))
                : Column(
              children: _farmerProducts.map((product) =>
                  _buildProductItem(
                    product['productName'] ?? 'Unnamed',
                    'Rs. ${product['price']}',
                    product['imageUrl'] ?? '',
                  )).toList(),
            ),
            const SizedBox(height: 32),
            const Text('Reviews', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            const SizedBox(height: 12),
            _buildDescriptionInputBar(),
            const SizedBox(height: 24),
            _buildCommentsList(),
            const SizedBox(height: 40),
          ],
        ),
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
    if (_comments.isEmpty) {
      return const Center(child: Text('No reviews yet. Be the first to rate!', style: TextStyle(color: Colors.grey)));
    }

    final currentUserId = _supabase.auth.currentUser?.id;

    return Column(
      children: _comments.map((review) {
        final profile = review['profiles'] as Map<String, dynamic>?;
        final reviewerName = profile?['full_name'] ?? 'Verified User';
        final rating = review['rating'] ?? 0;
        final isMyReview = currentUserId != null && review['user_id'] == currentUserId;

        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.green.shade100,
                    child: Text(reviewerName.isNotEmpty ? reviewerName[0].toUpperCase() : 'U', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(reviewerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                  Row(
                    children: List.generate(5, (i) => Icon(
                      i < rating ? Icons.star : Icons.star_border,
                      size: 14, color: Colors.orangeAccent,
                    )),
                  ),
                  if (isMyReview)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                      onSelected: (value) async {
                        if (value == 'edit') {
                          setState(() {
                            _userSelectedRating = review['rating'] as int;
                            _commentController.text = review['comment'] ?? '';
                            _commentController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _commentController.text.length),
                            );
                          });
                          _commentFocusNode.requestFocus();
                        } else if (value == 'delete') {
                          _deleteReview();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Text(
                  review['comment'] ?? '',
                  style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(indent: 44, color: Colors.black12),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFarmerHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        children: [
          const CircleAvatar(
              radius: 25,
              backgroundImage: NetworkImage('https://via.placeholder.com/150')),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.farmerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      const Text('Rating ', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => ChatPage(receiverId: widget.farmerId, farmerName: widget.farmerName)));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRatingSection() {
    return InkWell(
      onTap: _showRatingDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade100),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Your Rating:',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            Row(
              children: List.generate(5, (index) => Icon(
                index < _userSelectedRating ? Icons.star : Icons.star_border,
                color: Colors.orangeAccent, size: 24,
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesStatsCard(int totalSold) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long, color: Colors.green),
          const SizedBox(width: 12),
          const Expanded(child: Text('Total Product sold', style: TextStyle(fontSize: 16))),
          Text('$totalSold units', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(10)),
      child: Center(child: Text(title, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
    );
  }

  Widget _buildProductItem(String name, String quantityInfo, String imagePath) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 50, height: 50,
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
          child: imagePath.isNotEmpty ? Image.network(imagePath, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.image),) : const Icon(Icons.image),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis,),
        subtitle: Text(quantityInfo, style: const TextStyle(color: Colors.grey)),
        trailing: const Icon(Icons.delete_outline, color: Colors.red),
      ),
    );
  }
}
