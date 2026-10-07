import 'package:flutter/material.dart';
import 'package:mc_session/mc_session.dart';
import 'package:mc_ui/mc_ui.dart';

import '../screen.dart';

/// 原版 `ManageServerScreen` 的简化对应：名称 + 地址表单（添加/编辑共用），
/// 完成即持久化（ServerList.add/editAt），取消退栈。
class ManageServerScreen extends StatefulWidget {
  const ManageServerScreen({super.key, required this.args});

  final ManageServerArgs args;

  @override
  State<ManageServerScreen> createState() => _ManageServerScreenState();
}

class _ManageServerScreenState extends State<ManageServerScreen> {

  late final _name = TextEditingController(
    text: widget.args.editIndex == null
        ? ''
        : widget.args.list[widget.args.editIndex!].name,
  );
  late final _address = TextEditingController(
    text: widget.args.editIndex == null
        ? ''
        : widget.args.list[widget.args.editIndex!].ip,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final s = mcScaleForWidth(constraints.maxWidth);
    final editing = widget.args.editIndex != null;
    return McScreen(
      title: editing ? '编辑服务器信息' : '添加服务器',
      body: (context) => Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 60 * s, vertical: 8 * s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field('服务器名称', _name, s),
                  SizedBox(height: 8 * s),
                  _field('服务器地址', _address, s),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(4 * s),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MCButton(
                  width: 98 * s,
                  height: 20 * s,
                  label: '完成',
                  onPress: () {
                    if (_name.text.trim().isEmpty || _address.text.trim().isEmpty) {
                      return;
                    }
                    final data = ServerData(
                      name: _name.text.trim(),
                      ip: _address.text.trim(),
                    );
                    final index = widget.args.editIndex;
                    if (index == null) {
                      widget.args.list.add(data);
                    } else {
                      widget.args.list.editAt(index, data);
                    }
                    Navigator.pop(context);
                  },
                ),
                SizedBox(width: 4 * s),
                MCButton(
                  width: 98 * s,
                  height: 20 * s,
                  label: '取消',
                  onPress: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
      });
  }

  Widget _field(String label, TextEditingController controller, double s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: const Color(0xFF9E9E9E), fontSize: 7 * s, height: 1.0),
        ),
        SizedBox(height: 2 * s),
        MCEditBox(controller: controller, width: double.infinity, height: 20 * s),
      ],
    );
  }
}

class ManageServerArgs {
  ManageServerArgs({required this.list, this.editIndex});
  final ServerList list;
  final int? editIndex;
}
