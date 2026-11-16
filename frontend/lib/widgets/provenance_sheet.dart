// 溯源卡片组件 — FR-017 句子级溯源

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/content_service_api.dart';
import '../widgets/speak_button.dart';
import 'chat_markdown.dart';
import 'chunk_tag.dart';

class ProvenanceSheet extends StatelessWidget {
  final List<ProvenanceCard> cards;
  const ProvenanceSheet({super.key, required this.cards});

  static const _layerLabel = {1: '原文', 2: '命题', 3: '注释', 4: '解析'};

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('无溯源信息', style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.all(12),
      itemCount: cards.length,
      itemBuilder: (_, i) {
        final c = cards[i];
        return Card(
          elevation: 0,
          color: const Color(0xFFFBF7F5),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC8161D),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _layerLabel[c.layer] ?? 'L${c.layer}',
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${c.source} · ${c.location}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    SpeakButton(
                      id: 'prov-${c.chunkId}',
                      compact: true,
                      text: ChatMarkdown.toSpeech(c.excerpt),
                      resolveText: () async {
                        try {
                          final full = await ContentApi().chunk(c.chunkId);
                          final t = (full['text'] ?? '').toString();
                          return t.trim().isEmpty ? ChatMarkdown.toSpeech(c.excerpt) : ChatMarkdown.toSpeech(t);
                        } catch (_) {
                          return ChatMarkdown.toSpeech(c.excerpt);
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '权威 ${(c.authorityScore * 100).round()}%',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(c.excerpt, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 13, color: Color(0xFFC8161D)),
                    label: const Text('查看完整原文',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFFC8161D))),
                    onPressed: () => showChunkCard(context, c.chunkId, fallbackText: c.excerpt),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _checkChip('事实', c.factCheck),
                    _checkChip('术语', c.terminologyCheck),
                    _checkChip('立场', c.stanceCheck),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _checkChip(String label, String status) {
    final ok = status == 'pass';
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle : Icons.warning,
              size: 12, color: Color(ok ? 0xFF10B981 : 0xFFE11D48)),
          const SizedBox(width: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
        ],
      ),
    );
  }
}
