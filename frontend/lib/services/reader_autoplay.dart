// 连续朗读（原文阅读器的「自动连续发声」）—— 纯逻辑，可单测。
//
// 三种模式（用户在原文页点「自动连续发声」后选）：
//   pageLoop  当前页循环播放：本页读完从头再读，一直循环；
//   toEnd     从当前页播到结束：读完一页自动翻下一页，读到全书末尾停；
//   bookLoop  播完再整篇循环：读完一页自动翻下一页，到末尾回到第一页继续。
//
// 为什么单独拆出来：`nextAutoPage` 决定「念完这一页之后念哪一页」，
// 是三种模式唯一的差异点，也是最容易写错的地方（末页回头 / 整篇回卷 / 单页书）。
// 放在纯函数里可以直接断言，不必去戳 TTS 通道。
//
// 性能红线：本文件不含 Timer / 动画 / 网络，只有一次取模或加法。

/// 连续朗读的三种模式。
enum ReaderAutoMode {
  pageLoop('当前页循环播放', '本页读完从头再读，一直循环', '本页循环'),
  toEnd('从当前页播到结束', '念完一页自动翻下一页，到全书末尾停', '播到结尾'),
  bookLoop('播完再整篇循环', '念完一页自动翻下一页，到末尾回到第一页继续', '整篇循环');

  const ReaderAutoMode(this.label, this.hint, this.short);

  /// 选项标题（弹层里的一行）。
  final String label;

  /// 一句话说明，讲清「念完这页之后会怎样」。
  final String hint;

  /// 状态条上用的短名（底部栏就那么宽，塞不下 [label]）。
  final String short;
}

/// 念完 [current] 这一页之后该念哪一页；返回 null 表示「到此结束，不必再念」。
///
/// · pageLoop：永远返回自己（单页书也成立，等于反复念这一页）；
/// · toEnd：末页返回 null（停止）；
/// · bookLoop：始终回到第 0 页继续（单页书等于 pageLoop）。
///
/// [pageCount] <= 0（还没分好页）时返回 null，避免调用方念一个不存在的页。
int? nextAutoPage({
  required ReaderAutoMode mode,
  required int current,
  required int pageCount,
}) {
  if (pageCount <= 0) return null;
  final cur = current < 0 ? 0 : (current >= pageCount ? pageCount - 1 : current);
  switch (mode) {
    case ReaderAutoMode.pageLoop:
      return cur;
    case ReaderAutoMode.toEnd:
      return cur + 1 < pageCount ? cur + 1 : null;
    case ReaderAutoMode.bookLoop:
      return (cur + 1) % pageCount;
  }
}
