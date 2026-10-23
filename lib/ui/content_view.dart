import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../content/markji.dart';
import '../data/app_store.dart';

class CardReferenceScope extends InheritedWidget {
  const CardReferenceScope({
    super.key,
    required this.pageBuilder,
    required super.child,
  });
  final Widget Function(String id) pageBuilder;

  static CardReferenceScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardReferenceScope>();

  @override
  bool updateShouldNotify(CardReferenceScope oldWidget) =>
      pageBuilder != oldWidget.pageBuilder;
}

class ContentView extends StatefulWidget {
  const ContentView({
    super.key,
    required this.source,
    required this.store,
    this.revealed = true,
    this.interactive = true,
    this.replaceImages = false,
    this.pendingMedia = const {},
  });
  final String source;
  final AppStore store;
  final bool revealed, interactive, replaceImages;

  /// 尚未写入媒体库的图片，例如导入预览中的文件。
  final Map<String, Uint8List> pendingMedia;
  @override
  State<ContentView> createState() => _ContentViewState();
}

class _ContentViewState extends State<ContentView> {
  final _groups = <String>{};
  late ParsedContent _parsed = MarkjiParser().parse(widget.source);
  @override
  void didUpdateWidget(ContentView old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _parsed = MarkjiParser().parse(widget.source);
      _groups.clear();
    }
    if (old.revealed && !widget.revealed) _groups.clear();
  }

  Future<void> _reference(ContentNode node) async {
    final id = node.param('ID/');
    final scope = CardReferenceScope.of(context);
    final target = id == null || id.isEmpty
        ? Future.value(null)
        : widget.store.card(id);
    final open = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => FractionallySizedBox(
        heightFactor: .72,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.link_rounded),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '卡片预览',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭预览',
                      onPressed: () => Navigator.pop(sheet),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder(
                    future: target,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final card = snapshot.data;
                      if (snapshot.hasError || card == null) {
                        return Center(
                          child: Text(
                            snapshot.hasError
                                ? '无法读取引用的卡片，请关闭后重试。'
                                : '引用的卡片不存在或已被删除。',
                          ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: ContentView(
                                source: card.source,
                                store: widget.store,
                              ),
                            ),
                          ),
                          if (scope != null) ...[
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => Navigator.pop(sheet, true),
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: const Text('打开卡片'),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (open == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '卡片详情'),
          builder: (_) => scope!.pageBuilder(id!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    var line = <ContentNode>[];
    void flush() {
      if (line.isEmpty) return;
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text.rich(
            TextSpan(children: line.map(_span).toList()),
            style: TextStyle(
              fontSize: widget.store.preferences.fontSize,
              height: 1.75,
            ),
          ),
        ),
      );
      line = [];
    }

    for (final n in _parsed.nodes) {
      if (n.kind == 'answer') {
        flush();
        if (!widget.revealed) break;
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              children: [
                Expanded(
                  child: Divider(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '解 答',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (n.kind == 'E') {
        flush();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                n.text,
                mathStyle: MathStyle.display,
                textStyle: TextStyle(
                  fontSize: widget.store.preferences.fontSize + 2,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onErrorFallback: (error) => Text(
                  '公式无法显示：${n.text}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ),
        );
      } else if (n.kind == 'Pic') {
        flush();
        widgets.add(
          _MediaImage(
            key: ValueKey(n.param('ID/')),
            id: n.param('ID/') ?? '',
            store: widget.store,
            replace: widget.replaceImages,
            pending: widget.pendingMedia[n.param('ID/')],
          ),
        );
      } else if (n.kind == 'P') {
        flush();
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              left: n.params.any((p) => p.startsWith('I')) ? 20 : 0,
              top: 8,
              bottom: 8,
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  if (n.params.contains('L')) const TextSpan(text: '•  '),
                  ...n.children.map(_span),
                ],
              ),
              textAlign: n.params.contains('center')
                  ? TextAlign.center
                  : n.params.contains('right')
                  ? TextAlign.right
                  : TextAlign.left,
              style: TextStyle(
                fontSize:
                    widget.store.preferences.fontSize +
                    (n.params.contains('H1') ? 6 : 0),
                height: 1.65,
                fontWeight: n.params.contains('H1')
                    ? FontWeight.w700
                    : FontWeight.normal,
              ),
            ),
          ),
        );
      } else if (n.kind == 'text' && n.text.contains('\n')) {
        final parts = n.text.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) {
            line.add(ContentNode('text', parts[i], n.offset));
          }
          if (i != parts.length - 1) flush();
        }
      } else {
        line.add(n);
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  InlineSpan _span(ContentNode n) {
    final colors = Theme.of(context).colorScheme;
    if (n.kind == 'Ref' || n.kind == 'Card') {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Tooltip(
          message: '预览引用卡片',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.interactive ? () => _reference(n) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                '↗ ${n.text.isEmpty ? '引用卡片' : n.text}',
                style: TextStyle(
                  fontSize: widget.store.preferences.fontSize,
                  color: colors.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (n.kind == 'F') {
      final group = n.params.firstOrNull ?? '1';
      final visible = widget.revealed || _groups.contains(group);
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Semantics(
          button: true,
          label: visible ? n.text : '揭晓第 $group 组挖空',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.interactive
                ? () => setState(() => _groups.add(group))
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                visible ? n.text : '  ··· $group  ',
                style: TextStyle(
                  fontSize: widget.store.preferences.fontSize,
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (n.kind == 'unsupported') {
      return TextSpan(
        text: '〔暂不支持的内容〕\n${n.text}',
        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
      );
    }
    if (n.kind != 'T') return TextSpan(text: n.text);
    Color? color, background;
    for (final p in n.params) {
      if (RegExp(r'^!![0-9a-fA-F]{6}$').hasMatch(p)) {
        background = Color(int.parse('ff${p.substring(2)}', radix: 16));
      } else if (RegExp(r'^![0-9a-fA-F]{6}$').hasMatch(p)) {
        color = Color(int.parse('ff${p.substring(1)}', radix: 16));
      }
    }
    final style = TextStyle(
      fontWeight: n.params.contains('B') ? FontWeight.w700 : null,
      fontStyle: n.params.contains('I') ? FontStyle.italic : null,
      decoration: n.params.contains('U') ? TextDecoration.underline : null,
      color: color,
      backgroundColor: background,
    );
    final link = n.param('link/');
    if (link != null) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: InkWell(
          onTap: () async {
            final uri = Uri.tryParse(link.replaceAll('"', ''));
            if (uri != null && {'http', 'https'}.contains(uri.scheme)) {
              await launchUrl(uri);
            }
          },
          child: Text(
            n.text,
            style: style.copyWith(
              fontSize: widget.store.preferences.fontSize,
              color: colors.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      );
    }
    if (n.params.contains('up') || n.params.contains('down')) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Transform.translate(
          offset: Offset(0, n.params.contains('up') ? -6 : 6),
          child: Text(
            n.text,
            style: style.copyWith(
              fontSize: widget.store.preferences.fontSize * .72,
            ),
          ),
        ),
      );
    }
    return TextSpan(text: n.text, style: style);
  }
}

class _MediaImage extends StatefulWidget {
  const _MediaImage({
    super.key,
    required this.id,
    required this.store,
    required this.replace,
    this.pending,
  });
  final String id;
  final AppStore store;
  final bool replace;
  final Uint8List? pending;
  @override
  State<_MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends State<_MediaImage> {
  late var _future = _load();
  Future<Uint8List?> _load() => widget.pending != null
      ? Future.value(widget.pending)
      : widget.store.media(widget.id);
  late int _revision = widget.store.revision;
  @override
  void didUpdateWidget(_MediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_revision != widget.store.revision || oldWidget.id != widget.id) {
      _revision = widget.store.revision;
      _future = _load();
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: FutureBuilder(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
              height: 260,
              errorBuilder: (_, _, _) => const Text('图片无法解码，原文件仍已保留'),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Icon(Icons.image_outlined, size: 32),
              const SizedBox(height: 8),
              const Text('尚未找到这张图片'),
              Text(
                '媒体 ID：${widget.id}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (widget.replace)
                TextButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.image,
                      withData: true,
                    );
                    final file = result?.files.firstOrNull;
                    if (file?.bytes != null) {
                      await widget.store.addMedia(
                        file!.name,
                        file.bytes!,
                        id: widget.id,
                      );
                      if (mounted) {
                        setState(() => _future = widget.store.media(widget.id));
                      }
                    }
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('关联本地图片'),
                ),
            ],
          ),
        );
      },
    ),
  );
}

/// 写卡悬浮窗中的单个公式或图片预览，随源码实时重绘。
class InlinePreview extends StatelessWidget {
  const InlinePreview({super.key, required this.token, required this.store});
  final InlineToken token;
  final AppStore store;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    if (token.tag == 'Pic') {
      final id = token.params
          .firstWhere((p) => p.startsWith('ID/'), orElse: () => 'ID/')
          .substring(3);
      return _InlineImage(key: ValueKey(id), id: id, store: store);
    }
    final hint = TextStyle(fontSize: 13, color: c.onSurfaceVariant);
    if (token.body.trim().isEmpty) return Text('输入公式后在这里预览', style: hint);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Math.tex(
        token.body,
        mathStyle: MathStyle.display,
        textStyle: TextStyle(
          fontSize: store.preferences.fontSize + 2,
          color: c.onSurface,
        ),
        onErrorFallback: (_) => Text('公式尚未完整', style: hint),
      ),
    );
  }
}

/// 悬浮窗用的紧凑图片：固定高度，加载与重新读取时保留上一张，避免闪烁。
class _InlineImage extends StatefulWidget {
  const _InlineImage({super.key, required this.id, required this.store});
  final String id;
  final AppStore store;
  @override
  State<_InlineImage> createState() => _InlineImageState();
}

class _InlineImageState extends State<_InlineImage> {
  Uint8List? _bytes;
  bool _loaded = false;
  int _revision = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  @override
  void didUpdateWidget(_InlineImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reload();
  }

  void _reload() {
    if (_revision == widget.store.revision) return;
    _revision = widget.store.revision;
    final revision = _revision;
    widget.store.media(widget.id).then((bytes) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _bytes = bytes;
        _loaded = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final hint = TextStyle(fontSize: 13, color: c.onSurfaceVariant);
    return SizedBox(
      height: 120,
      child: _bytes != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                _bytes!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    Center(child: Text('图片无法解码', style: hint)),
              ),
            )
          : Center(
              child: _loaded
                  ? Text('尚未找到这张图片', style: hint)
                  : const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
            ),
    );
  }
}
