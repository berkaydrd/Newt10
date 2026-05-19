import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_newtten/utilities/firestore_service.dart' as FirestoreService;
import 'package:flutter_application_newtten/utilities/stock_service.dart'; 
import 'package:flutter_application_newtten/widgets/portfolio_donut_chart_with_pp_widget.dart';

class EditPortfolioPage extends StatefulWidget {
  final String username;
  final List<Map<String, dynamic>>? initialPortfolio; 
  final String? profileImageUrl;
  final double currentExchangeRate; 

  const EditPortfolioPage({
    super.key, 
    required this.username,
    this.initialPortfolio,
    this.profileImageUrl,
    required this.currentExchangeRate, 
  });

  @override
  State<EditPortfolioPage> createState() => _EditPortfolioPageState();
}

class _EditPortfolioPageState extends State<EditPortfolioPage> {
  final StockService _stockService = StockService();

  String _selectedSymbol = "";
  final _sharesController = TextEditingController();
  final _priceController = TextEditingController();
  
  bool _isSellMode = false;
  Color _selectedColor = Colors.blue; 
  
  double _exchangeRate = 35.0; 

  final List<Color> _colorPalette = [
    Colors.red, Colors.blue, Colors.green, Colors.orange, 
    Colors.purple, Colors.teal, Colors.pink, Colors.amber,
    Colors.indigo, Colors.brown, Colors.cyan, Colors.deepOrange,
    Colors.lime, Colors.blueGrey, Colors.black, Colors.grey
  ];

  @override
  void initState() {
    super.initState();
    _exchangeRate = widget.currentExchangeRate;
    _fetchExchangeRate(); 
  }

  void _fetchExchangeRate() async {
    double rate = await _stockService.getExchangeRate();
    if (mounted) setState(() => _exchangeRate = rate);
  }

  Future<List<Map<String, dynamic>>> _mergePortfolioWithLiveData(List<Map<String, dynamic>> firestoreData) async {
    if (firestoreData.isEmpty) return [];

    List<String> querySymbols = [];
    for (var item in firestoreData) {
      String rawSymbol = item['symbol'];
      querySymbols.add(rawSymbol);          
    }

    List<Map<String, dynamic>> liveData = await _stockService.getQuotesForSymbols(querySymbols);

    return firestoreData.map((stock) {
      String symbol = stock['symbol'];
      
      var liveStock = liveData.firstWhere(
        (element) => element['symbol'] == symbol || element['rawSymbol'] == symbol,
        orElse: () => {}, 
      );
      
      String currency = 'USD';
      
      // Veritabanındaki currency'ye öncelik ver ama SEMBOL .IS İSE ZORLA TRY YAP
      if (symbol.contains('.IS')) {
        currency = 'TRY';
      } else if (stock.containsKey('currency') && stock['currency'] != null) {
        currency = stock['currency'];
      }

      double currentPrice = 0.0;
      if (liveStock.isNotEmpty) {
        currentPrice = (liveStock['price'] as num).toDouble();
      } else {
        currentPrice = (stock['current_price'] as num? ?? stock['purchase_price'] as num? ?? 0.0).toDouble();
      }
      
      double shares = (stock['shares'] as num? ?? 0).toDouble();
      double purchasePrice = (stock['purchase_price'] as num? ?? 0).toDouble();

      return {
        'symbol': symbol,
        'shares': shares,
        'purchase_price': purchasePrice,
        'current_price': currentPrice,
        'color': stock['color'],
        'logo_url': stock['logo_url'],
        'currency': currency, 
      };
    }).toList();
  }

  List<Map<String, dynamic>> _normalizeForChart(List<Map<String, dynamic>> data) {
    return data.map((item) {
      Map<String, dynamic> converted = Map.from(item);
      String currency = item['currency'] ?? 'USD';
      
      double price = (item['current_price'] as num).toDouble();
      
      // Sadece USD ise kurla çarp
      if (currency == 'USD') {
        converted['current_price'] = price * _exchangeRate;
      }
      
      return converted;
    }).toList();
  }

