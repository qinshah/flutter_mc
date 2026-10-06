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
  try {
    handle = await connector(server, kPlayerName);
    // 首个事件定成败：JoinedGame = 进服，SessionClosed = 失败（含连接被拒/版本不符）。
    final first = await handle.events.first.timeout(kJoinTimeout);
    if (!context.mounted) {
      handle.close();
      return;
    }
    if (first is SessionClosed) {
      handle.close();
      _showError(context, '无法加入 ${server.name}：${first.reason}');
      return;
    }

    // 进服成功 → 携带会话句柄进游戏屏（design D6）。
    final result = await Navigator.pushNamed(
      context,
      '/game',
      arguments: GameArgs(session: handle, serverName: server.name),
    );
    if (!context.mounted) return;
    if (result is String && result.isNotEmpty) {
      _showError(context, '已断开与 ${server.name} 的连接：$result');
    }
  } on UnsupportedProtocolError catch (e) {
    handle?.close();
    if (context.mounted) _showError(context, '$e');
  } on TimeoutException {
    handle?.close();
    if (context.mounted) {
      _showError(
        context,
        '连接 ${server.name} 超时（${kJoinTimeout.inSeconds} 秒无响应）',
      );
    }
  } catch (e) {
    handle?.close();
    if (context.mounted) _showError(context, '无法加入 ${server.name}：$e');
  }
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
  );
}
