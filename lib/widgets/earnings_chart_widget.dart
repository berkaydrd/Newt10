import 'package:flutter/material.dart';
import 'package:flutter_application_newtten/utilities/firestore_service.dart';
import 'package:flutter_application_newtten/widgets/performance_history_chart_widget.dart';

class ChartContainer extends StatelessWidget {
  final String username;
  final String selectedCurrency;

  const ChartContainer({
    super.key,
    required this.username,
    required this.selectedCurrency,
  });

  @override
  Widget build(BuildContext context) {
    if (username == 'Yükleniyor...' || username.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirestoreService.getPerformanceHistoryStream(username),
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
            final tempData = tempSnapshot.data ?? const <Map<String, dynamic>>[];
            return PerformanceHistoryChartWidget(
              key: const ValueKey('line_perf'),
              performanceHistory: data,
              tempSnapshots: tempData,
            );
          },
        );
      },
    );
  }

}