  void _openColorPicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Bir Renk Seçin'),
          content: SingleChildScrollView(
            child: Wrap(
              spacing: 10, runSpacing: 10,
              children: _colorPalette.map((color) {
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedColor = color);
                    Navigator.of(context).pop();
                  },
                  child: Container(width: 50, height: 50, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300, width: 1))),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // --- 🔥 KESİN ÇÖZÜM BURADA 🔥 ---
  void _handleTransaction(List<Map<String, dynamic>> currentPortfolio) async {
    if (_selectedSymbol.isEmpty || _sharesController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen listeden bir hisse seçin ve adet girin.')));
      return;
    }

    String symbol = _selectedSymbol.toUpperCase().trim();
    
    // 1. ZORLAYICI PARA BİRİMİ KURALI
    // Arayüzden ne gelirse gelsin, sembol .IS ise o hisse TRY'dir. Nokta.
    String finalCurrency = 'USD'; // Varsayılan
    if (symbol.contains('.IS')) {
      finalCurrency = 'TRY';
    }

    double inputShares = double.tryParse(_sharesController.text) ?? 0;
    double price = double.tryParse(_priceController.text) ?? 1.0;

    double transactionValue = inputShares * price;
    
    // Nakit Akışı Hesabı (Belirlenen kesin kura göre)
    double cashFlowAmountTRY = (finalCurrency == 'TRY') ? transactionValue : (transactionValue * _exchangeRate);

    var existingStock = currentPortfolio.firstWhere(
      (element) => element['symbol'] == symbol, 
      orElse: () => {},
    );

    double currentShares = 0;
    if (existingStock.isNotEmpty) {
      currentShares = (existingStock['shares'] as num).toDouble();
    }

    if (_isSellMode) {
      // SATIŞ
      if (existingStock.isEmpty || currentShares <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Portföyünüzde satacak bu hisse yok!')));
        return;
      }
      if (inputShares > currentShares) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Elinizde bu kadar hisse yok!')));
        return;
      }
      
      double newShares = currentShares - inputShares;
      
      if (newShares <= 0) {
        await FirestoreService.FirestoreService.deleteStockFromPortfolio(widget.username, symbol);
      } else {
        final stockData = {
          'symbol': symbol,
          'shares': -inputShares, 
          'purchase_price': (existingStock['purchase_price'] as num).toDouble(), 
          'current_price': price,
          'color': existingStock['color'],
          'currency': finalCurrency, // Eskisine bakma, doğrusunu yaz!
        };
        await FirestoreService.FirestoreService.addStockToPortfolio(widget.username, stockData);
      }

      await FirestoreService.FirestoreService.recordCashFlow(
        widget.username,
        cashFlowAmountTRY,
        'withdrawal',
        currency: finalCurrency,
        amountCurrency: transactionValue,
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$symbol Satışı Başarılı!')));

    } else {
      // ALIŞ
      int colorToSave = existingStock.isNotEmpty ? existingStock['color'] : _selectedColor.value;
      
      final stockData = {
        'symbol': symbol,
        'shares': inputShares,
        'purchase_price': price, 
        'current_price': price,
        'color': colorToSave,
        'currency': finalCurrency, // Eskisine bakma, doğrusunu yaz!
      };
      
      // Burada addStockToPortfolio fonksiyonu, eğer hisse varsa üzerine yazar (update eder).
      // Böylece eski hatalı "USD" kaydı "TRY" olarak düzelir.
      await FirestoreService.FirestoreService.addStockToPortfolio(widget.username, stockData);
      await FirestoreService.FirestoreService.recordCashFlow(
        widget.username,
        cashFlowAmountTRY,
        'deposit',
        currency: finalCurrency,
        amountCurrency: transactionValue,
      );

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alış İşlemi Başarılı!')));
    }

    setState(() {
      _selectedSymbol = "";
      _sharesController.clear();
      _priceController.clear();
      _selectedColor = Colors.blue;
      FocusScope.of(context).unfocus(); 
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Portföyü Düzenle'), centerTitle: true),
      body: SingleChildScrollView( 
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              StreamBuilder<List<Map<String, dynamic>>>(
                initialData: widget.initialPortfolio, 
                stream: FirestoreService.FirestoreService.getPortfolioStream(widget.username),
                builder: (context, snapshot) {
                  final rawPortfolio = snapshot.hasData ? snapshot.data! : <Map<String, dynamic>>[];

                    return FutureBuilder<List<Map<String, dynamic>>>(
                      future: (widget.initialPortfolio != null && 
                              widget.initialPortfolio!.isNotEmpty && 
                              widget.initialPortfolio!.first.containsKey('currency'))
                          ? Future.value(widget.initialPortfolio) 
                          : _mergePortfolioWithLiveData(rawPortfolio), 

                      initialData: widget.initialPortfolio ?? rawPortfolio, 
                      builder: (context, liveSnapshot) {
                          
                      final displayData = liveSnapshot.data ?? rawPortfolio;
                      final chartData = _normalizeForChart(displayData);

                      return Column(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Hero(
                                tag: 'portfolio_chart_hero',
                                child: Material(
                                  color: Colors.transparent, 
                                  child: PortfolioDonutChart(
                                    portfolio: chartData, 
                                    centerWidget: const SizedBox.shrink(), 
                                  ),
                                ),
                              ),
                              Hero(
                                tag: 'profile_image_hero',
                                child: Material(
                                  color: Colors.transparent,
                                  child: CircleAvatar(
                                    radius: 55,
                                    backgroundColor: Colors.grey.shade200,
                                    backgroundImage: widget.profileImageUrl != null 
                                      ? CachedNetworkImageProvider(widget.profileImageUrl!) 
                                      : null,
                                    child: widget.profileImageUrl == null 
                                      ? Text(widget.username.isNotEmpty ? widget.username[0].toUpperCase() : '?', style: const TextStyle(fontSize: 30, color: Colors.black, fontWeight: FontWeight.bold)) 
                                      : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 30),

                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))], border: Border.all(color: Colors.grey.shade200)),
                            child: Column(
                              children: [
                                // Toggle (Alış/Satış)
                                Container(height: 45, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(25)), child: Stack(children: [AnimatedAlign(duration: const Duration(milliseconds: 250), curve: Curves.decelerate, alignment: _isSellMode ? Alignment.centerRight : Alignment.centerLeft, child: FractionallySizedBox(widthFactor: 0.5, child: Container(margin: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)])))), Row(children: [Expanded(child: GestureDetector(onTap: () => setState(() => _isSellMode = false), child: Container(color: Colors.transparent, alignment: Alignment.center, child: Text("ALIŞ", style: TextStyle(fontWeight: FontWeight.bold, color: !_isSellMode ? Colors.green[700] : Colors.grey))))), Expanded(child: GestureDetector(onTap: () => setState(() => _isSellMode = true), child: Container(color: Colors.transparent, alignment: Alignment.center, child: Text("SATIŞ", style: TextStyle(fontWeight: FontWeight.bold, color: _isSellMode ? Colors.red[700] : Colors.grey)))))])])),
                                const SizedBox(height: 20),
                                
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    return Autocomplete<Map<String, dynamic>>(
                                      optionsBuilder: (TextEditingValue textEditingValue) async {
                                        if (textEditingValue.text.length < 2) {
                                          return const Iterable<Map<String, dynamic>>.empty();
                                        }
                                        return await _stockService.searchStocks(textEditingValue.text);
                                      },
                                      displayStringForOption: (Map<String, dynamic> option) => option['symbol'],
                                      
                                      onSelected: (Map<String, dynamic> selection) async {
                                        String symbol = selection['symbol'];
                                        
                                        setState(() {
                                          _selectedSymbol = symbol;
                                        });

                                        List<Map<String, dynamic>> priceData = await _stockService.getQuotesForSymbols([_selectedSymbol]);
                                        if(priceData.isNotEmpty) {
                                          setState(() {
                                            _priceController.text = priceData[0]['price'].toString();
                                          });
                                        }
                                      },
                                      
                                      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                                        return TextField(
                                          controller: textController,
                                          focusNode: focusNode,
                                          onChanged: (val) {
                                            _selectedSymbol = val;
                                          },
                                          decoration: const InputDecoration(
                                            labelText: 'Hisse Ara (Örn: thy, asels)',
                                            border: OutlineInputBorder(),
                                            prefixIcon: Icon(Icons.search),
                                            helperText: "Listeden seçerseniz fiyat otomatik gelir",
                                          ),
                                        );
                                      },
                                      optionsViewBuilder: (context, onSelected, options) {
                                        return Align(
                                          alignment: Alignment.topLeft,
                                          child: Material(
                                            elevation: 4.0,
                                            child: SizedBox(
                                              width: constraints.maxWidth,
                                              height: 200,
                                              child: ListView.builder(
                                                padding: EdgeInsets.zero,
                                                itemCount: options.length,
                                                itemBuilder: (BuildContext context, int index) {
                                                  final option = options.elementAt(index);
                                                  return ListTile(
                                                    title: Text(option['symbol'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                                    subtitle: Text("${option['shortname']} • ${option['exchange']}"),
                                                    onTap: () => onSelected(option),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  }
                                ),

                                const SizedBox(height: 15),
                                Row(children: [Expanded(child: TextField(controller: _sharesController, decoration: const InputDecoration(labelText: 'Adet', border: OutlineInputBorder()), keyboardType: TextInputType.number)), const SizedBox(width: 15), Expanded(child: TextField(controller: _priceController, decoration: const InputDecoration(labelText: 'Fiyat', border: OutlineInputBorder(), hintText: '1.0'), keyboardType: TextInputType.number))]),
                                AnimatedSize(duration: const Duration(milliseconds: 300), child: _isSellMode ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 15), child: GestureDetector(onTap: _openColorPicker, child: Container(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(5)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Grafik Rengi:", style: TextStyle(fontSize: 16)), Row(children: [Container(width: 30, height: 30, decoration: BoxDecoration(color: _selectedColor, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300))), const SizedBox(width: 10), const Icon(Icons.arrow_drop_down)])]))))),
                                const SizedBox(height: 20),
                                SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: () => _handleTransaction(rawPortfolio), style: ElevatedButton.styleFrom(backgroundColor: _isSellMode ? Colors.red[700] : Colors.black, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(_isSellMode ? 'SATIŞ YAP' : 'PORTFÖYE EKLE', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
