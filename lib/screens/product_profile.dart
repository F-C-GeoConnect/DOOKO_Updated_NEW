import 'package:flutter/material.dart';
import 'package:untitled1/providers/cart_provider.dart';
import 'package:provider/provider.dart';
import 'farmer_profile_page.dart';
import 'main_screen/chat_page.dart';
import '../widgets/seller_rating.dart';
import '../widgets/product_rating.dart';
import '../widgets/supabase_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_screen/cart_screen.dart';

class ProductProfilePage extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductProfilePage({super.key, required this.product});

  @override
  State<ProductProfilePage> createState() => _ProductProfilePageState();
}

class _ProductProfilePageState extends State<ProductProfilePage> {
  int _quantity = 1;
  final SupabaseClient _supabase = Supabase.instance.client;

  String _daysAgo() {
    final createdAtString = widget.product['created_at'] as String?;
    if (createdAtString == null) return 'Unknown';
    final createdAt = DateTime.parse(createdAtString);
    final difference = DateTime.now().difference(createdAt);
    if (difference.inDays > 1) return '${difference.inDays} days ago';
    if (difference.inDays == 1) return '1 day ago';
    return 'Today';
  }

  void _navigateToCheckout() {
    final productId = widget.product['id'] as int? ?? 0;
    final productName = widget.product['productName'] ?? 'Product';
    final price = widget.product['price']?.toDouble() ?? 0.0;
    final image = widget.product['imageUrl'] ?? '';
    final sellerId = widget.product['seller_id'] ?? '';

    final directItem = CartItem(
      id: productId,
      name: productName,
      price: price,
      image: image,
      quantity: _quantity,
      sellerId: sellerId,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CartScreen(directItem: directItem),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProductHeader(),
            const SizedBox(height: 24),
            _buildActionButtons(),
            const SizedBox(height: 24),
            _buildSectionHeader('Products Details'),
            _buildProductDetails(),
            const SizedBox(height: 24),
            _buildSectionHeader('Shipping Details'),
            _buildShippingDetails(),
            const SizedBox(height: 24),
            _buildSectionHeader('Product Reviews'),
            _buildReviewsList(),
            const SizedBox(height: 24),
            _buildMessageButton(),
            const SizedBox(height: 16),
            _buildShowProfileButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildProductHeader() {
    final productName = (widget.product['productName'] as String?)?.trim() ?? 'Unnamed Product';
    final imageUrl = (widget.product['imageUrl'] as String?)?.trim() ?? '';
    final priceValue = widget.product['price'];
    final sellerId = widget.product['seller_id'] as String? ?? '';
    final productId = widget.product['id'] as int? ?? 0;
    
    // FIX: Using the actual category from the database Map
    final category = widget.product['category'] as String? ?? 'Others';

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
              const SizedBox(height: 8),
              ProductRating(productId: productId, iconSize: 18, fontSize: 14),
              const SizedBox(height: 4),
              SellerRating(sellerId: sellerId), 
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
                IconButton(constraints: const BoxConstraints(), padding: const EdgeInsets.all(4), icon: const Icon(Icons.remove_circle_outline, color: Colors.green, size: 24), onPressed: () { if (_quantity > 1) setState(() => _quantity--); }),
                Text('$_quantity', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(constraints: const BoxConstraints(), padding: const EdgeInsets.all(4), icon: const Icon(Icons.add_circle, color: Colors.green, size: 24), onPressed: () => setState(() => _quantity++)),
              ],
            )
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
      child: Text(
        category,
        style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(child: _buildAddToCartButton()),
        const SizedBox(width: 12),
        Expanded(child: _buildBuyNowButton()),
      ],
    );
  }

  Widget _buildAddToCartButton() {
    final cart = Provider.of<CartProvider>(context, listen: false);
    final productId = widget.product['id'] as int?;
    if (productId == null) return const SizedBox.shrink();

    final isAdded = cart.isItemInCart(productId);
    return ElevatedButton(
      onPressed: () {
        cart.toggleCartStatus(productId, widget.product['productName'] ?? '', widget.product['price']?.toDouble() ?? 0.0, widget.product['imageUrl'] ?? '', widget.product['seller_id'] ?? '');
        setState(() {});
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isAdded ? Colors.red : Colors.white,
        side: const BorderSide(color: Colors.green),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(isAdded ? 'Remove' : 'Add to DOOKO', style: TextStyle(color: isAdded ? Colors.white : Colors.green, fontSize: 14), textAlign: TextAlign.center),
    );
  }

  Widget _buildBuyNowButton() {
    return ElevatedButton(
      onPressed: _navigateToCheckout,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text('Buy Now', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(padding: const EdgeInsets.only(left: 4.0, bottom: 8.0), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)));
  }

  Widget _buildProductDetails() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300, width: 1), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(widget.product['productName'] ?? 'Unnamed', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                Text(_daysAgo(), style: const TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            Text(widget.product['description'] ?? 'No description.'),
          ],
        ),
      ),
    );
  }

  Widget _buildShippingDetails() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300, width: 1), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.product['sellerName'] ?? 'Unknown Seller', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Farmer\'s Location: ${widget.product['location'] ?? 'Unknown'}'),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewsList() {
    final productId = widget.product['id'] as int? ?? 0;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _supabase.from('product_reviews').select().eq('product_id', productId).order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('No reviews yet.'));
        final reviews = snapshot.data!;
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: reviews.length,
          separatorBuilder: (context, index) => const Divider(),
          itemBuilder: (context, index) {
            final review = reviews[index];
            return ListTile(
              title: Row(
                children: List.generate(5, (i) => Icon(i < (review['rating'] as int) ? Icons.star : Icons.star_border, color: Colors.amber, size: 16)),
              ),
              subtitle: Text(review['comment'] ?? ''),
              trailing: Text(_formatReviewDate(review['created_at']), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            );
          },
        );
      },
    );
  }

  String _formatReviewDate(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.parse(dateStr);
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildMessageButton() {
    return OutlinedButton(
      onPressed: () {
        if (widget.product['seller_id'] != null && widget.product['sellerName'] != null) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => ChatPage(receiverId: widget.product['seller_id'], farmerName: widget.product['sellerName'])));
        }
      },
      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.green), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      child: const Text('Message', style: TextStyle(color: Colors.green, fontSize: 16)),
    );
  }

  Widget _buildShowProfileButton() {
    return OutlinedButton(
      onPressed: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => FarmerProfilePage(farmerId: widget.product['seller_id'] ?? '', farmerName: widget.product['sellerName'] ?? 'Unknown')));
      },
      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.green), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      child: const Text('Show Farmer\'s Profile', style: TextStyle(color: Colors.green, fontSize: 16)),
    );
  }
}
