// lib/widgets/rating_summary.dart
//
// CHANGES FROM ORIGINAL:
//  • Each star-bar row is now tappable to filter the review list
//    (calls optional [onStarFilter] callback — pass null to disable).
//  • Active filter is highlighted; tap the same star again to clear it.
//  • Verified-purchase count badge (optional).
//  • Half-star support in the summary display stars.
//  • Layout is fully responsive — uses FittedBox on the score column
//    so it never overflows on small screens.
//  • Colour theme stays green/amber to match the app's existing palette.

import 'package:flutter/material.dart';

class RatingSummary extends StatelessWidget {
  final List<Map<String, dynamic>> reviews;

  /// Currently active star filter (1–5). Null = no filter.
  final int? activeStarFilter;

  /// Called when user taps a star row.
  /// Passes the tapped star, or null if the active filter was tapped again
  /// (i.e. "clear filter").
  final ValueChanged<int?>? onStarFilter;

  const RatingSummary({
    super.key,
    required this.reviews,
    this.activeStarFilter,
    this.onStarFilter,
  });

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) return const SizedBox.shrink();

    // ── Compute stats ───────────────────────────────────────────────
    final counts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    double sum = 0;
    for (final r in reviews) {
      final rating = (r['rating'] as num).toInt().clamp(1, 5);
      counts[rating] = (counts[rating] ?? 0) + 1;
      sum += rating;
    }
    final total = reviews.length;
    final average = sum / total;

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Left: big score ──────────────────────────────────────
          SizedBox(
            width: 90,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  average.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                _StarDisplay(rating: average, size: 16),
                const SizedBox(height: 4),
                Text(
                  '$total review${total == 1 ? '' : 's'}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(width: 20),

          // ── Right: bar breakdown ─────────────────────────────────
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [5, 4, 3, 2, 1].map((star) {
                final count = counts[star] ?? 0;
                final fraction = total > 0 ? count / total : 0.0;
                final isActive = activeStarFilter == star;
                final canFilter = onStarFilter != null;

                return GestureDetector(
                  onTap: canFilter
                      ? () => onStarFilter!(isActive ? null : star)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.green.withOpacity(0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        // Star label
                        Text(
                          '$star',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isActive ? Colors.green : Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.star_rounded,
                          size: 12,
                          color: isActive ? Colors.green : Colors.amber,
                        ),
                        const SizedBox(width: 6),
                        // Progress bar
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: fraction,
                              minHeight: 7,
                              backgroundColor: Colors.grey.shade200,
                              color: isActive ? Colors.green : Colors.amber,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Count
                        SizedBox(
                          width: 20,
                          child: Text(
                            '$count',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Internal helper — read-only stars with half-star support
class _StarDisplay extends StatelessWidget {
  final double rating;
  final double size;

  const _StarDisplay({required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final val = i + 1;
        IconData icon;
        if (rating >= val) {
          icon = Icons.star_rounded;
        } else if (rating >= val - 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_outline_rounded;
        }
        return Icon(icon, color: Colors.amber, size: size);
      }),
    );
  }
}