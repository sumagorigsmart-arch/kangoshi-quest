import 'shift_history.dart';

const axisLabels = {
  'patient': '患者対応',
  'team': 'チーム',
  'health': '自分の健康',
  'safety': '安全',
};

String shiftTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

String shareText(ShiftRecord record) {
  final result = record.result;
  return [
    '看護師クエスト',
    '本日の勤務結果',
    '退勤時刻 ${shiftTime(result.finishTime)}',
    '残業時間 ${result.overtimeMinutes}分',
    for (final axis in axisLabels.entries)
      '${axis.value} ${result.axisScores[axis.key]} / 10000（${result.grades[axis.key]}）',
    '称号 ${record.title}',
    '今日も無事に定時で帰れ。',
    '#看護師クエスト',
  ].join('\n');
}

class ShiftSummary {
  final int total, onTime, overtimeMinutes, relief;
  final Map<String, double> axisAverages;
  final Map<String, int> titleCounts;
  const ShiftSummary(
    this.total,
    this.onTime,
    this.overtimeMinutes,
    this.relief,
    this.axisAverages,
    this.titleCounts,
  );

  factory ShiftSummary.fromRecords(
    List<ShiftRecord> records, {
    Map<String, String> titleNames = const {},
  }) {
    final unique = {for (final r in records) r.id: r}.values.toList();
    final n = unique.length;
    final titleCounts = <String, int>{};
    for (final record in unique) {
      for (final id in record.result.earnedTitleIds.toSet()) {
        final name =
            titleNames[id] ??
            (id == record.result.primaryTitleId ? record.title : id);
        titleCounts[name] = (titleCounts[name] ?? 0) + 1;
      }
    }
    return ShiftSummary(
      n,
      unique
          .where(
            (r) =>
                r.result.reason != 'forcedRelief' &&
                r.result.overtimeMinutes == 0,
          )
          .length,
      unique.fold(0, (sum, r) => sum + r.result.overtimeMinutes),
      unique.where((r) => r.result.reason == 'forcedRelief').length,
      {
        for (final axis in axisLabels.keys)
          axis: n == 0
              ? 0
              : unique.fold<int>(
                      0,
                      (sum, r) => sum + (r.result.axisScores[axis] ?? 0),
                    ) /
                    n,
      },
      titleCounts,
    );
  }

  double get onTimeRate => total == 0 ? 0 : onTime * 100 / total;
  double get averageOvertime => total == 0 ? 0 : overtimeMinutes / total;
}
