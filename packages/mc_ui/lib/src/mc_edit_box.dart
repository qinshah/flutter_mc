import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 原版 `gui/components/EditBox` 的 Flutter 对应：暗底矩形、细边框
/// （失焦灰、聚焦白）、白字；文本编辑经 Flutter 原生输入设施。
/// 宽高为最终像素（缺省取父级约束），高缺省 20（原版 GUI 像素）。
class MCEditBox extends StatelessWidget {
  const MCEditBox({
    super.key,
    this.controller,
    this.enabled = true,
    this.width,
    this.height = 20,
    this.hintText,
    this.autofocus = false,
    this.inputFormatters,
  });

  final TextEditingController? controller;
  final bool enabled;
  final double? width;
  final double height;
  final String? hintText;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;

  static const Color colorBorderDisabled = Color(0xFF5A5A5A);
  static const Color colorBorder = Color(0xFFA0A0A0);
  static const Color colorBorderFocused = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    final fontSize = height * 0.42;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: color, width: 1),
        );
    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(width: width, height: height),
      child: TextField(
        controller: controller,
        enabled: enabled,
        autofocus: autofocus,
        inputFormatters: inputFormatters,
        cursorColor: const Color(0xFFE0E0E0),
        style: TextStyle(
          color: enabled ? const Color(0xFFE0E0E0) : const Color(0xFF9E9E9E),
          fontSize: fontSize,
          height: 1.0,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFF000000),
          hintText: hintText,
          hintStyle: TextStyle(color: const Color(0xFF6E6E6E), fontSize: fontSize),
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: height * 0.18),
          isDense: true,
          enabledBorder: border(enabled ? colorBorder : colorBorderDisabled),
          focusedBorder: border(colorBorderFocused),
          disabledBorder: border(colorBorderDisabled),
        ),
      ),
    );
  }
}
