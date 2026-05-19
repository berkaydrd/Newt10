import 'package:flutter/material.dart';
import 'package:flutter_application_newtten/widgets/earnings_chart_widget.dart';
import 'package:flutter_application_newtten/widgets/pie_chart_widget.dart';
import 'package:flutter_application_newtten/widgets/profile_image_widget.dart';

class ProfileHeaderWidget extends StatelessWidget {
  final String username;
  final String? profileImagePath;
  final Function(String) onImageSelected;
  final bool showPieChart;
  final List<Map<String, dynamic>> displayData;
  final List<Map<String, dynamic>> fallbackPortfolio;
  final Widget? chartOverride;
  
  // YENİ PARAMETRE
  final String selectedCurrency; 

  const ProfileHeaderWidget({
    super.key,
    required this.username,
    required this.profileImagePath,
    required this.onImageSelected,
    required this.showPieChart,
    required this.displayData,
    required this.fallbackPortfolio,
    this.chartOverride,
    required this.selectedCurrency, // Zorunlu yaptık
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // SOL TARAF: PROFİL RESMİ VE BİLGİLER
        Padding(
          padding: const EdgeInsets.only(top: 40.0, left: 20.0),
          child: Column(
            children: [
              ProfileImageWidget(
                username: username,
                initialImagePath: profileImagePath,
                onImageSelected: onImageSelected,
              ),
              const SizedBox(height: 5.0),
              const Text('234 Takipçi', style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.w500)),
              const Text('5 Abone', style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.w500)),
              const SizedBox(height: 40.0),
            ],
          ),
        ),
        const SizedBox(width: 20.0),

        // SAĞ TARAF: GRAFİK (Pie veya Line)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 0.0, right: 10.0),
            child: SizedBox(
              height: 250,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: showPieChart
                    ? Hero(
                        tag: 'portfolio_chart_hero',
                        child: Material(
                          color: Colors.transparent,
                          child: PortfolioPieChart(
                            key: const ValueKey('Pie'),
                            portfolioData: displayData,
                          ),
                        ),
                      )
                    : (chartOverride ??
                        ChartContainer(
                          key: const ValueKey('line'),
                          username: username,
                          selectedCurrency: selectedCurrency, 
                        )),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
