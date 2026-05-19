import 'dart:math'; // Açı hesapları için gerekli
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_newtten/widgets/company_logo.dart';

class PortfolioDonutChart extends StatefulWidget {
  final List<Map<String, dynamic>> portfolio;
  final Widget centerWidget;

  const PortfolioDonutChart({
    super.key,
    required this.portfolio,
    required this.centerWidget,
  });

  @override
  State<PortfolioDonutChart> createState() => _PortfolioDonutChartState();
}

class _PortfolioDonutChartState extends State<PortfolioDonutChart> {
  int touchedIndex = -1;

  double _startDegreeOffset = 270.0;
  double _lastTouchAngle = 0.0;

  @override
  Widget build(BuildContext context) {
    if (widget.portfolio.isEmpty) {
      return SizedBox(
        height: 250,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                startDegreeOffset: 270,
                sectionsSpace: 0,
                centerSpaceRadius: 60,
                sections: [
                  PieChartSectionData(
                    color: Colors.grey.shade200,
                    value: 100,
                    radius: 20,
                    showTitle: false,
                  )
                ],
              ),
            ),
            widget.centerWidget,
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: 300,
          child: Listener(
            onPointerDown: (event) {
              _lastTouchAngle = _calculateAngle(event.localPosition, constraints.maxWidth, 300);
            },
            onPointerMove: (event) {
              final currentAngle = _calculateAngle(event.localPosition, constraints.maxWidth, 300);

              double delta = currentAngle - _lastTouchAngle;

              if (delta > 180) delta -= 360;
              if (delta < -180) delta += 360;

              setState(() {
                _startDegreeOffset += delta;
                _lastTouchAngle = currentAngle;
              });
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    startDegreeOffset: _startDegreeOffset, 
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null) {
                            touchedIndex = -1;
                            return;
                          }
                          touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                        });
                      },
                    ),
                    borderData: FlBorderData(show: false),
                    sectionsSpace: 1, 
                    centerSpaceRadius: 58,
                    sections: _showingSections(),
                  ),
                ),
                widget.centerWidget,
              ],
            ),
          ),
        );
      }
    );
  }

  double _calculateAngle(Offset position, double width, double height) {
    final centerX = width / 2;
    final centerY = height / 2;
    final dx = position.dx - centerX;
    final dy = position.dy - centerY;
    final radians = atan2(dy, dx);
    return radians * 180 / pi;
  }

  List<PieChartSectionData> _showingSections() {
    List<Map<String, dynamic>> processedList = [];
    
    // 1. Toplam Portföy Değeri
    double totalPortfolioValue = 0;

    for (var item in widget.portfolio) {
      double shares = 0;
      double price = 0;

      if (item['shares'] != null) {
        shares = double.tryParse(item['shares'].toString()) ?? 0.0;
      }
      if (item['current_price'] != null) {
        price = double.tryParse(item['current_price'].toString()) ?? 0.0;
      }

      double totalValue = shares * price;
      totalPortfolioValue += totalValue; 
      
      Map<String, dynamic> tempMap = Map.from(item);
      tempMap['calculated_value'] = totalValue;
      processedList.add(tempMap);
    }

    // Sıralama (Büyükten küçüğe)
    processedList.sort((a, b) {
      double valA = a['calculated_value'];
      double valB = b['calculated_value'];
      return valB.compareTo(valA); 
    });

    return List.generate(processedList.length, (i) {
      final stock = processedList[i];
      final isTouched = i == touchedIndex;
      final double widgetSize = isTouched ? 40.0 : 40.0;
      final double radius = isTouched ? 80.0 : 80.0;
      
      final double value = stock['calculated_value'];
      final String symbol = stock['symbol'];

      final double percentage = (totalPortfolioValue > 0) 
          ? (value / totalPortfolioValue) * 100 
          : 0;

      Color sectionColor;
      if (stock['color'] != null && stock['color'] is int) {
        sectionColor = Color(stock['color']);
      } else {
        sectionColor = Colors.primaries[i % Colors.primaries.length];
      }

      return PieChartSectionData(
        color: sectionColor, 
        value: value > 0 ? value : 0.1, 

        showTitle: true,
        title: '%${percentage.toStringAsFixed(1)}',

        titlePositionPercentageOffset: 1.199, 
        
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
        
        badgeWidget: _Badge(
          key: ValueKey(symbol), 
          symbol: symbol,
          logoUrl: stock['logo_url']?.toString(),
          size: widgetSize,
          borderColor: sectionColor, 
        ),
        badgePositionPercentageOffset: .55,
        radius: radius,
      );
    });
  }
}

// --- 2. GÜNCELLENMİŞ BADGE WIDGET (CACHE DESTEKLİ) ---
class _Badge extends StatelessWidget {
  final String symbol;
  final String? logoUrl;
  final double size;
  final Color borderColor;

  const _Badge({
    Key? key,
    required this.symbol,
    required this.logoUrl,
    required this.size,
    required this.borderColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: size,
      height: size,
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.transparent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 3,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: CompanyLogo(
          logoUrl: logoUrl,
          size: size,
        ),
      ),
    );
  }
}
