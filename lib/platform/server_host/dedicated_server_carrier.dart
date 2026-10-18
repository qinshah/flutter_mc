// 被托管服务端的**承载接口**（第三类自由设计「运行时宿主（JVM 托管）」的契约面）。
//
//   两块承载实现共用这一条接口，装配点按平台选实现，业务代码不按平台 / 版本分支：
//     · 桌面：子进程承载 —— `dedicated_server_process.dart`（`Process.start(java -jar ...)`）
//     · Android：专用子进程承载 —— `android_subprocess_jvm_host.dart`
//       （`:jvm` 子进程内 dlopen JRE + `JNI_CreateJavaVM`；一次会话一个子进程）
//
//   上层契约（实例目录 / 配置读写 / EULA / 就绪判定 / 管理服务器与 RCON）完全平台无关，
//   不在此接口内——见 spec「与桌面承载层共享同一契约面」。
//
//   ⚠ 原版无对应物：原版 `server/Main.java` 假定 JVM 已存在、只解析命令行选项
//   （`server/Main.java:72-73`），"谁来承载 JVM、输出如何采集、何时算就绪"由外层脚本承担。
//   故此处为承载方式豁免；被托管物（服务端本体）照旧是翻译债（openspec/progress.md）。

import 'artifact_resolver.dart';

/// 宿主视角的服务端状态（两块承载共用）。
enum ServerState { stopped, starting, ready, stopping, failed }

/// 被托管服务端的承载接口：启动 / 停止 / 状态 / 日志 / 退出码。
///
/// 语义（两块实现 MUST 一致，判据均为原版）：
///   · 就绪 SHALL 只认原版就绪行（判据 `server/dedicated/DedicatedServer.java:246`）；
///   · 实际监听端口 SHALL 取自原版日志行（判据 `DedicatedServer.java:210`）；
///   · 绑定失败 SHALL 取自原版标记（判据 `DedicatedServer.java:215`）；
///   · 异常退出 SHALL 暴露退出码，日志 SHALL 保留。
abstract class DedicatedServerCarrier {
  // ── 两块承载共用的原版判据（唯一真身；两块实现均引用这里，不各写一份） ──

  /// 就绪行（判据 `server/dedicated/DedicatedServer.java:246`）：
  /// `Done (<耗时>)! For help, type "help"`。
  static final RegExp readyLine =
      RegExp(r'Done \(.+\)! For help, type "help"');

  /// 绑定失败标记（判据 `DedicatedServer.java:215`）。
  static const String bindFailedMarker = '**** FAILED TO BIND TO PORT!';

  /// 监听端口日志行（判据 `DedicatedServer.java:210`）：
  /// `Starting Minecraft server on <host>:<port>`。
  static final RegExp listeningLine =
      RegExp(r'Starting Minecraft server on .*:(\d+)');

  /// 宿主视角状态。
  ServerState get state;

  /// 被托管服务端退出码（未退出为 null）。
  int? get exitCode;

  /// 是否检出原版"绑定失败"标记。
  bool get bindFailed;

  /// 是否处于"已启动"（启动中或已就绪）。
  bool get isRunning;

  /// 最近日志（供 UI 面板初次渲染），上限由实现定。
  List<String> get recentLogs;

  /// 实际监听端口（取自原版日志行；未回显时为 null）。
  int? get listeningPort;

  /// 状态变更流。
  Stream<ServerState> get stateChanges;

  /// 日志行流（增量）。
  Stream<String> get logLines;

  /// 启动被托管服务端（阻塞至"已起"或失败）。
  Future<void> start(ServerArtifacts artifacts);

  /// 优雅停止（下发停止请求并等待退出）；超出等待上限 SHALL 回落强制终止
  /// （spec「进程生命周期可控可观测」：桌面子进程 kill / Android 承载子进程 `nativeKill`）。
  Future<void> stop();

  /// 回收被托管服务端（应用退出/宿主重载时调用，spec「MUST NOT 残留孤儿进程」）。
  ///
  /// 桌面：强杀残留子进程；Android：对承载子进程（`:jvm`）下发 SIGKILL 并清理 pidFile
  /// （子进程心跳 watchdog 兜底"主进程异常死亡"路径，见 `android_subprocess_jvm_host.dart`）。
  void reap();

  /// 释放资源。
  Future<void> dispose();
}
