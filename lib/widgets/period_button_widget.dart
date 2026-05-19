import 'package:flutter/material.dart';

enum ChartPeriod { all, daily, weekly, monthly, sixMonthly, yearly }

class PeriodButton extends StatelessWidget {
  final ChartPeriod period;
  final String label;
  final bool isSelected;
  final ValueChanged<ChartPeriod> onSelected; 

  const PeriodButton({
    super.key,
    required this.period,
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.1, vertical: 7.0),
      child: TextButton(
        onPressed: () => onSelected(period), 
        style: TextButton.styleFrom(
          foregroundColor: isSelected ? Colors.white : Colors.black, 
          backgroundColor: isSelected ? Colors.black : Colors.grey.shade300, 
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.bold,
          ),
        ),
      ),
    );
  }
}