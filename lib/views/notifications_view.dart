import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NotificationsView extends StatelessWidget {
  final String username;

  const NotificationsView({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    if (username.isEmpty || username == 'Yükleniyor...' || username == 'Giriş Yapılmadı') {
      return const Scaffold(
        body: Center(child: Text("Bildirimler görüntülenemiyor.")),
      );
    }

    final ref = FirebaseFirestore.instance
        .collection('usernames')
        .doc(username.toLowerCase())
        .collection('notifications')
        .orderBy('created_at', descending: true);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Bildirimler", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 22)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        foregroundColor: Colors.black,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Henüz bildirim yok."));
          }

          final docs = snapshot.data!.docs;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final type = (data['type'] ?? '').toString();
              final symbol = (data['symbol'] ?? '').toString();
              final bool read = data['read'] == true;

              final String title;
              final String body;
              final DateTime? eventDate = (data['event_date'] as Timestamp?)?.toDate();

              if (type == 'dividend') {
                final amount = (data['amount_try'] as num? ?? 0).toDouble();
                title = "Temettü Ödemesi Alındı: $symbol";
                body = "${_formatAmount(amount, 'TRY')} tutarında temettü hesabınıza işlendi.";
              } else if (type == 'split') {
                final ratioText = (data['ratio_text'] ?? '').toString();
                title = "Hisse Bölünmesi: $symbol";
                body = "Hisse oranı ${ratioText.isNotEmpty ? ratioText : 'N/A'} olarak güncellendi.";
              } else {
                title = "Bildirim";
                body = "Yeni bir bildirim aldınız.";
              }

              return GestureDetector(
                onTap: () async {
                  if (!read) {
                    await doc.reference.update({'read': true});
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: read ? Colors.white : const Color(0xFFF3F6FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: read ? Colors.grey.shade200 : Colors.black,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          type == 'split' ? Icons.call_split : Icons.card_giftcard,
                          color: read ? Colors.black : Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(body, style: TextStyle(color: Colors.grey.shade700)),
                            if (eventDate != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                _formatDate(eventDate),
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!read)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 8, top: 6),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatAmount(double amount, String currency) {
    final format = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: currency == 'TRY' ? '₺' : '\$',
      decimalDigits: 2,
    );
    return format.format(amount);
  }

  String _formatDate(DateTime date) {
    final fmt = DateFormat('dd MMM yyyy', 'tr_TR');
    return fmt.format(date);
  }
}
