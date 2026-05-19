import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_newtten/widgets/company_logo.dart';

class PortfolioPieChart extends StatefulWidget {
  final List<Map<String, dynamic>> portfolioData;

  const PortfolioPieChart({super.key, required this.portfolioData});

  @override
  State<PortfolioPieChart> createState() => _PortfolioPieChartState();
}

class _PortfolioPieChartState extends State<PortfolioPieChart> {

  @override
  Widget build(BuildContext context) {
    if (widget.portfolioData.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: const Text("Henüz portföy verisi yok.", style: TextStyle(color: Colors.grey)),
      );
    }

    final processedData = _getProcessedData(widget.portfolioData);
    final double totalValue = processedData.fold(0, (sum, item) => sum + item['calculated_value']);

    return _InteractivePieChart(
      processedData: processedData,
      totalValue: totalValue,
    );
  }

  List<Map<String, dynamic>> _getProcessedData(List<Map<String, dynamic>> rawPortfolio) {
    List<Map<String, dynamic>> processedList = [];
    
    for (var item in rawPortfolio) {
      double shares = double.tryParse(item['shares']?.toString() ?? '0') ?? 0.0;
      double price = double.tryParse(item['current_price']?.toString() ?? '0') ?? 0.0;
      double totalValue = shares * price;
      
      Map<String, dynamic> tempMap = Map.from(item);
      tempMap['calculated_value'] = totalValue;
      processedList.add(tempMap);
    }

    processedList.sort((a, b) => b['calculated_value'].compareTo(a['calculated_value']));
    
    return processedList;
  }
}

class _InteractivePieChart extends StatefulWidget {
  final List<Map<String, dynamic>> processedData;
  final double totalValue;

  const _InteractivePieChart({
    required this.processedData,
    required this.totalValue,
  });

  @override
  State<_InteractivePieChart> createState() => _InteractivePieChartState();
}

class _InteractivePieChartState extends State<_InteractivePieChart> {
  int touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        height: 250,
        child: AspectRatio(
          aspectRatio: 1,
          child: PieChart(
            PieChartData(
              startDegreeOffset: 270, 
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  setState(() {
                    // Eğer boşluğa tıklanırsa veya geçersiz bir yere dokunulursa
                    if (pieTouchResponse == null || pieTouchResponse.touchedSection == null) {
                      // Parmağını kaldırdığında (TapUp) boşluğa denk geldiyse kapat
                      if (event is FlTapUpEvent) {
                         touchedIndex = -1;
                      }
                      return;
                    }

                    // --- DÜZELTME: FlTapDownEvent ---
                    // "TouchDown" değil "TapDown" kullanıyoruz.
                    // Ekrana parmak değdiği milisaniyede çalışır. Sürükleme olsa bile algılar.
                    if (event is FlTapDownEvent) {
                      final newIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                      
                      if (touchedIndex == newIndex) {
                        // Zaten açıksa kapat
                        touchedIndex = -1;
                      } else {
                        // Kapalıysa aç
                        touchedIndex = newIndex;
                      }
                    }
                  });
                },
              ),
              borderData: FlBorderData(show: false),
              sectionsSpace: 1,
              centerSpaceRadius: 0,
              sections: _showingSections(widget.processedData, widget.totalValue),
            ),
          ),
        ),
      ),
    );
  }

  List<PieChartSectionData> _showingSections(List<Map<String, dynamic>> data, double totalPortfolioValue) {
    return List.generate(data.length, (i) {
      final stock = data[i];
      final isTouched = i == touchedIndex;
      
      final double radius = isTouched ? 115.0 : 105.0; 
      final double widgetSize = isTouched ? 45.0 : 35.0; 

      Color sectionColor;
      if (stock['color'] != null) {
        int? colorValue = int.tryParse(stock['color'].toString());
        sectionColor = colorValue != null ? Color(colorValue) : Colors.primaries[i % Colors.primaries.length];
      } else {
        sectionColor = Colors.primaries[i % Colors.primaries.length];
      }

      double val = stock['calculated_value'];
      double percent = (totalPortfolioValue > 0) ? (val / totalPortfolioValue) * 100 : 0;
      String percentageText = '%${percent.toStringAsFixed(1)}';

      return PieChartSectionData(
        color: sectionColor,
        value: val > 0 ? val : 0.1,
        radius: radius,
        showTitle: false, 
        
        badgeWidget: isTouched 
          ? _InfoBubble(
              symbol: stock['symbol'], 
              percentage: percentageText, 
              value: "${val.toStringAsFixed(0)} TL",
              color: sectionColor,
            )
          : _Badge(
              key: ValueKey(stock['symbol']),
              symbol: stock['symbol'],
              logoUrl: stock['logo_url']?.toString(),
              size: widgetSize,
              borderColor: sectionColor,
            ),
        badgePositionPercentageOffset: isTouched ? 0.75 : 0.65,
      );
    });
  }
}

// --- LOGO WIDGET ---
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
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: Center(
          child: CompanyLogo(
            logoUrl: logoUrl,
          ),
        ),
      ),
    );
  }
}

// --- BALONCUK (Tooltip) ---
class _InfoBubble extends StatelessWidget {
  final String symbol;
  final String percentage;
  final String value;
  final Color color;

  const _InfoBubble({required this.symbol, required this.percentage, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(0),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(symbol, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
          Text(percentage, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
