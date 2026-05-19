import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NotificationsView extends StatefulWidget {
  final String username;

  const NotificationsView({super.key, required this.username});

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  late final Future<String?> _userDocIdFuture;

  @override
  void initState() {
    super.initState();
    _userDocIdFuture = _resolveUserDocId();
  }

  Future<String?> _resolveUserDocId() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final snap = await FirebaseFirestore.instance
          .collection('usernames')
          .where('uid', isEqualTo: currentUser.uid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return snap.docs.first.id;
      }
    }

    final fallback = widget.username.trim();
    if (fallback.isEmpty ||
        fallback == 'Yükleniyor...' ||
        fallback == 'Giriş Yapılmadı') {
      return null;
    }
    return fallback.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Bildirimler", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 22)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        foregroundColor: Colors.black,
      ),
      body: FutureBuilder<String?>(
        future: _userDocIdFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text("Kullanıcı bilgisi alınamadı."));
          }

          final userDocId = snapshot.data;
          if (userDocId == null || userDocId.isEmpty) {
            return const Center(child: Text("Bildirimler görüntülenemiyor."));
          }

          final ref = FirebaseFirestore.instance
              .collection('usernames')
              .doc(userDocId)
              .collection('notifications');

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: ref.snapshots(),
            builder: (context, notificationsSnapshot) {
              if (notificationsSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (notificationsSnapshot.hasError) {
                return const Center(child: Text("Bildirimler yüklenemedi."));
              }

              final docs = notificationsSnapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text("Henüz bildirim yok."));
              }

              final sortedDocs = [...docs]
                ..sort((a, b) {
                  final aData = a.data();
                  final bData = b.data();
                  final aTs = (aData['created_at'] as Timestamp?) ??
                      (aData['event_date'] as Timestamp?);
                  final bTs = (bData['created_at'] as Timestamp?) ??
                      (bData['event_date'] as Timestamp?);
                  final aMillis = aTs?.millisecondsSinceEpoch ?? 0;
                  final bMillis = bTs?.millisecondsSinceEpoch ?? 0;
                  return bMillis.compareTo(aMillis);
                });

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: sortedDocs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = sortedDocs[index];
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
