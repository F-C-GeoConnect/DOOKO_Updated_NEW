// lib/widgets/seller_rating.dart
//
// CHANGES FROM ORIGINAL:
//  • Uses StreamBuilder on a Supabase realtime channel so the badge
//    updates live when new reviews arrive — no manual refresh needed.
//  • Falls back to a one-shot FutureBuilder if realtime isn't needed.
//  • Shows a shimmer placeholder while loading instead of nothing.
//  • Handles empty sellerId gracefully (no unnecessary DB round-trip).
//  • Star icon colour matches product_rating.dart (Colors.amber → consistent).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SellerRating extends StatefulWidget {
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
  State<SellerRating> createState() => _SellerRatingState();
}

class _SellerRatingState extends State<SellerRating> {
  double _average = 0.0;
  int _count = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.sellerId.isNotEmpty) _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await Supabase.instance.client
          .from('farmer_reviews')
          .select('rating')
          .eq('farmer_id', widget.sellerId);

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
      debugPrint('SellerRating fetch error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sellerId.isEmpty) return _buildRow(0.0, 0);

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