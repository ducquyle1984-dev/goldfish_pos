import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/customer_feedback_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:intl/intl.dart';

/// Shows all stored negative feedback so staff can review and improve.
class CustomerFeedbackScreen extends StatelessWidget {
  const CustomerFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = PosRepository();
    return Scaffold(
      appBar: AppBar(title: const Text('Customer Feedback'), elevation: 0),
      body: StreamBuilder<List<CustomerFeedback>>(
        stream: repo.streamCustomerFeedback(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sentiment_satisfied_alt,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No negative feedback yet — great job! 🎉',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final fb = items[index];
              return _FeedbackCard(feedback: fb, repo: repo);
            },
          );
        },
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final CustomerFeedback feedback;
  final PosRepository repo;

  const _FeedbackCard({required this.feedback, required this.repo});

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat(
      'MMM d, yyyy  h:mm a',
    ).format(feedback.createdAt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sentiment_dissatisfied, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    feedback.customerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  dateStr,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _confirmDelete(context),
                ),
              ],
            ),
            if (feedback.customerPhone.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Phone: ${feedback.customerPhone}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(feedback.feedbackText),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  feedback.smsSent ? Icons.check_circle : Icons.cancel,
                  color: feedback.smsSent ? Colors.green : Colors.grey,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  feedback.smsSent ? 'SMS sent' : 'No SMS sent',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Feedback'),
        content: const Text('Remove this feedback entry permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repo.deleteCustomerFeedback(feedback.id);
    }
  }
}
