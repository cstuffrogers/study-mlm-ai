// 默认演示用户（单机版无登录态，学习数据仅存本机）
const String kDemoUserId = 'demo_user';

/// 单机版没有后端地址；保留该函数只为兼容旧调用点的提示文案。
String apiBase() => '本机存储（无需后端）';
