import 'package:flutter/material.dart';

import 'crosshair.dart' show mcGuiScaleOf;

/// 聊天/消息浮层（原版 `client/gui/components/ChatComponent` 的**显示部分**）。
///
/// debug 信息流：左下角逐行显示系统消息（如服务器回拉量），按原版消息
/// 时序自动淡出。仅显示，无输入框（输入框另有 `MCEditBox` 口径）。
///
/// **判据**（mc-sources/minecraft-26.2 `ChatComponent.java:484-497`
/// `AlphaCalculator.timeBased`）：
///
/// ```java
/// int tickDelta = currentTickTime - message.addedTime();
/// double t = 1.0 - tickDelta / 200.0;
/// t = Mth.clamp(t * 10.0, 0.0, 1.0);
/// t *= t;
/// ```
///
/// 即：消息加入后 **180 刻（9s）内 alpha 恒 1**，最后 20 刻（1s）按
/// **二次曲线**淡出，200 刻（10s）整行消失。tickDelta 换算成秒：
/// `alpha = clamp(10 × (1 − delta/10), 0, 1)²`。
///
/// 重建节奏由调用方驱动（见 [GuiMessage] 注释）；本组件只在 build 时
/// 读取当前时刻计算 alpha，自身不持有定时器（无状态、可测试）。
class MCChatComponent extends StatelessWidget {
  const MCChatComponent({super.key, required this.messages});

  /// 当前待显示消息（**旧 → 新**，最新在最下，同原版）。
  final List<GuiMessage> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    final s = mcGuiScaleOf(context);
    final now = DateTime.now();
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in messages)
            Opacity(
              // 判据 ChatComponent.java:488-496：clamp(10×(1−Δ/200刻))²。
              opacity: alphaOf(m, now),
              child: Padding(
                // MESSAGE_INDENT = 4 GUI 像素（ChatComponent.java:46）。
                padding: EdgeInsets.all(2 * s),
                child: Text(
                  m.text,
                  // 原版聊天字体 9pt 白字黑影（低配近似；贴图字体另有资源口径）。
                  style: TextStyle(
                    fontSize: 9 * s,
                    color: const Color(0xFFFFFFFF),
                    shadows: [
                      Shadow(offset: Offset(1 * s, 1 * s), color: Colors.black),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// `clamp(10 × (1 − delta/200刻), 0, 1)²`（秒口径，见类注释）。
  static double alphaOf(GuiMessage m, DateTime now) {
    final deltaSec =
        now.difference(m.addedAt).inMicroseconds / Duration.microsecondsPerSecond;
    var t = 10.0 * (1.0 - deltaSec / 10.0);
    t = t.clamp(0.0, 1.0);
    return t * t;
  }
}

/// 一条浮层消息（原版 `client/gui/GuiMessage`：addedTime + 文本）。
///
/// 时序字段用挂钟时刻（调用方按 100ms 量级定时重建即可驱动淡出；
/// 200 刻 = 10s 的语义见 [MCChatComponent] 类注释）。过期清理与条数
/// 上限由调用方负责（原版 `ChatComponent.refreshTrimmedMessages` 保留
/// 最近 100 条，`allMessages` 同口径）。
class GuiMessage {
  GuiMessage(this.text, {DateTime? at}) : addedAt = at ?? DateTime.now();

  final DateTime addedAt;
  final String text;
}
