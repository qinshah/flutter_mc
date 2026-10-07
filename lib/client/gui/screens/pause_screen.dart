import 'package:flutter/material.dart';
import 'package:mc_ui/mc_ui.dart';

import '../../../screens/screen.dart' show mcScaleForWidth;
import 'screen.dart';

/// `net/minecraft/client/gui/screens/PauseScreen.java` 的 Dart 对应物。
///
/// **判据**：
/// - `:72-75` 构造：`PauseScreen(showPauseMenu)`，标题 `showPauseMenu ? GAME
///   : PAUSED`（`menu.game` = "游戏菜单" / `menu.paused` = "游戏已暂停"）；
/// - `:82-89` `init`：标题 StringWidget 居中（showPauseMenu 时 y=40）；
/// - `:91-98` "回到游戏"：宽 204、跨两列、paddingTop 50；onPress =
///   `gui.setScreen(null)` + `mouseHandler.grabMouse()`（:96-97）；
/// - `:99-100` 进度 / 统计信息：`openScreenButton` 宽 98（`:264-266`）；
/// - `:102-137` 图标行：报告漏洞 / 发送反馈 / 好友 / 举报玩家，20 宽、间距 4、
///   水平居中；报告漏洞按 `:107` 的 `isSideSeries` 口径置灰；
/// - `:157-162` **联机分支**（本仓恒走此分支，`hasSingleplayerServer()=false`）：
///   "选项..." 宽 204 全宽、**无**"对局域网开放"按钮；
/// - `:164-175` 底部断开按钮：文案 `disconnectButtonLabel(isLocalServer=false)`
///   = `menu.disconnect` = "断开连接"（`CommonComponents.java:54`），onPress
///   先 `button.active = false`（:168）再断开。
///
/// **置灰说明**：进度/统计/好友/举报/选项 对应的屏幕（AdvancementsScreen /
/// StatsScreen / FriendsOverlayScreen / SocialInteractionsScreen / OptionsScreen）
/// 本仓未实现，置灰并登记翻译债（`openspec/progress.md` §8）。报告漏洞/发送反馈
/// 是浏览器外链（`ConfirmLinkScreen`），红线"无外联" ⇒ 恒置灰。
///
/// **背景**：原版对游戏画面做模糊；本仓暂用半透明黑遮罩（无后期管线——
/// 观感债，随 GUI 屏幕债一并补）。
class PauseScreen extends Screen {
  /// 判据 `:72-75`：`PauseScreen(showPauseMenu)` → 标题取
  /// `showPauseMenu ? GAME : PAUSED`。[onDisconnect] 对应原版
  /// `minecraft.disconnectFromWorld`（`Gui` 持有注入，见 Gui.disconnectFromWorld）。
  PauseScreen(this.onDisconnect, {bool showPauseMenu = true})
      : showPauseMenu = showPauseMenu,
        super(showPauseMenu ? gameTitle : pausedTitle);

  /// 判据 `:63` `GAME = menu.game`；`:64` `PAUSED = menu.paused`。
  static const String gameTitle = '游戏菜单';
  static const String pausedTitle = '游戏已暂停';

  /// 判据 `:69` `showPauseMenu`（联机 pauseGame 恒 true，见 Gui.pauseGame）。
  final bool showPauseMenu;

  /// 判据 `:164-175`：断开连接（app 壳注入：关会话 + 回标题屏）。
  final VoidCallback onDisconnect;

  /// 判据 `:55-56` `RETURN_TO_GAME` / `ADVANCEMENTS` / `STATS` 官方 zh_cn 文案。
  static const String _returnToGame = '回到游戏';
  static const String _advancements = '进度';
  static const String _stats = '统计信息';
  static const String _options = '选项...';
  static const String _disconnect = '断开连接';

