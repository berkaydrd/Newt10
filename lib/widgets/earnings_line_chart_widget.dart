import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class EarningsChartWidget extends StatelessWidget {
  final List<FlSpot> chartData;
  final double currentReturn;

  const EarningsChartWidget({
    super.key,
    required this.chartData,
    required this.currentReturn,
  });

  @override
  Widget build(BuildContext context) {
    Color lineColor =
        currentReturn >= 0 ? Colors.green.shade600 : Colors.red.shade600;
    return Stack(
      children: [
        LineChart(
          LineChartData(
            minY: chartData.map((e) => e.y).reduce((a, b) => a < b ? a : b) - 1,
            maxY: chartData.map((e) => e.y).reduce((a, b) => a > b ? a : b) + 1,
            titlesData: FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: chartData,
                isCurved: false,
                color: lineColor,
                barWidth: 2.5,
                dotData: FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [lineColor.withOpacity(0.3), lineColor.withOpacity(0.0)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                //tooltipBgColor: Colors.black, //Bu niye hata vermiş anlamadım :((
                getTooltipItems: (touchedSpots) => touchedSpots
                    .map(
                      (spot) => LineTooltipItem(
                        '%${spot.y.toStringAsFixed(2)}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold, 
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Toplam Getiri (TWR)',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
              Text(
                '%${currentReturn.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 20,
                  color: lineColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
