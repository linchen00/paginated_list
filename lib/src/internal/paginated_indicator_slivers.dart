import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 在拖动时绘制于内容 leading 侧，刷新时才占用布局空间的 Header Sliver。
class PaginatedRefreshSliver extends SingleChildRenderObjectWidget {
  const PaginatedRefreshSliver({
    super.key,
    required this.occupiesLayout,
    required super.child,
  });

  final bool occupiesLayout;

  @override
  RenderPaginatedRefreshSliver createRenderObject(BuildContext context) {
    return RenderPaginatedRefreshSliver(occupiesLayout);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPaginatedRefreshSliver renderObject,
  ) {
    renderObject.occupiesLayout = occupiesLayout;
  }
}

class RenderPaginatedRefreshSliver extends RenderSliverSingleBoxAdapter {
  RenderPaginatedRefreshSliver(this._occupiesLayout);

  bool _occupiesLayout;
  double _compensatedLayoutExtent = 0;
  bool _hasCompletedInitialLayout = false;

  set occupiesLayout(bool value) {
    if (_occupiesLayout == value) return;
    _occupiesLayout = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      geometry = SliverGeometry.zero;
      return;
    }

    child.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final childExtent = constraints.axis == Axis.vertical
        ? child.size.height
        : child.size.width;
    final layoutExtent = _occupiesLayout ? childExtent : 0.0;

    if (!_hasCompletedInitialLayout) {
      _hasCompletedInitialLayout = true;
      _compensatedLayoutExtent = layoutExtent;
    } else if (layoutExtent != _compensatedLayoutExtent) {
      geometry = SliverGeometry(
        scrollOffsetCorrection: layoutExtent - _compensatedLayoutExtent,
      );
      _compensatedLayoutExtent = layoutExtent;
      return;
    }

    final active = constraints.overlap < 0 || layoutExtent > 0;
    if (!active || childExtent == 0) {
      geometry = SliverGeometry(scrollExtent: layoutExtent);
      return;
    }

    final paintExtent = math.min(
      math.max(
        math.max(childExtent, layoutExtent) - constraints.scrollOffset,
        0.0,
      ),
      constraints.remainingPaintExtent,
    );
    geometry = SliverGeometry(
      scrollExtent: layoutExtent,
      paintOrigin: -childExtent - constraints.scrollOffset + layoutExtent,
      paintExtent: paintExtent,
      layoutExtent: math.min(
        paintExtent,
        math.max(layoutExtent - constraints.scrollOffset, 0.0),
      ),
      maxPaintExtent: math.max(childExtent, layoutExtent),
      hitTestExtent: paintExtent,
      hasVisualOverflow: true,
    );
    setChildParentData(child, constraints, geometry!);
  }
}

/// Footer 在 canLoading 时只绘制，在持久状态下才进入滚动布局。
class PaginatedLoadSliver extends SingleChildRenderObjectWidget {
  const PaginatedLoadSliver({
    super.key,
    required this.occupiesLayout,
    required super.child,
  });

  final bool occupiesLayout;

  @override
  RenderPaginatedLoadSliver createRenderObject(BuildContext context) {
    return RenderPaginatedLoadSliver(occupiesLayout);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPaginatedLoadSliver renderObject,
  ) {
    renderObject.occupiesLayout = occupiesLayout;
  }
}

class RenderPaginatedLoadSliver extends RenderSliverSingleBoxAdapter {
  RenderPaginatedLoadSliver(this._occupiesLayout);

  bool _occupiesLayout;

  set occupiesLayout(bool value) {
    if (_occupiesLayout == value) return;
    _occupiesLayout = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      geometry = SliverGeometry.zero;
      return;
    }

    child.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final childExtent = constraints.axis == Axis.vertical
        ? child.size.height
        : child.size.width;
    final scrollExtent = _occupiesLayout ? childExtent : 0.0;
    final paintExtent = calculatePaintOffset(
      constraints,
      from: 0,
      to: childExtent,
    );
    final cacheExtent = calculateCacheOffset(
      constraints,
      from: 0,
      to: childExtent,
    );

    geometry = SliverGeometry(
      scrollExtent: scrollExtent,
      paintExtent: paintExtent,
      cacheExtent: cacheExtent,
      maxPaintExtent: childExtent,
      hitTestExtent: paintExtent,
      hasVisualOverflow: true,
    );
    setChildParentData(child, constraints, geometry!);
  }
}
