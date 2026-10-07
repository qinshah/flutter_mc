import 'package:flutter/material.dart';
import 'package:mc_ui/mc_ui.dart';

import '../screen.dart';

/// gui/screens/options/VideoSettingsScreen.java 的对应：分组"显示"与
/// "品质与性能"的设置项。取值仅存于本界面内存态（无 Options 持久化，
/// 对应 spec client-screens：重进回默认值）；Options 系统随后续 change。
class VideoSettingsScreen extends StatefulWidget {
  const VideoSettingsScreen({super.key});

  @override
  State<VideoSettingsScreen> createState() => _VideoSettingsScreenState();
}

class _VideoSettingsScreenState extends State<VideoSettingsScreen> {
  // 滑条为受控取值；循环按钮的取值由控件内部承载——重进即重置（无持久化），
  // Options 持久化随后续 change 落地时再上收为受控状态。
  double _fullscreenResolution = 0; // 当前分辨率（滑条居左）
  double _maxFps = 1; // 无限制（滑条居右）
  double _brightness = 1; // 明亮

  void _onCycleChanged(String value) {}

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final s = mcScaleForWidth(constraints.maxWidth);
    final gap = SizedBox(width: 8 * s);
    return McScreen(
      title: '视频设置',
      body: (context) => Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: 50 * s, vertical: 8 * s),
              children: [
                _section('显示', s),
                MCSliderButton(
                  key: const Key('video.fullscreen-resolution'),
                  width: double.infinity,
                  height: 20 * s,
                  label: '全屏分辨率',
                  value: _fullscreenResolution,
                  valueText: (_) => '当前分辨率',
                  onChanged: (v) => setState(() => _fullscreenResolution = v),
                ),
                SizedBox(height: 8 * s),
                Row(
                  children: [
                    Expanded(
                      child: MCSliderButton(
                        key: const Key('video.max-fps'),
                        height: 20 * s,
                        label: '最大帧率',
                        value: _maxFps,
                        valueText: (v) => v >= 1 ? '无限制' : '${(v * 260).round()}',
                        onChanged: (v) => setState(() => _maxFps = v),
                      ),
                    ),
                    gap,
                    Expanded(
                      child: MCCycleButton<String>(
                        width: double.infinity,
                        height: 20 * s,
                        label: '垂直同步',
                        values: const ['关', '开'],
                        valueText: (v) => v,
                        onChanged: _onCycleChanged,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8 * s),
                Row(
                  children: [
                    Expanded(
                      child: MCCycleButton<String>(
                        width: double.infinity,
                        height: 20 * s,
                        label: '降低帧率',
                        values: const ['关', '无操作时', '始终'],
                        valueText: (v) => v,
                        initialIndex: 1,
                        onChanged: _onCycleChanged,
                      ),
                    ),
                    gap,
                    Expanded(
                      child: MCCycleButton<String>(
                        width: double.infinity,
                        height: 20 * s,
                        label: '界面尺寸',
                        values: const ['自动', '1', '2', '3', '4'],
                        valueText: (v) => v,
                        onChanged: _onCycleChanged,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8 * s),
                Row(
                  children: [
                    Expanded(
                      child: MCCycleButton<String>(
                        width: double.infinity,
                        height: 20 * s,
                        label: '全屏',
                        values: const ['关', '开'],
                        valueText: (v) => v,
                        onChanged: _onCycleChanged,
                      ),
                    ),
                    gap,
                    Expanded(
                      child: MCCycleButton<String>(
                        width: double.infinity,
                        height: 20 * s,
                        label: '独占全屏',
                        values: const ['关', '开'],
                        valueText: (v) => v,
                        onChanged: _onCycleChanged,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8 * s),
                Row(
                  children: [
                    Expanded(
                      child: MCSliderButton(
                        height: 20 * s,
                        label: '亮度',
                        value: _brightness,
                        valueText: (v) =>
                            v <= 0 ? '昏暗' : (v >= 1 ? '明亮' : '${(v * 100).round()}%'),
                        onChanged: (v) => setState(() => _brightness = v),
                      ),
                    ),
                    gap,
                    Expanded(
                      child: MCCycleButton<String>(
                        width: double.infinity,
                        height: 20 * s,
                        label: '图形API',
                        values: const ['原生', '优先使用 OpenGL', '优先使用 Vulkan（实验性'],
                        valueText: (v) => v,
                        initialIndex: 2,
                        onChanged: _onCycleChanged,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16 * s),
                _section('品质与性能', s),
                MCCycleButton<String>(
                  width: double.infinity,
                  height: 20 * s,
                  label: '预设',
                  values: const ['自定义', '低', '中', '高'],
                  valueText: (v) => v,
                  onChanged: _onCycleChanged,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(4 * s),
            child: Center(
              child: MCButton(
                width: 200 * s,
                height: 20 * s,
                label: '完成',
                onPress: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
      });
  }

  Widget _section(String text, double s) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: EdgeInsets.only(bottom: 4 * s),
          child: Text(
            text,
            style: TextStyle(color: const Color(0xFFE0E0E0), fontSize: 8 * s, height: 1.0),
          ),
        ),
      );
}
