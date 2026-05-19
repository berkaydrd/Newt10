import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class CompanyLogo extends StatelessWidget {
  static const double _size = 40;

  final String? logoUrl;
  final String symbol;

  const CompanyLogo({
    super.key,
    required this.logoUrl,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedSymbol = symbol.trim();
    final fallbackChar =
        trimmedSymbol.isNotEmpty ? trimmedSymbol[0].toUpperCase() : "?";
    final safeUrl = logoUrl?.trim();

    return SizedBox.square(
      dimension: _size,
      child: ClipOval(
        child: (safeUrl == null || safeUrl.isEmpty)
            ? _buildFallback(fallbackChar)
            : CachedNetworkImage(
                imageUrl: safeUrl,
                fit: BoxFit.contain,
                cacheKey: safeUrl,
                placeholder: (context, url) => _buildPlaceholder(),
                errorWidget: (context, url, error) =>
                    _buildFallback(fallbackChar),
              ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return const CircleAvatar(
      backgroundColor: Color(0xFFE0E0E0),
    );
  }

  Widget _buildFallback(String initial) {
    return CircleAvatar(
      backgroundColor: const Color(0xFFE0E0E0),
      child: Text(
        initial,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.black54,
        ),
      ),
    );
  }
}
