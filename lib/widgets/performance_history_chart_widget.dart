import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_newtten/widgets/earnings_line_chart_widget.dart';
import 'package:flutter_application_newtten/widgets/period_button_widget.dart';

class PerformanceHistoryChartWidget extends StatefulWidget {
  final List<Map<String, dynamic>> performanceHistory;
  final List<Map<String, dynamic>> tempSnapshots;

  const PerformanceHistoryChartWidget({
    super.key,
    required this.performanceHistory,
    this.tempSnapshots = const [],
  });

  @override
  State<PerformanceHistoryChartWidget> createState() => _PerformanceHistoryChartWidgetState();
}

class _PerformanceHistoryChartWidgetState extends State<PerformanceHistoryChartWidget> {
  ChartPeriod _selectedPeriod = ChartPeriod.all;

  List<FlSpot> _buildSpots(List<Map<String, dynamic>> docs) {
    final List<FlSpot> spots = [];
    for (int i = 0; i < docs.length; i++) {
      final item = docs[i];
      final num? rawValue =
          item['cumulative_twr'] ?? item['cumulative_return'] ?? item['twr'];
      final double cumulative = (rawValue ?? 0).toDouble();
      spots.add(FlSpot(i.toDouble(), cumulative * 100));
    }
    return spots;
  }

  List<FlSpot> _normalizeData(List<FlSpot> slicedData) {
    if (slicedData.isEmpty) return [];
    final double startY = slicedData.first.y;
    final double startX = slicedData.first.x;
    return slicedData.map((e) => FlSpot(e.x - startX, e.y - startY)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> slicedDocs =
        _docsForPeriod(_selectedPeriod);
    final List<FlSpot> fullData = _buildSpots(slicedDocs);

    if (fullData.isEmpty) {
      return SizedBox(
        height: 200,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.show_chart, size: 40, color: Colors.grey),
            SizedBox(height: 10),
            Text("Veri Bekleniyor...", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    List<FlSpot> displayData = _normalizeData(fullData);
    if (displayData.length == 1) {
      final only = displayData.first;
      displayData = [only, FlSpot(only.x + 1, only.y)];
    }
    final double currentReturn = displayData.isNotEmpty ? displayData.last.y : 0.0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 40.0, right: 20.0),
          child: SizedBox(
            height: 140,
            child: EarningsChartWidget(
              chartData: displayData,
              currentReturn: currentReturn,
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            PeriodButton(period: ChartPeriod.all, label: 'tümü', isSelected: _selectedPeriod == ChartPeriod.all, onSelected: _onPeriodSelected),
            PeriodButton(period: ChartPeriod.daily, label: '1G', isSelected: _selectedPeriod == ChartPeriod.daily, onSelected: _onPeriodSelected),
            PeriodButton(period: ChartPeriod.weekly, label: '1H', isSelected: _selectedPeriod == ChartPeriod.weekly, onSelected: _onPeriodSelected),
            PeriodButton(period: ChartPeriod.monthly, label: '1A', isSelected: _selectedPeriod == ChartPeriod.monthly, onSelected: _onPeriodSelected),
            PeriodButton(period: ChartPeriod.yearly, label: '1Y', isSelected: _selectedPeriod == ChartPeriod.yearly, onSelected: _onPeriodSelected),
          ],
        ),
      ],
    );
  }

  void _onPeriodSelected(ChartPeriod period) {
    setState(() => _selectedPeriod = period);
  }

  List<Map<String, dynamic>> _docsForPeriod(ChartPeriod period) {
    if (period == ChartPeriod.daily) {
      return _sliceTempDaily();
    }
    final List<Map<String, dynamic>> history =
        List<Map<String, dynamic>>.from(widget.performanceHistory);
    history.sort((a, b) => _extractDate(a).compareTo(_extractDate(b)));
    return _sliceHistoryByPeriod(history, period);
  }

  List<Map<String, dynamic>> _sliceHistoryByPeriod(
    List<Map<String, dynamic>> docs,
    ChartPeriod period,
  ) {
    if (docs.isEmpty) return [];
    final DateTime endDate = _extractDate(docs.last);

    switch (period) {
      case ChartPeriod.weekly:
        return _filterByDateWindow(docs, endDate, 7);
      case ChartPeriod.monthly:
        return _filterByDateWindow(docs, endDate, 30);
      case ChartPeriod.yearly:
        return _filterByDateWindow(docs, endDate, 365);
      case ChartPeriod.all:
      default:
        return docs;
    }
  }

  List<Map<String, dynamic>> _sliceTempDaily() {
    final List<Map<String, dynamic>> temp =
        List<Map<String, dynamic>>.from(widget.tempSnapshots);
    if (temp.isEmpty) return [];
    temp.sort((a, b) => _extractDate(a).compareTo(_extractDate(b)));

    final DateTime latest = _extractDate(temp.last);
    final DateTime start = latest.subtract(const Duration(hours: 24));
    final List<Map<String, dynamic>> window = temp.where((doc) {
      final DateTime d = _extractDate(doc);
      return !d.isBefore(start) && !d.isAfter(latest);
    }).toList();

    if (window.length <= 8) return window;
    return window.sublist(window.length - 8);
  }

  List<Map<String, dynamic>> _filterByDateWindow(
    List<Map<String, dynamic>> docs,
    DateTime endDate,
    int days,
  ) {
    final DateTime startDate = endDate.subtract(Duration(days: days));
    return docs.where((doc) {
      final DateTime d = _extractDate(doc);
      return !d.isBefore(startDate);
    }).toList();
  }

  DateTime _extractDate(Map<String, dynamic> doc) {
    final date = doc['date'];
    if (date is Timestamp) return date.toDate();
    if (date is DateTime) return date;
    final dateId = doc['date_id'];
    if (dateId is String) {
      final parts = dateId.split('-');
      if (parts.length == 3) {
        final year = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        final day = int.tryParse(parts[2]);
        final hourRaw = doc['hour_id']?.toString() ?? '0';
        final hour = int.tryParse(hourRaw) ?? 0;
        if (year != null && month != null && day != null) {
          return DateTime(year, month, day, hour);
        }
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
