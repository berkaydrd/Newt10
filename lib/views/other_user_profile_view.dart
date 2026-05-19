import 'package:flutter/material.dart';
import 'package:flutter_application_newtten/utilities/firestore_service.dart';
import 'package:flutter_application_newtten/widgets/performance_history_chart_widget.dart';
import 'package:flutter_application_newtten/widgets/profile_header_widget.dart';
import 'package:flutter_application_newtten/widgets/portfolio_list_widget.dart';

class OtherUserProfileView extends StatefulWidget {
  final Map<String, dynamic> userData;

  const OtherUserProfileView({super.key, required this.userData});

  @override
  State<OtherUserProfileView> createState() => _OtherUserProfileViewState();
}

class _OtherUserProfileViewState extends State<OtherUserProfileView> {
  // Durum Yönetimi
  bool _isFollowing = false;
  bool _isSubscribed = false; // Bu veri ileride veritabanından kontrol edilecek
  bool _showPieChart = false; // Başlangıçta TWR grafiğini göstermek için false yaptık
  String _selectedCurrency = 'TRY';

  // Veri
  List<Map<String, dynamic>> _portfolioData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _isLoading = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : _buildProfileContent(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.1,
      iconTheme: const IconThemeData(color: Colors.black),
      title: Text(widget.userData['username'] ?? "Profil", 
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      centerTitle: true,
      actions: [
        TextButton(
          onPressed: () => setState(() => _selectedCurrency = _selectedCurrency == 'TRY' ? 'USD' : 'TRY'),
          child: Text(
            _selectedCurrency == 'TRY' ? 'TL' : 'USD',
            style: TextStyle(fontWeight: FontWeight.bold, color: _selectedCurrency == 'TRY' ? Colors.black : Colors.green[700]),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileContent() {
    final String username = (widget.userData['username'] ?? '').toString();
    final Stream<List<Map<String, dynamic>>> performanceStream =
        FirestoreService.getPerformanceHistoryStream(username);

    final Widget performanceChart = StreamBuilder<List<Map<String, dynamic>>>(
      stream: performanceStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SizedBox(
            height: 200,
            child: Center(child: Text("Grafik verisi alınamadı")),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final data = snapshot.data ?? const <Map<String, dynamic>>[];
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: FirestoreService.getTempHourlySnapshotsStream(username),
          builder: (context, tempSnapshot) {
            if (tempSnapshot.hasError) {
              return PerformanceHistoryChartWidget(
                key: const ValueKey('line_perf'),
                performanceHistory: data,
              );
            }
            final tempData =
                tempSnapshot.data ?? const <Map<String, dynamic>>[];
            return PerformanceHistoryChartWidget(
              key: const ValueKey('line_perf'),
              performanceHistory: data,
              tempSnapshots: tempData,
            );
          },
        );
      },
    );

    return Column(
      children: [
        // 1. HEADER (Resim, Takipçi ve Grafikler)
        ProfileHeaderWidget(
          username: username,
          profileImagePath: widget.userData['profile_image_path'],
          onImageSelected: (_) {}, // Başkasının resmini değiştiremez
          showPieChart: _showPieChart && _isSubscribed, // Sadece aboneyse Pie Chart'a izin ver
          displayData: _isSubscribed ? _portfolioData : [],
          fallbackPortfolio: const [],
          selectedCurrency: _selectedCurrency,
          chartOverride: performanceChart,
        ),

        // 2. AKSİYON BUTONLARI (Takip Et & Abone Ol)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          child: Row(
            children: [
              // TAKİP ET BUTONU
              Expanded(
                child: ElevatedButton(
                  onPressed: () => setState(() => _isFollowing = !_isFollowing),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isFollowing ? Colors.grey[200] : Colors.black,
                    foregroundColor: _isFollowing ? Colors.black : Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(_isFollowing ? 'Takibi Bırak' : 'Takip Et', 
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              // ABONE OL BUTONU
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    // Abonelik işlemlerini başlat
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    side: const BorderSide(color: Colors.black, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Abone Ol', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),
        const Divider(height: 1, thickness: 0.5, color: Color.fromARGB(60, 0, 0, 0)),

        // 3. ALT KISIM (Liste veya Kilit Mesajı)
        Expanded(
          child: _isSubscribed 
              ? PortfolioListWidget(
                  portfolio: _portfolioData,
                  currencySymbol: _selectedCurrency == 'TRY' ? '₺' : '\$',
                )
              : _buildLockedOverlay(),
        ),
      ],
    );
  }

  Widget _buildLockedOverlay() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text(
              "Portföy Detayları Kilitli",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Kullanıcının güncel hisselerini ve alım-satım stratejilerini görmek için abone olmalısın.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
