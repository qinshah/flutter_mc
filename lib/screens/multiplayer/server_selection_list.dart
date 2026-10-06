import 'package:flutter/material.dart';
import 'package:mc_session/mc_session.dart';

import '../screen.dart';

/// gui/screens/multiplayer/ServerSelectionList.java 的对应：真实服务器
/// 条目列表（数据来自 ServerList），条目两行：名称 + 探测状态行。
class ServerSelectionList extends StatelessWidget {
  const ServerSelectionList({
    super.key,
    required this.servers,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<ServerData> servers;
  final int selectedIndex;
  final void Function(int index) onSelected;

  @override
  Widget build(BuildContext context) {
    final s = mcGuiScale(MediaQuery.sizeOf(context)).toDouble();
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.all(4 * s),
      itemCount: servers.length,
      itemBuilder: (context, index) {
        final server = servers[index];
        final selected = index == selectedIndex;
        return GestureDetector(
          onTap: () => onSelected(index),
          child: Container(
            margin: EdgeInsets.only(bottom: 2 * s),
            padding: EdgeInsets.all(4 * s),
            decoration: BoxDecoration(
              color: const Color(0xAA000000),
              border: Border.all(
                color: selected ? const Color(0xFFFFFFFF) : const Color(0x00000000),
                width: s,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 服务器图标占位（原版为条目 favicon）。
                Container(width: 32 * s, height: 32 * s, color: const Color(0xFF8B8B8B)),
                SizedBox(width: 6 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFFE0E0E0),
                          fontSize: 8 * s,
                          height: 1.0,
                        ),
                      ),
                      SizedBox(height: 3 * s),
                      Text(
                        _statusLine(server),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _statusColor(server),
                          fontSize: 8 * s,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _statusLine(ServerData server) {
    if (server.pingInfo != null) {
      final info = server.pingInfo!;
      return '${info.motd} · ${info.playersOnline}/${info.playersMax} · 协议 ${info.protocolId}';
    }
    if (server.pingFailed) return '无法连接至服务器';
    return '正在探测…';
  }

  Color _statusColor(ServerData server) {
    if (server.pingFailed) return const Color(0xFFFF5555);
    return const Color(0xFFE0E0E0);
  }
}
