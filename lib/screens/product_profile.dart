import 'package:flutter/material.dart';
import 'main_screen/chat_page.dart';
import 'farmer_profile_page.dart';
import '../widgets/supabase_image.dart'; // IMPORTED shared widget

class ProductProfilePage extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductProfilePage({super.key, required this.product});

  @override
  State<ProductProfilePage> createState() => _ProductProfilePageState();
}

class _ProductProfilePageState extends State<ProductProfilePage> {
  int _quantity = 1;

  String _daysAgo() {
    final createdAtStr = widget.product['created_at'];
    if (createdAtStr == null) return 'Unknown';
    final createdAt = DateTime.parse(createdAtStr);
    final difference = DateTime.now().difference(createdAt);
    if (difference.inDays > 1) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays == 1) {
      return '1 day ago';
    } else {
      return 'Today';
    }
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
            _buildAddToCartButton(),
            const SizedBox(height: 24),
            _buildSectionHeader('Products Details'),
            _buildProductDetails(),
            const SizedBox(height: 24),
            _buildSectionHeader('Shipping Details'),
            _buildShippingDetails(),
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
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: SupabaseImage( // Now using the shared widget
            imagePath: widget.product['imageUrl'] ?? '',
            height: 60,
            width: 60,
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.product['productName'] ?? 'No Name',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Text('Add more Items'),
          ],
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Rs.${widget.product['price'] ?? 0}',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.green),
                  onPressed: () {
                    if (_quantity > 1) {
                      setState(() {
                        _quantity--;
                      });
                    }
                  },
                ),
                Text('$_quantity',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.green),
                  onPressed: () {
                    setState(() {
                      _quantity++;
                    });
                  },
                ),
              ],
            )
          ],
        ),
      ],
    );
  }

  Widget _buildAddToCartButton() {
    return ElevatedButton(
      onPressed: () {
        // TODO: Implement Add to DOOKO functionality
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: Colors.green),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: const Text(
        'Add to DOOKO',
        style: TextStyle(color: Colors.green, fontSize: 16),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildProductDetails() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.product['productName'] ?? 'No Name',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  _daysAgo(),
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(widget.product['description'] ?? 'No description provided'),
          ],
        ),
      ),
    );
  }

  Widget _buildShippingDetails() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.product['sellerName'] ?? 'Anonymous',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
                'Farmer\'s Location: ${widget.product['location'] ?? 'Not set'}'),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageButton() {
    return OutlinedButton(
      onPressed: () {
        final sellerId = widget.product['seller_id'] as String?;
        final sellerName = widget.product['sellerName'] as String?;

        if (sellerId != null && sellerName != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatPage(
                receiverId: sellerId,
                farmerName: sellerName,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not initiate chat. Seller not found.')),
          );
        }
      },
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.green),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: const Text(
        'Message',
        style: TextStyle(color: Colors.green, fontSize: 16),
      ),
    );
  }

  Widget _buildShowProfileButton() {
    return OutlinedButton(
      onPressed: () {
        final sellerId = widget.product['seller_id'] as String?;
        final sellerName = widget.product['sellerName'] as String?;

        if (sellerId != null && sellerName != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FarmerProfilePage(
                farmerId: sellerId,
                farmerName: sellerName,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Farmer profile not found.')),
          );
        }
      },
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.green),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: const Text(
        'Show Farmer\'s Profile',
        style: TextStyle(color: Colors.green, fontSize: 16),
      ),
    );
  }
}
