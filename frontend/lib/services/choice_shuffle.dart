// 选项展示层打乱：只影响「页面展示顺序」，提交前把用户选择的展示字母
// 映回原始字母再上送，后端判分逻辑完全不变（answer 仍对应原始选项顺序）。
import 'dart:math';

/// 生成展示顺序：返回 origAt，其中 origAt[pos] = 该展示位置对应的原始选项索引。
/// 选项个数 n<=1 时原样返回（不打乱）。
List<int> shuffledOptionOrder(int n, Random rng) {
  final idx = List<int>.generate(n, (i) => i);
  if (n > 1) idx.shuffle(rng);
  return idx;
}

/// 把「用户在展示位置 pos 选的字母」映回「原始选项字母」。
String displayLetterToOrig(int displayPos, List<int> origAt) =>
    String.fromCharCode(65 + origAt[displayPos]);
