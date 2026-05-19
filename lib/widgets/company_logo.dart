import 'package:flutter/material.dart';

class CompanyLogo extends StatelessWidget {
  final String? logoUrl;
  final double size;
  final String? fallbackAssetPath;

  const CompanyLogo({
    required this.logoUrl,
    this.size = 32.0,
    this.fallbackAssetPath,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // URL null veya boşsa hemen yedek (yuvarlak) ikonu göster
    if (logoUrl == null || logoUrl!.isEmpty) {
      return _buildFallbackIcon();
    }

    // Ağı (Network) resmini ClipOval ile tam yuvarlak çiziyoruz
    return ClipOval(
      child: Image.network(
        logoUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: size.toInt(),
        cacheHeight: size.toInt(),
        loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (BuildContext context, Object exception, StackTrace? stackTrace) {
          if (fallbackAssetPath != null && fallbackAssetPath!.isNotEmpty) {
            return ClipOval(
              child: Image.asset(
                fallbackAssetPath!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (BuildContext context, Object exception, StackTrace? stackTrace) {
                  return _buildFallbackIcon();
                },
              ),
            );
          }
          return _buildFallbackIcon();
        },
      ),
    );
  }

  Widget _buildFallbackIcon() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        shape: BoxShape.circle, // <-- Köşeli borderRadius yerine tam yuvarlak şekil
      ),
      child: Center(
        child: Icon(
          Icons.business,
          size: size * 0.5, // İkon boyutunu widget'a göre orantılı yaptık
          color: Colors.grey,
        ),
      ),
    );
  }
}
