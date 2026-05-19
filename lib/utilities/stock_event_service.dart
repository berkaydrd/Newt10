import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_newtten/utilities/firestore_service.dart';
import 'package:flutter_application_newtten/utilities/notification_service.dart';
import 'package:flutter_application_newtten/utilities/stock_service.dart';
import 'package:http/http.dart' as http;

class StockEventService {
  final StockService _stockService = StockService();
  final NotificationService _notificationService = NotificationService();

  Future<void> processPortfolioEvents(String username) async {
    final userId = username.toLowerCase();
    await _notificationService.init();

    final portfolio = await FirestoreService.getPortfolioStream(userId).first;
    if (portfolio.isEmpty) return;

    final double exchangeRate = await _stockService.getExchangeRate();
    for (final stock in portfolio) {
      await _processStockEvents(
        userId: userId,
        stock: stock,
        exchangeRate: exchangeRate,
      );
    }
  }

  Future<void> _processStockEvents({
    required String userId,
    required Map<String, dynamic> stock,
    required double exchangeRate,
  }) async {
    final symbol = (stock['symbol'] ?? '').toString().trim();
    if (symbol.isEmpty) return;

    final String currency = (stock['currency'] ?? '').toString().toUpperCase();
    final bool isBist = symbol.toUpperCase().endsWith('.IS');
    final String yahooSymbol = (!isBist && currency == 'TRY') ? '$symbol.IS' : symbol;

    final events = await _fetchEvents(yahooSymbol);
    if (events.isEmpty) return;

    final DocumentReference<Map<String, dynamic>>? stockRef = await _resolveStockRef(userId, stock);
    if (stockRef == null) return;

    await _handleDividends(
      userId: userId,
      stockRef: stockRef,
      stock: stock,
      events: events['dividends'],
      exchangeRate: exchangeRate,
    );

    await _handleSplits(
      userId: userId,
      stockRef: stockRef,
      stock: stock,
      events: events['splits'],
    );
  }

  Future<Map<String, dynamic>> _fetchEvents(String symbol) async {
    try {
      final url = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=1d&range=5d&events=div,splits',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      });
      if (response.statusCode != 200) return {};
      final data = json.decode(response.body);
      final result = data['chart']?['result'];
      if (result == null || result.isEmpty) return {};
      final events = result[0]['events'];
      if (events == null) return {};
      return Map<String, dynamic>.from(events);
    } catch (_) {
      return {};
    }
  }

  Future<void> _handleDividends({
    required String userId,
    required DocumentReference<Map<String, dynamic>> stockRef,
    required Map<String, dynamic> stock,
    required dynamic events,
    required double exchangeRate,
  }) async {
    if (events == null) return;
    final Map<String, dynamic> dividends = Map<String, dynamic>.from(events);

    final double shares = (stock['shares'] as num? ?? 0).toDouble();
    final String currency = (stock['currency'] ?? '').toString().toUpperCase();

    for (final entry in dividends.entries) {
      final String eventId = 'dividend_${entry.key}';
      if (await _isProcessed(stockRef, eventId)) continue;

      final Map<String, dynamic> event = Map<String, dynamic>.from(entry.value);
      final double amountPerShare = (event['amount'] as num? ?? 0).toDouble();
      final int ts = (event['date'] as num? ?? 0).toInt();
      final DateTime eventDate = DateTime.fromMillisecondsSinceEpoch(ts * 1000);

      final double totalRaw = amountPerShare * shares;
      final double amountTry = currency == 'USD' ? (totalRaw * exchangeRate) : totalRaw;

      if (amountTry > 0) {
        await FirestoreService.recordCashFlow(
          userId,
          amountTry,
          'dividend',
          currency: currency,
          amountCurrency: totalRaw,
        );
        await _addNotificationDoc(
          userId: userId,
          type: 'dividend',
          symbol: stock['symbol']?.toString() ?? '',
          amountTry: amountTry,
          eventDate: eventDate,
          eventId: eventId,
        );
        await _notificationService.showDividendNotification(
          symbol: stock['symbol']?.toString() ?? '',
          amount: amountTry,
          currency: 'TRY',
        );
      }

      await _markProcessed(stockRef, eventId, {
        'type': 'dividend',
        'date': Timestamp.fromDate(eventDate),
        'amount_per_share': amountPerShare,
        'shares': shares,
        'total_amount_try': amountTry,
        'currency': currency,
      });
    }
  }

