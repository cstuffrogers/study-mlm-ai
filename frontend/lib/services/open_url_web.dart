// 外部链接打开 —— Web 实现（package:web，新标签页）。仅 Web 端可用。
import 'package:web/web.dart' as web;

void openExternal(String url) {
  try {
    web.window.open(url, '_blank');
  } catch (_) {
    // 忽略：非 Web 或浏览器拦截
  }
}
