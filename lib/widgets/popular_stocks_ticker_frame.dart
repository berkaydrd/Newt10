import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_newtten/utilities/firestore_service.dart';

class PopularStocksTickerFrame extends StatefulWidget {
  final double height;
  final double itemWidth;
  final Duration scrollDurationPerItem;

  const PopularStocksTickerFrame({
    super.key,
    this.height = 160.0,
    this.itemWidth = 100.0,
    this.scrollDurationPerItem = const Duration(seconds: 2),
  });

  @override
  State<PopularStocksTickerFrame> createState() =>
      _PopularStocksTickerFrameState();
}

class _PopularStocksTickerFrameState extends State<PopularStocksTickerFrame>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  // ignore: unused_field
  int _currentDataLength = 0;
  Stream<List<Map<String, dynamic>>>? _stocksStream;
  List<Map<String, dynamic>>? _currentEntries;

  @override
  void initState() {
    super.initState();
    _stocksStream = FirestoreService.getPopularStocksStream();
    _initControllerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant PopularStocksTickerFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Stream is internal, no need to check widget changes
  }

  void _initControllerIfNeeded() {
    if (_currentEntries == null || _currentEntries!.isEmpty) {
      _controller?.stop();
      return;
    }

    final length = _currentEntries!.length;
    _currentDataLength = length;

    // Duration based on unique width and a gentle scroll speed (~50 px/sec)
    final uniqueWidth = length * widget.itemWidth;
    const scrollSpeedPixelsPerSecond = 50.0;
    final durationMs =
        (uniqueWidth / scrollSpeedPixelsPerSecond * 1000).round();

    _controller?.dispose();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );

    _controller!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller!
          ..reset()
          ..repeat();
      }
    });

    _controller!.repeat();
  }

  @override
  void dispose() {
    try {
      _controller?.dispose();
    } catch (_) {}
    _controller = null;
    _currentEntries = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stocksStream,
      builder: (context, snapshot) {
        // Handle loading state
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _buildLoading();
        }

        // Handle error state
        if (snapshot.hasError) {
          debugPrint('PopularStocksTicker error: ${snapshot.error}');
          return _buildError(snapshot.error);
        }

        // Handle empty state
        final data = snapshot.data ?? [];
        if (data.isEmpty) {
          return _buildEmpty();
        }

        // Filter out entries missing the required 'symbol' field
        final validEntries = data.where((entry) {
          final symbol = entry['symbol'];
          if (symbol is String && symbol.isNotEmpty) {
            return true;
          }
          debugPrint(
              '[PopularStocksTicker] Skipping entry with missing/invalid symbol: $entry');
          return false;
        }).toList();

        if (validEntries.isEmpty) {
          return _buildEmpty();
        }

        // Update current entries and reinitialize animation if needed
        if (_currentEntries == null || 
            _currentEntries!.length != validEntries.length ||
            !_areEntriesEqual(_currentEntries!, validEntries)) {
          _currentEntries = validEntries;
          _initControllerIfNeeded();
        }

        return _buildTicker(validEntries);
      },
    );
  }

  bool _areEntriesEqual(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i]['symbol'] != b[i]['symbol'] ||
          a[i]['return_24h_pct'] != b[i]['return_24h_pct']) {
        return false;
      }
    }
    return true;
  }

  Widget _buildLoading() {
    return SizedBox(
      height: widget.height,
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildEmpty() {
    return SizedBox(
      height: widget.height,
      child: const Center(
        child: Text(
          'Henüz veri yok.',
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildError(dynamic error) {
    debugPrint('[PopularStocksTicker] Error: $error');
    final errorText = error?.toString() ?? 'Bilinmeyen hata';
    final displayText =
        errorText.length > 80 ? '${errorText.substring(0, 80)}...' : errorText;

    return SizedBox(
      height: widget.height,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade300, size: 28),
            const SizedBox(height: 8),
            Text(
              displayText,
              style: TextStyle(color: Colors.red.shade300, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicker(List<Map<String, dynamic>> entries) {
    final controller = _controller;
    if (controller == null) {
      return _buildEmpty();
    }

    final uniqueWidth = entries.length * widget.itemWidth;
    final duplicated = [...entries, ...entries];

    return SizedBox(
      height: widget.height,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final offset = -controller.value * uniqueWidth;
            return Transform.translate(
              offset: Offset(offset, 0),
              child: child,
            );
          },
          child: OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: duplicated
                  .map((stock) => _buildStockCard(stock))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStockCard(Map<String, dynamic> stock) {
    final symbol = stock['symbol'] as String? ?? '--';
    final name = stock['name'] as String?;
    final logoUrl = stock['logo_url'] as String?;
    final price = stock['price'];
    final returnPct = stock['return_24h_pct'];

    // Parse return percentage
    final double? pctValue =
        returnPct is num ? returnPct.toDouble() : null;
    final String pctText;
    final Color pctColor;

    if (pctValue != null) {
      final sign = pctValue >= 0 ? '+' : '';
      pctText = '$sign${pctValue.toStringAsFixed(2)}%';
      pctColor = _getReturnColor(pctValue);
    } else {
      pctText = '--';
      pctColor = Colors.grey;
    }

    // Parse price for potential display
    // ignore: unused_local_variable
    final String priceText;
    if (price is num) {
      priceText = price.toStringAsFixed(2);
    } else {
      priceText = '--';
    }

    return SizedBox(
      width: widget.itemWidth,
      height: widget.height - 16,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAvatar(logoUrl, symbol),
            const SizedBox(height: 6),
            Text(
              symbol,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (name != null && name.isNotEmpty)
              Text(
                name,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 2),
            Text(
              pctText,
              style: TextStyle(
                color: pctColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String? logoUrl, String symbol) {
    final hasValidUrl = logoUrl != null && logoUrl.isNotEmpty;

    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.grey.shade800,
      child: hasValidUrl
          ? ClipOval(
              child: Image.network(
                logoUrl,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildLetterPlaceholder(symbol);
                },
              ),
            )
          : _buildLetterPlaceholder(symbol),
    );
  }

  Widget _buildLetterPlaceholder(String symbol) {
    return Center(
      child: Text(
        symbol.isNotEmpty ? symbol[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getReturnColor(double pct) {
    return pct >= 0 ? Colors.green : Colors.red;
  }
}
