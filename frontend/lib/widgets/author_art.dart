// 红白人物像：把 pic/red 的红白图按著作著者贴到红色头部右侧。
// 红底透明（PNG alpha），所以叠在任何红色渐变上都不会露出色块边。
import 'package:flutter/material.dart';

/// 著者 → 红白像。顺序即匹配优先级（马克思、恩格斯合著归到马克思）。
const _authorArt = <(String, String)>[
  ('马克思', 'pic/red/red2.png'),
  ('恩格斯', 'pic/red/red3.png'),
  ('列宁', 'pic/red/red4.png'),
  ('斯大林', 'pic/red/red5.png'),
  ('毛泽东', 'pic/red/red6.png'),
  ('周恩来', 'pic/red/red7.png'),
  ('托洛茨基', 'pic/red/red8.png'),
  ('拖洛夫斯基', 'pic/red/red8.png'), // 兼容旧写法
];

/// 至今通用的红白图（首页顶部右侧）。
const kHomeArt = 'pic/red/red1.png';

/// 各红白像的宽高比（= 资源 PNG 的真实像素比）。
/// 头部布局要在**不解码图片**的前提下预留出图片占位，否则横幅图
/// （red1.png 706x463）会横着盖住标题——用户实报「大标题被人物头像遮住」。
const _aspect = <String, double>{
  'pic/red/red1.png': 706 / 463,
  'pic/red/red2.png': 348 / 362,
  'pic/red/red3.png': 221 / 282,
  'pic/red/red4.png': 506 / 642,
  'pic/red/red5.png': 516 / 520,
  'pic/red/red6.png': 750 / 1000,
  'pic/red/red7.png': 849 / 980,
  'pic/red/red8.png': 621 / 738,
};

/// 按著者名找红白像资源；找不到返回 null（不显示）。
String? authorArtFor(String? author) {
  if (author == null || author.isEmpty) return null;
  for (final (name, asset) in _authorArt) {
    if (author.contains(name)) return asset;
  }
  return null;
}

class AuthorArt extends StatelessWidget {
  /// 著者名（会做包含匹配）；也可用 [asset] 直接指定。
  final String? author;
  final String? asset;
  final double height;
  final double opacity;

  const AuthorArt({
    super.key,
    this.author,
    this.asset,
    this.height = 108,
    this.opacity = 1,
  });

  /// 按高度算出这张图**会占多宽**（缺省 0.85 是竖版人像的中位比例）。
  /// 布局方（GradientHeader）用它预留空间，避免标题被图片压住。
  static double widthFor({String? author, String? asset, required double height}) {
    final path = asset ?? authorArtFor(author);
    if (path == null) return 0;
    return height * (_aspect[path] ?? 0.85);
  }

  @override
  Widget build(BuildContext context) {
    final path = asset ?? authorArtFor(author);
    if (path == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Image.asset(
          path,
          height: height,
          // 显式给出宽度：与 widthFor() 同一套比例，图片本身不变形，
          // 但布局能拿到确定尺寸（BoxFit.contain 在无宽约束时会撑满父级）。
          width: widthFor(asset: path, height: height),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
