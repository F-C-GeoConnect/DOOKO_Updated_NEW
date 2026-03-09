import 'package:flutter/material.dart';

/// Shows a "Today / Yesterday / dd/mm/yyyy" label between messages whenever
/// the calendar day changes.
class DateSeparator extends StatelessWidget {
  final String? isoDate;

  const DateSeparator({super.key, this.isoDate});

  String _label() {
    if (isoDate == null) return '';
    try {
      final dt = DateTime.parse(isoDate!).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);
      final diff = today.difference(msgDay).inDays;
      if (diff == 0) return 'Today';
      if (diff == 1) return 'Yesterday';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _label();
    if (label.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[300])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey[300])),
        ],
      ),
    );
  }
}