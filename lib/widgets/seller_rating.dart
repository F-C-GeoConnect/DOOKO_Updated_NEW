import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SellerRating extends StatelessWidget {
  final String sellerId;
  final double iconSize;
  final double fontSize;
  final Color textColor;

  const SellerRating({
    super.key,
    required this.sellerId,
    this.iconSize = 16,
    this.fontSize = 12,
    this.textColor = Colors.grey,
  });

  @override
  Widget build(BuildContext context) {
    if (sellerId.isEmpty) return _buildRatingRow(0.0, 0);

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('farmer_reviews')
          .select('rating')
          .eq('farmer_id', sellerId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Error in SellerRating: ${snapshot.error}');
          return _buildRatingRow(0.0, 0);
        }

        final reviews = snapshot.data;
        if (reviews == null || reviews.isEmpty) {
          return _buildRatingRow(0.0, 0);
        }

        double sum = 0;
        for (var review in reviews) {
          sum += (review['rating'] as num).toDouble();
        }
        double average = sum / reviews.length;

        return _buildRatingRow(average, reviews.length);
      },
    );
  }

  Widget _buildRatingRow(double average, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, color: Colors.amber, size: iconSize),
        const SizedBox(width: 4),
        Text(
          average == 0 ? '0.0' : average.toStringAsFixed(1),
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 4),
        Text(
          '($count)',
          style: TextStyle(fontSize: fontSize, color: textColor),
        ),
      ],
    );
  }
}