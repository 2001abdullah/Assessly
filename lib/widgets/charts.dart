import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../themes/app_colors.dart';
import '../themes/app_text_styles.dart';

/// Chart wrappers with the app's styling, so screens only pass data.
/// Percentages are plotted on a fixed 0-100 axis.

/// A white card with a title, optional subtitle and a chart (or any child).
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.height = 200,
    this.legend,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final double height;
  final Widget? legend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.subtitle),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: AppTextStyles.bodySecondary.copyWith(fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(height: height, child: child),
          if (legend != null) ...[const SizedBox(height: 10), legend!],
        ],
      ),
    );
  }
}

class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: AppTextStyles.caption),
    ],
  );
}

/// Shown instead of a chart when there is nothing to plot yet.
class ChartEmpty extends StatelessWidget {
  const ChartEmpty({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.show_chart_rounded,
          color: AppColors.neutral,
          size: 30,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySecondary,
        ),
      ],
    ),
  );
}

FlTitlesData _titles({required List<String> labels, bool percentAxis = true}) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 34,
        interval: percentAxis ? 25 : null,
        getTitlesWidget: (value, meta) => SideTitleWidget(
          meta: meta,
          child: Text(
            percentAxis ? '${value.toInt()}%' : '${value.toInt()}',
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final i = value.toInt();
          if (i < 0 || i >= labels.length || value != i.toDouble()) {
            return const SizedBox.shrink();
          }
          // Thin labels out when there are many points.
          final step = math.max(1, (labels.length / 6).ceil());
          if (i % step != 0 && i != labels.length - 1) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            meta: meta,
            child: Text(
              labels[i],
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          );
        },
      ),
    ),
  );
}

final _grid = FlGridData(
  show: true,
  drawVerticalLine: false,
  horizontalInterval: 25,
  getDrawingHorizontalLine: (_) =>
      const FlLine(color: AppColors.border, strokeWidth: 1),
);

/// One or more percentage series over the same x labels (e.g. exams).
class PercentLineChart extends StatelessWidget {
  const PercentLineChart({
    super.key,
    required this.labels,
    required this.series,
    required this.colors,
    this.dashed = const {},
  });

  final List<String> labels;

  /// Values per series; null points are skipped.
  final List<List<double?>> series;
  final List<Color> colors;

  /// Indexes of series drawn dashed (e.g. the class average).
  final Set<int> dashed;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const ChartEmpty(message: 'No results yet');
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        minX: 0,
        maxX: math.max(1, labels.length - 1).toDouble(),
        gridData: _grid,
        borderData: FlBorderData(show: false),
        titlesData: _titles(labels: labels),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.ink,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${s.y.toStringAsFixed(1)}%',
                  TextStyle(
                    color: s.bar.color ?? Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          for (var i = 0; i < series.length; i++)
            LineChartBarData(
              spots: [
                for (var x = 0; x < series[i].length; x++)
                  if (series[i][x] != null) FlSpot(x.toDouble(), series[i][x]!),
              ],
              isCurved: true,
              preventCurveOverShooting: true,
              color: colors[i],
              barWidth: dashed.contains(i) ? 2 : 3,
              dashArray: dashed.contains(i) ? [5, 4] : null,
              dotData: FlDotData(show: !dashed.contains(i)),
              belowBarData: BarAreaData(
                show: i == 0,
                color: colors[i].withValues(alpha: 0.10),
              ),
            ),
        ],
      ),
    );
  }
}

/// Vertical bars, one per label. [percent] fixes the axis at 0-100.
class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    super.key,
    required this.labels,
    required this.values,
    this.colors,
    this.percent = true,
  });

  final List<String> labels;
  final List<double> values;
  final List<Color>? colors;
  final bool percent;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const ChartEmpty(message: 'Nothing to show yet');
    final maxValue = values.fold<double>(0, math.max);
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: percent ? 100 : math.max(1, maxValue * 1.2),
        gridData: percent
            ? _grid
            : const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: _titles(labels: labels, percentAxis: percent),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.ink,
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              percent
                  ? '${rod.toY.toStringAsFixed(1)}%'
                  : rod.toY.toStringAsFixed(0),
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  width: math.min(22, 180 / math.max(values.length, 1)),
                  color: colors?[i % colors!.length] ?? AppColors.primary,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Donut with a label in the middle.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.values,
    required this.colors,
    required this.center,
  });

  final List<double> values;
  final List<Color> colors;
  final Widget center;

  @override
  Widget build(BuildContext context) {
    final total = values.fold<double>(0, (a, b) => a + b);
    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 48,
            startDegreeOffset: -90,
            sections: total == 0
                ? [
                    PieChartSectionData(
                      value: 1,
                      color: AppColors.neutralSoft,
                      showTitle: false,
                      radius: 18,
                    ),
                  ]
                : [
                    for (var i = 0; i < values.length; i++)
                      if (values[i] > 0)
                        PieChartSectionData(
                          value: values[i],
                          color: colors[i],
                          showTitle: false,
                          radius: 18,
                        ),
                  ],
          ),
        ),
        center,
      ],
    );
  }
}
