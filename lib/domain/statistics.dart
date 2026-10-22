/// 三个统计视图共用的时间分组。周从周一开始，月按自然月分组。
enum StatisticsPeriod {
  day('日'),
  week('周'),
  month('月');

  const StatisticsPeriod(this.label);
  final String label;
  DateTime start(DateTime date, [int offset = 0]) => switch (this) {
    day => DateTime(date.year, date.month, date.day + offset),
    week => DateTime(
      date.year,
      date.month,
      date.day - date.weekday + 1 + offset * 7,
    ),
    month => DateTime(date.year, date.month + offset),
  };
}

class LearningBucket {
  LearningBucket(this.start, this.end);
  final DateTime start, end;
  final grades = List<int>.filled(4, 0);
  int newCards = 0, reviewCards = 0, elapsedMs = 0, pending = 0;
  int enrolled = 0;

  /// 对应 ≥10、30、60、90 天；旧数据缺少记忆状态时为 null。
  final durability = List<int?>.filled(4, 0);
}

/// 经典节省率采样的示意插值，用于截图中的参考线；不是个人回忆概率。
/// 来源：Ebbinghaus, Memory, Chapter VII（墨墨百科经典文献译本）。
/// https://memodocs.maimemo.com/docs/ebbinghaus-memory-forgetting-curve-and-retention
double ebbinghausReference(double days) {
  const anchors = [
    (0.0, 100.0),
    (1.0, 33.7),
    (2.0, 27.8),
    (6.0, 25.4),
    (31.0, 21.1),
  ];
  for (var i = 1; i < anchors.length; i++) {
    final a = anchors[i - 1], b = anchors[i];
    if (days <= b.$1) {
      return a.$2 + (b.$2 - a.$2) * (days - a.$1) / (b.$1 - a.$1);
    }
  }
  return anchors.last.$2;
}
