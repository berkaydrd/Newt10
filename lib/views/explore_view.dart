import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_newtten/views/other_user_profile_view.dart'; // Firestore için gerekli
import 'package:flutter_application_newtten/widgets/leaderboard_frame.dart';
import 'package:flutter_application_newtten/widgets/popular_stocks_ticker_frame.dart';

class ExploreView extends StatefulWidget {
  const ExploreView({super.key});

  @override
  State<ExploreView> createState() => _ExploreViewState();
}

class _ExploreViewState extends State<ExploreView> with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];

  @override
  bool get wantKeepAlive => true;

  void _onSearchChanged(String query) {

    String cleanQuery = query.toLowerCase().trim(); // Sorguyu küçültüyoruz

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.isEmpty) {
        setState(() { _isSearching = false; _searchResults = []; });
        return;
      }

      setState(() => _isSearching = true);
      
      try {
        print("Sorgu başlatılıyor: $query");
        final results = await FirebaseFirestore.instance
            .collection('usernames')
            .where('username', isGreaterThanOrEqualTo: cleanQuery)
            .where('username', isLessThanOrEqualTo: cleanQuery + '\uf8ff')
            .get();
        
        print("Gelen sonuç sayısı: ${results.docs.length}");

        if (mounted) {
          setState(() {
            _searchResults = results.docs.map((doc) => doc.data()).toList();
          });
        }
      } catch (e) {
        print("ARAMA HATASI: $e"); // Hata varsa burada yazar
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Keşfet", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      body: Column(
        children: [
          // 1. KULLANICI ARAMA KUTUSU
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300)
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  icon: const Icon(Icons.person_search, color: Colors.grey),
                  suffixIcon: _searchController.text.isNotEmpty 
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : null,
                  border: InputBorder.none,
                  hintText: "Kullanıcı ara...",
                ),
              ),
            ),
          ),

          // ARAMA SONUÇLARI (KULLANICI LİSTESİ)
          if (_isSearching)
            Expanded(
              child: _searchResults.isEmpty
                  ? const Center(child: Text("Yatırımcı bulunamadı..."))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _searchResults.length,
                      separatorBuilder: (ctx, i) => const Divider(height: 1, color: Colors.black12),
                      itemBuilder: (context, index) {
                        final user = _searchResults[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blueGrey[100],
                            backgroundImage: user['photoUrl'] != null 
                                ? NetworkImage(user['photoUrl']) 
                                : null,
                            child: user['photoUrl'] == null 
                                ? const Icon(Icons.person, color: Colors.white) 
                                : null,
                          ),
                          title: Text(user['username'] ?? "İsimsiz Yatırımcı", 
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text("TWR Grafiğini gör"), // İstediğin kısıtlı bilgi
                          trailing: const Icon(Icons.chevron_right, size: 20),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => OtherUserProfileView(userData: user),
                              ),  
                            );
                          },
                        );
                      },
                    ),
            )
          
          // LİDERLİK TABLOSU (3. MADDE TEMELİ)
          else ...[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: const [
                    LeaderboardFrame(),
                    SizedBox(height: 16),
                    PopularStocksTickerFrame(),
                  ],
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }
}
