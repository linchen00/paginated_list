import 'package:flutter/widgets.dart';

/// 为短内容补充可拖动能力，同时保留调用方提供的 physics 链。
ScrollPhysics? composePaginatedPhysics(ScrollPhysics? physics) {
  ScrollPhysics? current = physics;
  while (current != null) {
    if (current is NeverScrollableScrollPhysics) return physics;
    current = current.parent;
  }
  return PaginatedScrollPhysics(parent: physics);
}

/// 允许所有平台在分页边缘产生可回弹的 overscroll。
class PaginatedScrollPhysics extends BouncingScrollPhysics {
  const PaginatedScrollPhysics({super.parent});

  @override
  PaginatedScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return PaginatedScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => true;
}
