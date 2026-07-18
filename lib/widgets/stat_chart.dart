import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A compact line chart of a sliding window of samples.
class StatLineChart extends StatelessWidget {
  final String title;
  final String currentLabel;
  final List<double> samples;
  final int capacity;
  final Color color;

  /// Upper bound for the y axis; when null the chart auto-scales.
  final double? maxY;
  final String Function(double) formatValue;

  /// Optional second series (e.g. upload vs download).
  final List<double>? secondarySamples;
  final Color? secondaryColor;

  const StatLineChart({
    super.key,
    required this.title,
    required this.currentLabel,
    required this.samples,
    required this.capacity,
    required this.color,
    required this.formatValue,
    this.maxY,
    this.secondarySamples,
    this.secondaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    double top;
    if (maxY != null) {
      top = maxY!;
    } else {
      final all = [...samples, ...?secondarySamples];
      final peak =
          all.isEmpty ? 0.0 : all.reduce((a, b) => a > b ? a : b);
      top = peak <= 0 ? 1 : peak * 1.25;
    }

    List<FlSpot> toSpots(List<double> values) {
      final offset = capacity - values.length;
      return [
        for (var i = 0; i < values.length; i++)
          FlSpot((offset + i).toDouble(), values[i]),
      ];
    }

    LineChartBarData bar(List<double> values, Color barColor) =>
        LineChartBarData(
          spots: toSpots(values),
          isCurved: true,
          curveSmoothness: 0.2,
          preventCurveOverShooting: true,
          color: barColor,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: barColor.withValues(alpha: 0.15),
          ),
        );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(
                  currentLabel,
                  style: theme.textTheme.titleSmall?.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: samples.length < 2
                  ? Center(
                      child: Text('等待資料…',
                          style: theme.textTheme.bodySmall))
                  : LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: (capacity - 1).toDouble(),
                        minY: 0,
                        maxY: top,
                        clipData: const FlClipData.all(),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(),
                          rightTitles: const AxisTitles(),
                          bottomTitles: const AxisTitles(),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 52,
                              interval: top / 2,
                              getTitlesWidget: (value, meta) => Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Text(
                                  formatValue(value),
                                  style: theme.textTheme.labelSmall,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ),
                          ),
                        ),
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          horizontalInterval: top / 2,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.4),
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineTouchData:
                            const LineTouchData(enabled: false),
                        lineBarsData: [
                          bar(samples, color),
                          if (secondarySamples != null)
                            bar(secondarySamples!,
                                secondaryColor ?? color),
                        ],
                      ),
                      duration: Duration.zero,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