  @override
  Widget buildWidget(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 用户约定 2026-10-07：整体尺寸封顶 2 档（原版 204 宽按钮手机上不再
        // 放大到夸张）。
        final s = mcScaleForWidth(constraints.maxWidth).clamp(1.0, 2.0);
        // 判据 `:82-89`：标题居中。**间隔压小 + 可滚动**（用户约定：
        // "游戏菜单"标题上下间隔太大；内容超出视口时滚动兜底）。
        return ColoredBox(
          color: const Color(0x88000000), // 无模糊管线的替代遮罩（债）
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(vertical: 16 * s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: const Color(0xFFE0E0E0),
                        fontSize: 9 * s,
                        height: 1.0,
                        decoration: TextDecoration.none,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (showPauseMenu) ..._pauseMenu(context, s),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 判据 `:91-175` `createPauseMenu`（GridLayout 2 列 → Flutter 等价排版；
  /// 单元格 padding 4，宽 204/98 为 GUI 像素）。
  List<Widget> _pauseMenu(BuildContext context, double s) {
    return [
      SizedBox(height: 20 * s), // 判据 `:98` paddingTop(50)——用户约定压小
      MCButton(
        label: _returnToGame,
        width: 204 * s,
        height: 20 * s,
        onPress: () {
          // 判据 `:96-97`：`gui.setScreen(null)` + `mouseHandler.grabMouse()`
          //（grabMouse 幂等；setScreen(null) 内部已走 :280 grabMouse）。
          gui!.setScreen(null);
          gui!.mouseHandler.grabMouse();
        },
      ),
      SizedBox(height: 8 * s),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          MCButton(
            label: _advancements,
            width: 98 * s,
            height: 20 * s,
            // AdvancementsScreen 未实现——置灰（债）。
            enabled: false,
            onPress: null,
          ),
          SizedBox(width: 8 * s),
          MCButton(
            label: _stats,
            width: 98 * s,
            height: 20 * s,
            // StatsScreen 未实现——置灰（债）。
            enabled: false,
            onPress: null,
          ),
        ],
      ),
      SizedBox(height: 8 * s),
      // 判据 `:101-137`：图标行（4 × SpriteIconButton 20 宽、间距 4、居中）。
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 报告漏洞（`:102-108`）：ConfirmLink 外链 + isSideSeries 置灰；
          // 本仓红线无外联 ⇒ 恒置灰。
          MCSpriteIconButton(
            onPress: null,
            enabled: false,
            width: 20 * s,
            height: 20 * s,
            tooltip: '报告漏洞',
            child: _iconText('!', s),
          ),
          SizedBox(width: 4 * s),
          // 发送反馈（`:109-118`）：ConfirmLink 外链 ⇒ 置灰。
          MCSpriteIconButton(
            onPress: null,
            enabled: false,
            width: 20 * s,
            height: 20 * s,
            tooltip: '发送反馈',
            child: _iconText('~', s),
          ),
          SizedBox(width: 4 * s),
          // 好友（`:124-129` FriendsButton）⇒ FriendsOverlayScreen 未实现置灰。
          MCSpriteIconButton(
            onPress: null,
            enabled: false,
            width: 20 * s,
            height: 20 * s,
            tooltip: '好友',
            child: _iconText('@', s),
          ),
          SizedBox(width: 4 * s),
          // 举报玩家（`:130-137`）⇒ SocialInteractionsScreen 未实现置灰。
          MCSpriteIconButton(
            onPress: null,
            enabled: false,
            width: 20 * s,
            height: 20 * s,
            tooltip: '举报玩家',
            child: _iconText('▲', s),
          ),
        ],
      ),
      SizedBox(height: 8 * s),
      // 判据 `:161` 联机 else 分支：选项... 204 全宽（OptionsScreen 未实现置灰，债）。
      MCButton(
        label: _options,
        width: 204 * s,
        height: 20 * s,
        enabled: false,
        onPress: null,
      ),
      SizedBox(height: 8 * s),
      // 判据 `:164-175`：disconnectButtonLabel(false) = menu.disconnect；
      // onPress 先禁用按钮再断开（:168 `button.active = false`）。
      _DisconnectButton(onDisconnect: onDisconnect, s: s),
    ];
  }

  /// sprite 占位（官方 sprite 资产不入库；资源抽象补齐后替换）。
  Widget _iconText(String glyph, double s) => Text(
        glyph,
        style: TextStyle(
          color: const Color(0xFFE0E0E0),
          fontSize: 10 * s,
          height: 1.0,
          decoration: TextDecoration.none,
        ),
      );
}

/// 判据 `:164-175`：按下即禁用（`button.active = false`）再触发断开。
class _DisconnectButton extends StatefulWidget {
  const _DisconnectButton({required this.onDisconnect, required this.s});

  final VoidCallback onDisconnect;
  final double s;

  @override
  State<_DisconnectButton> createState() => _DisconnectButtonState();
}

class _DisconnectButtonState extends State<_DisconnectButton> {
  bool _active = true;

  @override
  Widget build(BuildContext context) {
    return MCButton(
      label: PauseScreen._disconnect,
      width: 204 * widget.s,
      height: 20 * widget.s,
      enabled: _active,
      onPress: _active
          ? () {
              setState(() => _active = false); // 判据 `:168`
              widget.onDisconnect();
            }
          : null,
    );
  }
}