  Future<void> _handleSplits({
    required String userId,
    required DocumentReference<Map<String, dynamic>> stockRef,
    required Map<String, dynamic> stock,
    required dynamic events,
  }) async {
    if (events == null) return;
    final Map<String, dynamic> splits = Map<String, dynamic>.from(events);

    for (final entry in splits.entries) {
      final String eventId = 'split_${entry.key}';
      if (await _isProcessed(stockRef, eventId)) continue;

      final Map<String, dynamic> event = Map<String, dynamic>.from(entry.value);
      final int ts = (event['date'] as num? ?? 0).toInt();
      final DateTime eventDate = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      final double ratio = _parseSplitRatio(event);
      final String ratioText = _ratioText(event, ratio);

      if (ratio > 0 && ratio != 1.0) {
        final double shares = (stock['shares'] as num? ?? 0).toDouble();
        final double purchasePrice = (stock['purchase_price'] as num? ?? 0).toDouble();
        final double currentPrice = (stock['current_price'] as num? ?? 0).toDouble();

        await stockRef.update({
          'shares': shares * ratio,
          'purchase_price': purchasePrice / ratio,
          'current_price': currentPrice / ratio,
        });

        await _addNotificationDoc(
          userId: userId,
          type: 'split',
          symbol: stock['symbol']?.toString() ?? '',
          ratioText: ratioText,
          eventDate: eventDate,
          eventId: eventId,
        );
        await _notificationService.showSplitNotification(
          symbol: stock['symbol']?.toString() ?? '',
          ratioText: ratioText,
        );
      }

      await _markProcessed(stockRef, eventId, {
        'type': 'split',
        'date': Timestamp.fromDate(eventDate),
        'ratio': ratio,
        'ratio_text': ratioText,
      });
    }
  }

  double _parseSplitRatio(Map<String, dynamic> event) {
    final num? numerator = event['numerator'];
    final num? denominator = event['denominator'];
    if (numerator != null && denominator != null && denominator != 0) {
      return numerator.toDouble() / denominator.toDouble();
    }
    final String? ratio = event['splitRatio']?.toString();
    if (ratio != null && ratio.contains('/')) {
      final parts = ratio.split('/');
      final double? numPart = double.tryParse(parts[0]);
      final double? denPart = double.tryParse(parts[1]);
      if (numPart != null && denPart != null && denPart != 0) {
        return numPart / denPart;
      }
    }
    return 1.0;
  }

  String _ratioText(Map<String, dynamic> event, double ratio) {
    final String? ratioText = event['splitRatio']?.toString();
    if (ratioText != null && ratioText.contains('/')) {
      return ratioText.replaceAll('/', ':');
    }
    if (ratio > 0) {
      return ratio.toStringAsFixed(2);
    }
    return 'N/A';
  }

  Future<DocumentReference<Map<String, dynamic>>?> _resolveStockRef(
    String userId,
    Map<String, dynamic> stock,
  ) async {
    final portfolioRef = FirebaseFirestore.instance
        .collection('usernames')
        .doc(userId)
        .collection('portfolio');

    final String? docId = stock['docId']?.toString();
    if (docId != null && docId.isNotEmpty) {
      return portfolioRef.doc(docId);
    }

    final symbol = stock['symbol'];
    if (symbol == null) return null;
    final query = await portfolioRef.where('symbol', isEqualTo: symbol).limit(1).get();
    if (query.docs.isEmpty) return null;
    return query.docs.first.reference;
  }

  Future<bool> _isProcessed(
    DocumentReference<Map<String, dynamic>> stockRef,
    String eventId,
  ) async {
    final doc = await stockRef.collection('processed_events').doc(eventId).get();
    return doc.exists;
  }

  Future<void> _markProcessed(
    DocumentReference<Map<String, dynamic>> stockRef,
    String eventId,
    Map<String, dynamic> data,
  ) async {
    await stockRef.collection('processed_events').doc(eventId).set({
      ...data,
      'processed_at': Timestamp.now(),
    });
  }

  Future<void> _addNotificationDoc({
    required String userId,
    required String type,
    required String symbol,
    required DateTime eventDate,
    required String eventId,
    double? amountTry,
    String? ratioText,
  }) async {
    await FirebaseFirestore.instance
        .collection('usernames')
        .doc(userId)
        .collection('notifications')
        .add({
      'type': type,
      'symbol': symbol,
      'amount_try': amountTry,
      'ratio_text': ratioText,
      'event_date': Timestamp.fromDate(eventDate),
      'created_at': Timestamp.now(),
      'event_id': eventId,
      'read': false,
    });
  }
}
