import 'package:flutter/material.dart';

import '../screen.dart';

/// gui/screens/multiplayer/ServerSelectionList.java 的对应：服务器条目列表。
/// 本期含一条硬编码示例条目（design D5），servers.dat 读写随后续连接 change。
class ServerSelectionList extends StatelessWidget {
  const ServerSelectionList({super.key});

  @override
  Widget build(BuildContext context) {
    final s = mcGuiScale(MediaQuery.sizeOf(context)).toDouble();
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.all(4 * s),
      children: [
        Container(
          color: const Color(0xAA000000),
          padding: EdgeInsets.all(4 * s),
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
                      'localhost',
                      style: TextStyle(color: const Color(0xFFE0E0E0), fontSize: 8 * s, height: 1.0),
                    ),
                    SizedBox(height: 3 * s),
                    Text(
                      '无法连接至服务器',
                      style: TextStyle(color: const Color(0xFFFF5555), fontSize: 8 * s, height: 1.0),
                    ),
                  ],
                ),
              ),
              // 删除叉钮占位（原版为红色叉形贴图按钮）。
              Text(
                '✕',
                style: TextStyle(
                  color: const Color(0xFFFF5555),
                  fontSize: 10 * s,
                  fontWeight: FontWeight.bold,
                  backgroundColor: const Color(0xFF000000),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
