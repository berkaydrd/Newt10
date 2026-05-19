import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_newtten/utilities/firestore_service.dart';

class ChatView extends StatefulWidget {
  final String username;
  const ChatView({super.key, required this.username});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _systemPrompt = '';
  final List<({String text, bool isUser})> _messages = [];
  bool _isLoading = false;
  bool _isInitializing = true;

  String get _historyKey => 'chat_history_${widget.username}';
  String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';
  static const String _geminiModel = 'gemini-2.5-flash';

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    await _loadHistory();

    String portfolioContext = '';
    try {
      final portfolio = await FirestoreService.getPortfolioStream(widget.username).first;
      if (portfolio.isNotEmpty) {
        final lines = portfolio.map((s) {
          final symbol = s['symbol'] ?? '';
          final shares = s['shares'] ?? 0;
          final buyPrice = s['purchase_price'] ?? 0;
          final currentPrice = s['current_price'] ?? 0;
          final currency = s['currency'] ?? 'TRY';
          return '$symbol: $shares adet, alış: $buyPrice $currency, güncel: $currentPrice $currency';
        }).join('\n');
        portfolioContext = '\n\nKullanıcının mevcut portföyü:\n$lines';
      }
    } catch (_) {}

    _systemPrompt =
        'Sen bir finans ve yatırım asistanısın. '
        'Hisse senetleri, portföy yönetimi, borsa ve yatırım konularında uzmansın. '
        'Kullanıcının tüm sorularını Türkçe olarak yanıtla. '
        'Finansal tavsiye verirken dikkatli ve dengeli ol, riskleri belirt.$portfolioContext';

    if (mounted) {
      setState(() => _isInitializing = false);
      _scrollToBottom();
    }
  }

  Future<String> _callGemini(String userMessage) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$_apiKey',
    );

    // Tüm geçmiş + yeni mesaj
    final contents = <Map<String, dynamic>>[];
    for (final m in _messages) {
      contents.add({
        'role': m.isUser ? 'user' : 'model',
        'parts': [{'text': m.text}],
      });
    }
    contents.add({
      'role': 'user',
      'parts': [{'text': userMessage}],
    });

    final body = jsonEncode({
      'systemInstruction': {
        'parts': [{'text': _systemPrompt}],
      },
      'contents': contents,
    });

    for (int attempt = 0; attempt < 3; attempt++) {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final parts = data['candidates']?[0]?['content']?['parts'] as List?;
        final text = parts
            ?.map((part) => part['text'])
            .whereType<String>()
            .join()
            .trim();

        if (text == null || text.isEmpty) {
          throw Exception('Gemini boş yanıt döndürdü.');
        }

        return text;
      } else if (response.statusCode == 503 && attempt < 2) {
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        continue;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error']['message'] ?? 'API hatası');
      }
    }
    throw Exception('Yanıt alınamadı, tekrar dene.');
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return;
    final list = jsonDecode(raw) as List;
    setState(() {
      _messages.addAll(list.map((e) => (
            text: e['text'] as String,
            isUser: e['isUser'] as bool,
          )));
    });
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _messages.map((m) => {'text': m.text, 'isUser': m.isUser}).toList();
    await prefs.setString(_historyKey, jsonEncode(data));
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    setState(() => _messages.clear());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    _controller.clear();
    setState(() {
      _messages.add((text: text, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final reply = await _callGemini(text);
      setState(() => _messages.add((text: reply, isUser: false)));
      await _saveHistory();
    } catch (e) {
      setState(() => _messages.add((text: 'Hata: $e', isUser: false)));
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('AI Asistan'),
        centerTitle: true,
        elevation: 0.2,
        shadowColor: Colors.black,
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Geçmişi temizle',
              onPressed: () => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Sohbeti Temizle'),
                  content: const Text('Tüm sohbet geçmişi silinecek.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('İptal'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _clearHistory();
                      },
                      child: const Text('Temizle', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Hisse, portföy veya yatırım hakkında soru sorabilirsiniz.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            return _MessageBubble(text: msg.text, isUser: msg.isUser);
                          },
                        ),
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Yanıt yazılıyor...',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                AnimatedPadding(
                  duration: const Duration(milliseconds: 100),
                  padding: EdgeInsets.only(
                    left: 12,
                    right: 12,
                    top: 8,
                    bottom: bottomInset > 0 ? bottomInset + 8 : 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Mesaj yaz...',
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 16,
                            ),
                            filled: true,
                            fillColor: const Color.fromARGB(100, 224, 224, 224),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _isLoading ? null : _sendMessage,
                        icon: const Icon(Icons.send),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.text, required this.isUser});

  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? Colors.black : const Color.fromARGB(255, 235, 235, 235),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isUser ? Colors.white : Colors.black,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
