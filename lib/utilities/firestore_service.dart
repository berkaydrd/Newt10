import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class FirestoreService {
  static List<String> _candidateStockIds(String symbol) {
    final trimmed = symbol.trim().toUpperCase();
    final ids = <String>[];
    void add(String value) {
      if (value.isEmpty) return;
      if (!ids.contains(value)) ids.add(value);
    }

    add(trimmed);
    if (trimmed.contains('.')) {
      add(trimmed.split('.').first);
    }
    if (trimmed.endsWith('-USD')) {
      add(trimmed.replaceAll(RegExp('-USD\$'), ''));
    }
    if (trimmed.endsWith('=X')) {
      add(trimmed.replaceAll(RegExp('=X\$'), ''));
    }
    return ids;
  }

  static Future<bool> isUsernameAvailable(String username) async {
    for (int i = 0; i < 5; i++) {
      try {
        final result = await FirebaseFirestore.instance
            .collection('usernames')
            .doc(username.toLowerCase())
            .get(const GetOptions(source: Source.server));
        return !result.exists;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied' && i < 4) {
          await Future.delayed(const Duration(milliseconds: 700));
          continue;
        }
        rethrow;
      }
    }
    return true;
  }

  static Future<String?> getUsername(String uid) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('usernames')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        return doc.data()['username'] as String?;
      }
      return null;
    } catch (e) {
      print('Kullanıcı adı çekilirken hata: $e');
      return null;
    }
  }

  // --- 🔥 SORUNUN ÇÖZÜLDÜĞÜ YER ---
  static Future<void> addStockToPortfolio(String username, Map<String, dynamic> stockData) async {
    try {
      final portfolioRef = FirebaseFirestore.instance
          .collection('usernames')
          .doc(username.toLowerCase())
          .collection('portfolio');

      final String symbol = (stockData['symbol'] ?? '').toString();
      String? logoUrl = stockData['logo_url']?.toString();
      if (logoUrl == null || logoUrl.trim().isEmpty) {
        try {
          final candidates = _candidateStockIds(symbol);
          for (final candidate in candidates) {
            final stockDoc = await FirebaseFirestore.instance
                .collection('stocks')
                .doc(candidate)
                .get();
            if (!stockDoc.exists) continue;
            final data = stockDoc.data();
            final fetchedUrl = data?['logo_url']?.toString();
            if (fetchedUrl != null && fetchedUrl.trim().isNotEmpty) {
              logoUrl = fetchedUrl.trim();
              break;
            }
          }
        } catch (e) {
          print('Logo URL çekilirken hata: $e');
        }
      }
      final querySnapshot = await portfolioRef
          .where('symbol', isEqualTo: symbol)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        // --- HİSSE ZATEN VARSA (GÜNCELLEME) ---
        final doc = querySnapshot.docs.first;
        final currentData = doc.data();

        double oldShares = (currentData['shares'] as num? ?? 0).toDouble();
        double oldPrice = (currentData['purchase_price'] as num? ?? 0).toDouble();
        
        double newSharesToAdd = (stockData['shares'] as num? ?? 0).toDouble();
        double newPrice = (stockData['purchase_price'] as num? ?? 0).toDouble();

        double totalShares = oldShares + newSharesToAdd;
        
        // Satış işleminde maliyet değişmez
        double averagePrice = oldPrice; 
        
        // Alış işleminde ortalama maliyet hesapla
        if (newSharesToAdd > 0) {
          double totalCost = (oldShares * oldPrice) + (newSharesToAdd * newPrice);
          averagePrice = totalCost / totalShares;
        }

        // 🚨 İŞTE BURASI EKSİKTİ! ARTIK CURRENCY DE GÜNCELLENİYOR.
        final existingLogoUrl = currentData['logo_url']?.toString();
        final hasExistingLogo =
            existingLogoUrl != null && existingLogoUrl.trim().isNotEmpty;
        await doc.reference.update({
          'shares': totalShares,
          'purchase_price': averagePrice,
          'current_price': stockData['current_price'],
          'color': stockData['color'],
          'currency': stockData['currency'], // <--- BU SATIR EKLENDİ!
          if ((logoUrl != null && logoUrl.isNotEmpty) || hasExistingLogo)
            'logo_url': (logoUrl != null && logoUrl.isNotEmpty)
                ? logoUrl
                : existingLogoUrl,
        });

      } else {
        // --- YENİ HİSSE ---
        final newData = Map<String, dynamic>.from(stockData);
        if (logoUrl != null && logoUrl.isNotEmpty) {
          newData['logo_url'] = logoUrl;
        }
        await portfolioRef.add(newData);
      }

    } catch (e) {
      print("Hisse işlemi sırasında hata oluştu: $e");
    }
  }

  static Future<void> deleteStockFromPortfolio(String username, String symbol) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(username.toLowerCase())
          .collection('portfolio')
          .where('symbol', isEqualTo: symbol)
          .get();

      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }
      print("Hisse silindi: $symbol");
    } catch (e) {
      print("Hisse silinirken hata oluştu: $e");
    }
  }

  static Stream<List<Map<String, dynamic>>> getPortfolioStream(String username) {
    return FirebaseFirestore.instance
        .collection('usernames')
        .doc(username.toLowerCase())
        .collection('portfolio')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['docId'] = doc.id; 
            return data;
          }).toList();
        });
  }

  static Future<String?> getProfileImagePath(String username) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(username.toLowerCase())
          .get();
          
      if (doc.exists && doc.data() != null) {
        return doc.data()!['profile_image_path'] as String?; 
      }
      return null;
    } catch (e) {
      print("Resim çekilemedi: $e");
      return null;
    }
  }

  static Future<String?> uploadProfileImage(String username, File imageFile) async {
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('${username.toLowerCase()}.jpg');

      final uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('usernames')
          .doc(username.toLowerCase())
          .update({
            'profile_image_path': downloadUrl,
          });

      return downloadUrl;

    } catch (e) {
      print("Resim yükleme hatası: $e");
      return null;
    }
  }

  // 1. GÜNLÜK SNAPSHOT
  static Future<void> recordDailySnapshot(String username, double totalValueTRY, double totalValueUSD) async {
    try {
      final now = DateTime.now();
      final String dateId = "${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}";
      
      final docRef = FirebaseFirestore.instance
          .collection('usernames')
          .doc(username.toLowerCase())
          .collection('history')
          .doc(dateId);

      await docRef.set({
        'date': Timestamp.now(),
        'total_value_try': totalValueTRY,
        'total_value_usd': totalValueUSD,
      }, SetOptions(merge: true));

      print("Günlük Snapshot Alındı: $dateId -> $totalValueTRY TL");
    } catch (e) {
      print("Snapshot hatası: $e");
    }
  }

  // 2. NAKİT AKIŞI
  static Future<void> recordCashFlow(
    String username,
    double amountTRY,
    String type, {
    String currency = 'TRY',
    double? amountCurrency,
  }) async {
    try {
      final String normalizedCurrency = currency.toUpperCase();
      final double safeAmountCurrency = amountCurrency ?? amountTRY;
      double fxRate = 1.0;
      if (normalizedCurrency != 'TRY' && safeAmountCurrency > 0) {
        fxRate = amountTRY / safeAmountCurrency;
      }

      await FirebaseFirestore.instance
          .collection('usernames')
          .doc(username.toLowerCase())
          .collection('cash_flows')
          .add({
        'date': Timestamp.now(),
        'amount_try': amountTRY,
        'amount_currency': safeAmountCurrency,
        'currency': normalizedCurrency,
        'fx_rate': fxRate,
        'type': type, 
      });
      print("Nakit Akışı Kaydedildi: $type -> $amountTRY TL");
    } catch (e) {
      print("Cash Flow hatası: $e");
    }
  }

  // 3. GRAFİK VERİSİ
  static Future<List<Map<String, dynamic>>> getHistoryData(String username) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(username.toLowerCase())
          .collection('history')
          .orderBy('date', descending: false)
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print("Tarihçe çekilemedi: $e");
      return [];
    }
  }

  // 4. CASH FLOW GETİR
  static Future<List<Map<String, dynamic>>> getCashFlows(String username) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(username.toLowerCase())
          .collection('cash_flows')
          .orderBy('date', descending: false)
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print("Nakit akışı çekilemedi: $e");
      return [];
    }
  }

  // 5. PERFORMANCE HISTORY (STREAM)
  static Stream<List<Map<String, dynamic>>> getPerformanceHistoryStream(String username) {
    return FirebaseFirestore.instance
        .collection('usernames')
        .doc(username.toLowerCase())
        .collection('performance_history')
        .orderBy('date', descending: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['docId'] = doc.id;
            return data;
          }).toList();
        });
  }

  // 6. TEMP HOURLY SNAPSHOTS (STREAM)
  static Stream<List<Map<String, dynamic>>> getTempHourlySnapshotsStream(
    String username,
  ) {
    return FirebaseFirestore.instance
        .collection('usernames')
        .doc(username.toLowerCase())
        .collection('performance_intraday')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['docId'] = doc.id;
            return data;
          }).toList();
        });
  }

  // popular_stocks/v1 → entries: [{symbol, logo_url, return_24h_pct, price, name}]
  static Stream<List<Map<String, dynamic>>> getPopularStocksStream() {
    return FirebaseFirestore.instance
        .collection('popular_stocks')
        .doc('v1')
        .snapshots()
        .map((doc) {
          if (!doc.exists || doc.data() == null) return <Map<String, dynamic>>[];
          final entries = doc.data()!['entries'];
          if (entries is! List) return <Map<String, dynamic>>[];
          return entries
              .whereType<Map<String, dynamic>>()
              .toList();
        })
        .handleError((error) {
          print('[FirestoreService] getPopularStocksStream error: $error');
        });
  }
}
