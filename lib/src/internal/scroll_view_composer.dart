import 'package:flutter/widgets.dart';

import 'paginated_scroll_physics.dart';

/// 把受支持 ScrollView 的内容与分页指示器组合进同一个视口。
///
/// 对 `buildSlivers` 的访问集中在这里，并由组合测试保护 Flutter SDK
/// 的签名变化。
CustomScrollView composeScrollView({
  required BuildContext context,
  required ScrollView source,
  required Widget headerSliver,
  required Widget footerSliver,
}) {
  if (source is! ListView &&
      source is! GridView &&
      source is! CustomScrollView) {
    throw FlutterError(
      'PaginatedList 不支持 ${source.runtimeType}。'
      'itemsBuilder 仅可返回 ListView、GridView 或 CustomScrollView。',
    );
  }

  // ignore: invalid_use_of_protected_member
  final content = source.buildSlivers(context);
  return CustomScrollView(
    key: source.key,
    scrollDirection: source.scrollDirection,
    reverse: source.reverse,
    controller: source.controller,
    primary: source.primary,
    physics: composePaginatedPhysics(source.physics),
    scrollBehavior: source.scrollBehavior,
    shrinkWrap: source.shrinkWrap,
    center: source.center,
    anchor: source.anchor,
    // ignore: deprecated_member_use
    cacheExtent: source.cacheExtent,
    scrollCacheExtent: source.scrollCacheExtent,
    semanticChildCount: source.semanticChildCount,
    paintOrder: source.paintOrder,
    dragStartBehavior: source.dragStartBehavior,
    keyboardDismissBehavior: source.keyboardDismissBehavior,
    restorationId: source.restorationId,
    clipBehavior: source.clipBehavior,
    hitTestBehavior: source.hitTestBehavior,
    slivers: [headerSliver, ...content, footerSliver],
  );
}
