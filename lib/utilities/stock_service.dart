import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class StockService {
  // Kategorilere göre sembol listeleri
  final Map<String, List<String>> categories = {
    'Popüler': ['AAPL', 'TSLA', 'NVDA', 'AMZN', 'MSFT', 'META', 'NFLX', 'GME'],
    'Kripto': ['BTC-USD', 'ETH-USD', 'DOGE-USD', 'SOL-USD', 'AVAX-USD', 'XRP-USD'],
    'ETF': ['VOO', 'QQQ', 'SPY', 'VTI', 'ARKK', 'SCHD'],
    'Döviz & Altın': ['EURUSD=X', 'GBPUSD=X', 'JPY=X', 'TRY=X', 'XAU=X', 'GC=F'],
  };

  // İsim Haritası
  final Map<String, String> _nameMap = {
    'AAPL': 'Apple Inc.', 'TSLA': 'Tesla Inc.', 'NVDA': 'NVIDIA Corp.',
    'AMZN': 'Amazon.com', 'MSFT': 'Microsoft', 'META': 'Meta Platforms',
    'NFLX': 'Netflix', 'GME': 'GameStop',
    'BTC-USD': 'Bitcoin', 'ETH-USD': 'Ethereum', 'DOGE-USD': 'Dogecoin',
    'SOL-USD': 'Solana', 'AVAX-USD': 'Avalanche', 'XRP-USD': 'XRP',
    'VOO': 'Vanguard S&P 500', 'QQQ': 'Invesco QQQ', 'SPY': 'SPDR S&P 500',
    'VTI': 'Vanguard Total Stock', 'ARKK': 'ARK Innovation', 'SCHD': 'Schwab US Dividend',
    'EURUSD=X': 'Euro / USD', 'GBPUSD=X': 'GBP / USD',
    'JPY=X': 'Japon Yeni', 'TRY=X': 'Türk Lirası',
    'XAU=X': 'Altın (Ons)', 'GC=F': 'Altın Vadeli'
  };

  // 1. KEŞFET EKRANI İÇİN (Kategoriye göre)
  Future<List<Map<String, dynamic>>> getStockData(String category) async {
    List<String> symbols = categories[category] ?? [];
    return await _fetchSymbols(symbols);
  }

  // 2. PORTFÖY İÇİN (Verilen listeye göre - YENİ ÖZELLİK)
  Future<List<Map<String, dynamic>>> getQuotesForSymbols(List<String> symbols) async {
    return await _fetchSymbols(symbols);
  }

  // Ortak Veri Çekme Motoru
  Future<List<Map<String, dynamic>>> _fetchSymbols(List<String> symbols) async {
    if (symbols.isEmpty) return [];

    List<Future<Map<String, dynamic>?>> futures = symbols.map((symbol) async {
      try {
        final url = Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=1d&range=1d');
        
        final response = await http.get(url, headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        });

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['chart']['result'] == null || data['chart']['result'].isEmpty) {
            return null;
          }

          final meta = data['chart']['result'][0]['meta'];
          double currentPrice = (meta['regularMarketPrice'] as num).toDouble();
          double previousClose = (meta['chartPreviousClose'] as num).toDouble();
          double change = currentPrice - previousClose;
          double percentChange = (change / previousClose) * 100;

          // Sembol temizliği
          String cleanSymbol = symbol.replaceAll('-USD', '').replaceAll('=X', '');

          return {
            'symbol': cleanSymbol,
            'rawSymbol': symbol,
            'price': currentPrice,
            'change': change,
            'percentChange': percentChange,
            'name': _nameMap[symbol] ?? cleanSymbol, 
          };
        } else {
          return null;
        }
      } catch (e) {
        return null;
      }
    }).toList();

    final results = await Future.wait(futures);
    return results.whereType<Map<String, dynamic>>().toList();
  }
  // ---------------------------------------------------------------------------
  // 3. ARAMA MOTORU (YENİ ÖZELLİK)
  // Kullanıcı "thy" yazınca "THYAO.IS" bulmasını sağlayan fonksiyon
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> searchStocks(String query) async {
    if (query.isEmpty) return [];

    try {
      // Yahoo'nun arama servisi (Autocomplete)
      final url = Uri.parse('https://query1.finance.yahoo.com/v1/finance/search?q=$query&quotesCount=10&newsCount=0');
      
      final response = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> quotes = data['quotes'];

        return quotes.map((item) {
          return {
            'symbol': item['symbol'],      // Örn: THYAO.IS
            'shortname': item['shortname'] ?? item['longname'] ?? item['symbol'], // Örn: Turk Hava Yollari
            'exchange': item['exchDisp'],  // Örn: Istanbul
            'type': item['quoteType'],     // Örn: EQUITY (Hisse)
          };
        }).toList();
      } else {
        return [];
      }
    } catch (e) {
      debugPrint("Arama Hatası: $e");
      return [];
    }
  }
// 4. DÖVİZ KURU ÇEKME (DÜZELTİLMİŞ & GARANTİ VERSİYON)
  // Diğer fonksiyonlardan bağımsız, sadece fiyata odaklanır.
  Future<double> getExchangeRate() async {
    try {
      // 'TRY=X' yerine 'USDTRY=X' kullanıyoruz (Daha standart)
      final url = Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/USDTRY=X?interval=1d&range=1d');
      
      final response = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Veri yapısı kontrolü
        if (data['chart']['result'] == null || data['chart']['result'].isEmpty) {
           debugPrint("Kur verisi boş geldi, varsayılan dönülüyor.");
           return 35.0;
        }

        final meta = data['chart']['result'][0]['meta'];
        
        // Sadece fiyatı alıyoruz, diğer hesaplamalara girmiyoruz
        if (meta.containsKey('regularMarketPrice')) {
           final price = (meta['regularMarketPrice'] as num).toDouble();
           debugPrint("Güncel Dolar Kuru Çekildi: $price");
           return price;
        }
      }
      
      debugPrint("Kur API yanıt vermedi, varsayılan dönülüyor.");
      return 35.0; // API hatası durumunda
      
    } catch (e) {
      debugPrint("Kur çekilirken KRİTİK HATA: $e");
      return 35.0; // İnternet yoksa veya kod kırılırsa
    }
  }
}
