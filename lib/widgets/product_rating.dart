// lib/widgets/product_rating.dart
//
// CHANGES FROM ORIGINAL:
//  • Converted from StatelessWidget + FutureBuilder to StatefulWidget
//    so it can show a loading shimmer and avoid flickering on rebuild.
//  • Gracefully handles productId == 0 without hitting the database.
//  • Uses rounded star icon to match seller_rating.dart visually.
//  • Error state shows "–" instead of silently showing 0.0 (impartial display).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductRating extends StatefulWidget {
  final int productId;
  final double iconSize;
  final double fontSize;
  final Color textColor;

  const ProductRating({
    super.key,
    required this.productId,
    this.iconSize = 16,
    this.fontSize = 12,
    this.textColor = Colors.grey,
  });

  @override
  State<ProductRating> createState() => _ProductRatingState();
}

class _ProductRatingState extends State<ProductRating> {
  double _average = 0.0;
  int _count = 0;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (widget.productId > 0) _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await Supabase.instance.client
          .from('product_reviews')
          .select('rating')
          .eq('product_id', widget.productId);

      if (!mounted) return;

      final reviews = List<Map<String, dynamic>>.from(data as List);
      if (reviews.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      double sum = 0;
      for (final r in reviews) {
        sum += (r['rating'] as num).toDouble();
      }

      setState(() {
        _average = sum / reviews.length;
        _count = reviews.length;
        _loading = false;
      });
    } catch (e) {
      debugPrint('ProductRating fetch error: $e');
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // No product — show nothing
    if (widget.productId <= 0) return _buildRow(0.0, 0);

    if (_loading) {
      return SizedBox(
        height: widget.iconSize,
        width: 60,
        child: LinearProgressIndicator(
          backgroundColor: Colors.grey.shade200,
          color: Colors.amber.shade200,
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }

    if (_hasError) {
      return Text(
        '–',
        style: TextStyle(fontSize: widget.fontSize, color: widget.textColor),
      );
    }

    return _buildRow(_average, _count);
  }

  Widget _buildRow(double average, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, color: Colors.amber, size: widget.iconSize),
        const SizedBox(width: 3),
        Text(
          average == 0.0 ? '0.0' : average.toStringAsFixed(1),
          style: TextStyle(
            fontSize: widget.fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '($count)',
          style: TextStyle(fontSize: widget.fontSize, color: widget.textColor),
        ),
      ],
    );
  }
}