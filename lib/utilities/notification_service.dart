import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // Uygulama açıldığında varsayılan davranış yeterli.
      },
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  Future<void> showDividendNotification({
    required String symbol,
    required double amount,
    required String currency,
  }) async {
    await init();
    final formatted = _formatAmount(amount, currency);
    await _plugin.show(
      _notificationId(),
      'Temettü Ödemesi Alındı: $symbol',
      '$formatted tutarında temettü hesabınıza işlendi. Performans grafiğiniz bu ödemeye göre otomatik olarak düzeltildi.',
      _details(),
    );
  }

  Future<void> showSplitNotification({
    required String symbol,
    required String ratioText,
  }) async {
    await init();
    await _plugin.show(
      _notificationId(),
      'Hisse Bölünmesi: $symbol',
      'Hisse oranı $ratioText olarak güncellendi. Portföyünüz otomatik düzeltildi.',
      _details(),
    );
  }

  NotificationDetails _details() {
    const androidDetails = AndroidNotificationDetails(
      'stock_events',
      'Stock Events',
      channelDescription: 'Temettü ve bölünme bildirimleri',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    return const NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  int _notificationId() {
    return DateTime.now().millisecondsSinceEpoch.remainder(1000000);
  }

  String _formatAmount(double amount, String currency) {
    final format = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: currency == 'TRY' ? '₺' : '\$',
      decimalDigits: 2,
    );
    return format.format(amount);
  }
}
