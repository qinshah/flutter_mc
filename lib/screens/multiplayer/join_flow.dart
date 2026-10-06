import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mc_session/mc_session.dart';

import '../../routes.dart';

/// 装配点连接的注入点（`(server, playerName) → SessionHandle`）。
///
/// 独立成 typedef 是为了**可测**：widget 测试注入一个假连接器，就能覆盖
/// "连接失败报错"与"进服成功进游戏屏"两条分支，不必起真服务器。
typedef JoinConnector = Future<SessionHandle> Function(
  ServerData server,
  String playerName,
);

/// 本客户端上报的玩家名（本项目无账号体系，取固定名）。
const String kPlayerName = 'flutter_mc';

/// 默认连接器：走版本装配点（协议号由 `ServerData.protocol` 决定，业务代码看不见版本）。
Future<SessionHandle> defaultJoinConnector(
  ServerData server,
  String playerName,
) =>
    SessionAssembly.connectFor(server, playerName: playerName);

/// 等待"进服成功/失败"的上限。原版 `ConnectScreen` 也会在超时后放弃；
/// 这里防的是 SYN 黑洞这类"既没成功也没报错"的连接。
const Duration kJoinTimeout = Duration(seconds: 30);

/// 加入服务器的公共流程（多人屏"加入服务器"与"直接连接"共用）。
///
/// 原版对应物：`client.gui.screens.ConnectScreen`——原版把"连接中"做成独立一屏并在
/// 其上显示失败原因；本仓简化为"就地等待 → 失败 SnackBar 留在列表 / 成功进游戏屏"。
Future<void> joinServer(
  BuildContext context, {
  required ServerData server,
  required JoinConnector connector,
}) async {
  SessionHandle? handle;
  StreamController<SessionEvent>? relay;
  try {
    handle = await connector(server, kPlayerName);

    // **先挂转发再等首个事件**：会话事件流是 broadcast，晚订阅者拿不到早先的事件，
    // 而"进游戏屏"要经过一次路由跳转 + 游戏屏的启动（引擎静态资源 + 图集/模型），
    // 好几秒里到达的事件会全部丢掉——**初始的 PlayerPosition 传送包正是最早那条**。
    // 丢了它客户端就不知道自己在哪（停在原点），移动门禁也永远等不到"脚下列已加载"。
    //
    // 这里用**单订阅** StreamController：无人监听时它会缓冲，broadcast 不会；
    // 游戏屏只订阅一次，正好合适。
    relay = StreamController<SessionEvent>();
    handle.events.listen(
      (event) {
        if (relay != null && !relay.isClosed) relay.add(event);
      },
      onDone: () {
        if (relay != null && !relay.isClosed) relay.close();
      },
    );

    // 首个事件定成败：JoinedGame = 进服，SessionClosed = 失败（含连接被拒/版本不符）。
    final first = await handle.events.first.timeout(kJoinTimeout);
    if (!context.mounted) {
      handle.close();
      return;
    }
    if (first is SessionClosed) {
      handle.close();
      unawaited(relay.close());
      _showError(context, '无法加入 ${server.name}：${first.reason}');
      return;
    }

    // 进服成功 → 携带会话句柄 + **已缓冲的事件流**进游戏屏（design D6）。
    final result = await Navigator.pushNamed(
      context,
      '/game',
      arguments: GameArgs(
        session: handle,
        events: relay.stream,
        serverName: server.name,
      ),
    );
    // 同理不 await：await 后再用 context 会触发 use_build_context_synchronously。
    if (!relay.isClosed) unawaited(relay.close());
    if (!context.mounted) return;
    if (result is String && result.isNotEmpty) {
      _showError(context, '已断开与 ${server.name} 的连接：$result');
    }
  } on UnsupportedProtocolError catch (e) {
    handle?.close();
    // 失败分支不把 relay 交出去，关掉即可；不 await（await 后再用 context 会触发
    // use_build_context_synchronously）。
    final failed = relay;
    if (failed != null && !failed.isClosed) unawaited(failed.close());
    if (context.mounted) _showError(context, '$e');
  } on TimeoutException {
    handle?.close();
    // 失败分支不把 relay 交出去，关掉即可；不 await（await 后再用 context 会触发
    // use_build_context_synchronously）。
    final failed = relay;
    if (failed != null && !failed.isClosed) unawaited(failed.close());
    if (context.mounted) {
      _showError(
        context,
        '连接 ${server.name} 超时（${kJoinTimeout.inSeconds} 秒无响应）',
      );
    }
  } catch (e) {
    handle?.close();
    // 失败分支不把 relay 交出去，关掉即可；不 await（await 后再用 context 会触发
    // use_build_context_synchronously）。
    final failed = relay;
    if (failed != null && !failed.isClosed) unawaited(failed.close());
    if (context.mounted) _showError(context, '无法加入 ${server.name}：$e');
  }
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
  );
}
