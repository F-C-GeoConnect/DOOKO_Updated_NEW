import 'package:flutter/material.dart';

class ProductRating extends StatelessWidget {
  final int productId;

  const ProductRating({
    super.key,
    required this.productId,
  });

  @override
  Widget build(BuildContext context) {
    // For now, we show a consistent placeholder rating.
    // In a future update, we can fetch real ratings from a 'product_reviews' table.
    return const Row(
      children: [
        Icon(Icons.star, color: Colors.amber, size: 16),
        SizedBox(width: 4),
        Text(
          '4.5',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        SizedBox(width: 4),
        Text(
          '(123)',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
