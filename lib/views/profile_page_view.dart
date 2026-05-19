import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_newtten/utilities/firestore_service.dart';
import 'package:flutter_application_newtten/views/notifications_view.dart';
import 'package:flutter_application_newtten/views/edit_portfolio_view.dart';
import 'package:flutter_application_newtten/views/explore_view.dart';
import 'package:flutter_application_newtten/views/chat_view.dart';
// Yeni Widget'ı eklemeyi unutma
import 'package:flutter_application_newtten/widgets/profile_header_widget.dart';
import 'package:flutter_application_newtten/widgets/portfolio_list_widget.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Stream<List<Map<String, dynamic>>>? _portfolioStream;
  String _username = 'Yükleniyor...';
  String? _profileImagePath;  
  bool _showPieChart = true;
  int _selectedIndex = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _performanceSub;

  // Veri Cache
  List<Map<String, dynamic>> _currentPortfolioData = [];
  final List<Map<String, dynamic>> _fallbackPortfolio = [];

  // Döviz Ayarları
  double _exchangeRate = 35.0;
  String _selectedCurrency = 'TRY';

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  void _loadUsername() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _username = 'Giriş Yapılmadı');
      return;
    }
    try {
      final fetchedUsername = await FirestoreService.getUsername(user.uid);
      final validUsername = fetchedUsername ?? 'Misafir';
      final fetchedImagePath = await FirestoreService.getProfileImagePath(validUsername);
      final newStream = FirestoreService.getPortfolioStream(validUsername).asBroadcastStream();

      if (mounted) {
        setState(() {
          _profileImagePath = fetchedImagePath;
          _username = validUsername;
          _portfolioStream = newStream; 
        });
      }
      _listenPerformanceHistory(validUsername);
    } catch (e) {
      if (mounted) setState(() => _username = 'Hata oluştu');
    }
  }

  void _listenPerformanceHistory(String username) {
    _performanceSub?.cancel();
    _performanceSub = FirestoreService.getPerformanceHistoryStream(username)
        .listen((history) {
      if (history.isEmpty) return;
      final last = history.last;
      final double lastTry = (last['total_value_try'] as num? ?? 0).toDouble();
      final double lastUsd = (last['total_value_usd'] as num? ?? 0).toDouble();
      if (lastUsd <= 0) return;
      final double rate = lastTry / lastUsd;
      if (mounted) setState(() => _exchangeRate = rate);
    });
  }

  // --- OTOMATİK DÖNÜŞTÜRÜCÜ ---
  List<Map<String, dynamic>> _convertPrices(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return [];

    return data.map((item) {
      Map<String, dynamic> convertedItem = Map.from(item);
      
      // Artık tahmin etmiyoruz, merge fonksiyonundan gelen etikete bakıyoruz
      String itemCurrency = item['currency'] ?? 'USD'; 
      
      double originalPrice = (item['current_price'] as num).toDouble();
      double originalCost = (item['purchase_price'] as num).toDouble();

      // MOD: TRY (Her şeyi TL yap)
      if (_selectedCurrency == 'TRY') {
        if (itemCurrency == 'USD') {
          // Dolar olanları TL'ye çevir
          convertedItem['current_price'] = originalPrice * _exchangeRate;
          convertedItem['purchase_price'] = originalCost * _exchangeRate;
        }
        // Zaten TRY olanlara dokunma
      } 
      
      // MOD: USD (Her şeyi Dolar yap)
      else {
        if (itemCurrency == 'TRY') {
          // TL olanları Dolara çevir
          convertedItem['current_price'] = originalPrice / _exchangeRate;
          convertedItem['purchase_price'] = originalCost / _exchangeRate;
        }
        // Zaten USD olanlara dokunma
      }

      return convertedItem;
    }).toList();
  }

  @override
  void dispose() {
    _performanceSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: (_selectedIndex == 1 || _selectedIndex == 3) ? null : _buildAppBar(),
      body: _selectedIndex == 1
          ? const ExploreView()
          : _selectedIndex == 3
              ? const ChatView()
              : _buildProfileContent(),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      foregroundColor: const Color.fromARGB(190, 0, 0, 0),
      shadowColor: Colors.black, 
      elevation: 0.1,
      leadingWidth: 60.0,
      leading: Padding(padding: const EdgeInsets.all(1.0), child: Image.asset('assets/images/Logo.png', width: 65.0, height: 65.0, fit: BoxFit.fill)),
      title: Text(_username, style: const TextStyle(fontWeight: FontWeight.w500)),
      centerTitle: true,
      actions: [
        IconButton(
          onPressed: () {
            if (_username == 'Yükleniyor...' || _username == 'Giriş Yapılmadı') return;
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => NotificationsView(username: _username)),
            );
          },
          icon: const Icon(Icons.notifications_none),
        ),
        TextButton(
          onPressed: () => setState(() => _selectedCurrency = _selectedCurrency == 'TRY' ? 'USD' : 'TRY'),
          child: Text(
            _selectedCurrency == 'TRY' ? 'TL' : 'USD',
            style: TextStyle(fontWeight: FontWeight.bold, color: _selectedCurrency == 'TRY' ? Colors.black : Colors.green[700]),
          ),
        ),
        IconButton(onPressed: (){}, icon: const Icon(Icons.settings_suggest_outlined))
      ],
    );
  }

  Widget _buildBottomNavBar() {
    return Theme(
      data: Theme.of(context).copyWith(splashColor: Colors.transparent, highlightColor: Colors.grey),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          if (index == 2) {
            if (_selectedIndex == 1) {
              setState(() { _selectedIndex = 0; _showPieChart = !_showPieChart; });
            } else {
              setState(() => _showPieChart = !_showPieChart);
            }
          } else {
            setState(() => _selectedIndex = index);
          }
        },
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home', backgroundColor: Colors.black),
          const BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Keşfet'),
          BottomNavigationBarItem(icon: Icon(_showPieChart ? Icons.line_axis : Icons.pie_chart), label: 'Grafik'),
          const BottomNavigationBarItem(icon: Icon(Icons.smart_toy_outlined), label: 'AI'),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    if (_portfolioStream == null) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _portfolioStream,
      initialData: _currentPortfolioData.isNotEmpty ? _currentPortfolioData : null,
      builder: (context, snapshot) {
        final List<Map<String, dynamic>> firestoreData = snapshot.data ?? [];

        if (firestoreData.isNotEmpty) {
          _currentPortfolioData = firestoreData;
        }

        final displayData = _convertPrices(_currentPortfolioData);

        return Column(
          children: [
            ProfileHeaderWidget(
              username: _username,
              profileImagePath: _profileImagePath,
              onImageSelected: (newPath) => setState(() => _profileImagePath = newPath),
              showPieChart: _showPieChart,
              displayData: displayData,
              fallbackPortfolio: _fallbackPortfolio,
              selectedCurrency: _selectedCurrency,
            ),
            
            // 2. DÜZENLE BUTONU
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 900), 
                    reverseTransitionDuration: const Duration(milliseconds: 900),
                    pageBuilder: (context, animation, secondaryAnimation) => EditPortfolioPage(
                      username: _username.toLowerCase(),
                      initialPortfolio: _currentPortfolioData,
                      profileImageUrl: _profileImagePath,
                      currentExchangeRate: _exchangeRate,
                    ),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      var slideTween = Tween(begin: const Offset(0.0, 0.1), end: Offset.zero).chain(CurveTween(curve: Curves.easeOut));
                      var fadeTween = Tween<double>(begin: 0.0, end: 1.0);
                      return SlideTransition(
                        position: animation.drive(slideTween),
                        child: FadeTransition(opacity: animation.drive(fadeTween), child: child),
                      );
                    },
                  ),
                );
              },
              style: TextButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 120, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Portföyü Düzenle', style: TextStyle(fontSize: 13.0)),
            ),
            
            const SizedBox(height: 10),
            const Divider(height: 1, thickness: 0.5, color: Color.fromARGB(60, 0, 0, 0)),
            
            // 3. LİSTE
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: PortfolioListWidget(
                      portfolio: displayData,
                      currencySymbol: _selectedCurrency == 'TRY' ? '₺' : '\$',
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
