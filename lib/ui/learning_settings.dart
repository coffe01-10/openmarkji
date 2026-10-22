part of 'app.dart';

class _AlgorithmPlanSection extends StatefulWidget {
  const _AlgorithmPlanSection({required this.store});
  final AppStore store;
  @override
  State<_AlgorithmPlanSection> createState() => _AlgorithmPlanSectionState();
}

class _AlgorithmPlanSectionState extends State<_AlgorithmPlanSection> {
  String _days = '30';
  bool _applying = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.store.preferences;
    final c = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AppearanceHeader('记忆算法', Icons.psychology_outlined),
        _AppearanceCard(
          child: Column(
            children: [
              _AppearanceMenu(
                title: '当前算法版本',
                value: '${p.defaultAlgorithm}',
                options: const {'5': 'MMX-5.0', '6': 'MMX-6.0'},
                onChanged: (v) => _action(context, () async {
                  await widget.store.setDefaultAlgorithm(int.parse(v));
                }),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '用于新建牌组。已有牌组可单独设置，也可在下方统一切换。',
                  style: TextStyle(fontSize: 12, height: 1.7),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _applying
                          ? null
                          : () => _action(context, () async {
                              setState(() => _applying = true);
                              try {
                                final count = await widget.store
                                    .setDefaultAlgorithm(
                                      p.defaultAlgorithm,
                                      applyToExisting: true,
                                    );
                                if (context.mounted) {
                                  _toast(
                                    context,
                                    count == 0
                                        ? '所有牌组已使用 MMX-${p.defaultAlgorithm}'
                                        : '已切换 $count 副牌组到 MMX-${p.defaultAlgorithm}',
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _applying = false);
                              }
                            }),
                      icon: const Icon(Icons.sync_rounded),
                      label: Text(
                        _applying
                            ? '正在应用…'
                            : '全部牌组使用 MMX-${p.defaultAlgorithm}',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '切换版本的牌组使用该版本默认参数。学习记录与复习日期保留，下次正式评分时按历史重新计算。',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.7,
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _AppearanceHeader('学习计划与学习量', Icons.calendar_month_outlined),
        _AppearanceCard(
          child: Column(
            children: [
              _AppearanceMenu(
                title: '统计范围',
                value: _days,
                options: const {'7': '近 7 天', '30': '近 30 天', '90': '近 90 天'},
                onChanged: (v) => setState(() => _days = v),
              ),
              _Load(
                future: widget.store.learningLoad(days: int.parse(_days)),
                builder: (load) => Column(
                  children: [
                    _LearningValue(
                      title: '学习计划卡片数',
                      value: '${load.planned}',
                      unit: '张',
                    ),
                    _LearningValue(
                      title: '平均每天新学卡片数',
                      value: load.dailyNew.toStringAsFixed(1),
                      unit: '张',
                    ),
                    _LearningValue(
                      title: '平均每天复习卡片数',
                      value: load.dailyReview.toStringAsFixed(1),
                      unit: '张',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  '统计当前计划内的卡片，按近 $_days 个自然日（含今天和未学习日）平均；复习不含首次学习、当日重学及专项练习。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: c.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        _AppearanceHeader('每日安排', Icons.auto_stories_outlined),
      ],
    );
  }
}

class _LearningValue extends StatelessWidget {
  const _LearningValue({
    required this.title,
    required this.value,
    required this.unit,
  });
  final String title, value, unit;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      children: [
        Expanded(child: Text(title)),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            '$value $unit',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ],
    ),
  );
}
