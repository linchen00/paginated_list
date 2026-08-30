import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../paginated_state.dart';
import '../paginated_status.dart';

/// 监听两端的真实滚动距离，并将一次滚动会话转换为刷新或加载请求。
class PaginatedGestureControl<T> extends StatefulWidget {
  const PaginatedGestureControl({
    super.key,
    required this.state,
    required this.refreshTriggerDistance,
    required this.loadingTriggerDistance,
    required this.onRefresh,
    required this.onLoading,
    required this.child,
  });

  final PaginatedState<T> state;
  final double refreshTriggerDistance;
  final double loadingTriggerDistance;
  final VoidCallback? onRefresh;
  final VoidCallback? onLoading;
  final Widget child;

  @override
  State<PaginatedGestureControl<T>> createState() =>
      _PaginatedGestureControlState<T>();
}

class _PaginatedGestureControlState<T>
    extends State<PaginatedGestureControl<T>> {
  bool _refreshDragging = false;
  bool _loadSessionActive = false;
  bool _loadTriggeredInSession = false;

  @override
  void didUpdateWidget(covariant PaginatedGestureControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      _resetSessions();
      return;
    }
    if (widget.onRefresh == null) _refreshDragging = false;
    if (widget.onLoading == null) _resetLoadSession();
  }

  bool _handleNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _refreshDragging = widget.onRefresh != null;
      _loadSessionActive = widget.onLoading != null;
      _loadTriggeredInSession = false;
    }

    if (notification case ScrollUpdateNotification(
      :final metrics,
      :final dragDetails,
      :final scrollDelta,
    )) {
      _updateRefresh(metrics, isDragging: dragDetails != null);
      _updateLoading(
        metrics,
        isDragging: dragDetails != null,
        scrollDelta: scrollDelta ?? 0,
      );
    } else if (notification case OverscrollNotification(
      :final metrics,
      :final dragDetails,
      :final overscroll,
    )) {
      _updateRefresh(metrics, isDragging: dragDetails != null);
      _updateLoading(
        metrics,
        isDragging: dragDetails != null,
        scrollDelta: overscroll,
      );
    }

    if (notification is ScrollEndNotification ||
        notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle) {
      _finishRefresh(notification.metrics);
      _finishLoading(notification.metrics);
    }
    return false;
  }

  void _updateRefresh(ScrollMetrics metrics, {required bool isDragging}) {
    if (!_refreshDragging || widget.onRefresh == null) return;
    final status = widget.state.refreshStatus;
    if (status != RefreshStatus.idle && status != RefreshStatus.canRefresh) {
      _refreshDragging = false;
      return;
    }

    final pulledExtent = math.max(
      metrics.minScrollExtent - metrics.pixels,
      0.0,
    );
    if (isDragging) {
      if (pulledExtent > 0 && pulledExtent >= widget.refreshTriggerDistance) {
        widget.state.markCanRefresh();
      } else {
        widget.state.cancelCanRefresh();
      }
      return;
    }

    _refreshDragging = false;
    if (status == RefreshStatus.canRefresh && pulledExtent > 0) {
      widget.onRefresh!();
    } else {
      widget.state.cancelCanRefresh();
    }
  }

  void _finishRefresh(ScrollMetrics metrics) {
    if (!_refreshDragging || widget.onRefresh == null) return;
    _refreshDragging = false;
    if (widget.state.refreshStatus == RefreshStatus.canRefresh &&
        metrics.pixels < metrics.minScrollExtent) {
      widget.onRefresh!();
    } else {
      widget.state.cancelCanRefresh();
    }
  }

  void _updateLoading(
    ScrollMetrics metrics, {
    required bool isDragging,
    required double scrollDelta,
  }) {
    if (!_loadSessionActive ||
        _loadTriggeredInSession ||
        widget.onLoading == null ||
        !_canLoad) {
      return;
    }

    if (metrics.maxScrollExtent > metrics.minScrollExtent) {
      if (scrollDelta > 0 &&
          metrics.extentAfter <= widget.loadingTriggerDistance) {
        _triggerLoading();
      }
      return;
    }

    final pulledExtent = math.max(
      metrics.pixels - metrics.maxScrollExtent,
      0.0,
    );
    if (isDragging) {
      if (pulledExtent > 0 && pulledExtent >= widget.loadingTriggerDistance) {
        widget.state.markCanLoading();
      } else {
        widget.state.cancelCanLoading();
      }
      return;
    }

    if (widget.state.loadStatus == LoadStatus.canLoading && pulledExtent > 0) {
      _triggerLoading();
    } else {
      widget.state.cancelCanLoading();
      _loadSessionActive = false;
    }
  }

  bool get _canLoad =>
      widget.state.loadStatus != LoadStatus.loading &&
      widget.state.loadStatus != LoadStatus.noMore;

  void _triggerLoading() {
    if (_loadTriggeredInSession || !_canLoad || widget.onLoading == null) {
      return;
    }
    _loadTriggeredInSession = true;
    _loadSessionActive = false;
    widget.onLoading!();
  }

  void _finishLoading(ScrollMetrics metrics) {
    if (!_loadSessionActive || widget.onLoading == null) return;
    if (widget.state.loadStatus == LoadStatus.canLoading &&
        metrics.pixels > metrics.maxScrollExtent) {
      _triggerLoading();
    } else {
      widget.state.cancelCanLoading();
      _loadSessionActive = false;
    }
  }

  void _resetSessions() {
    _refreshDragging = false;
    _resetLoadSession();
  }

  void _resetLoadSession() {
    _loadSessionActive = false;
    _loadTriggeredInSession = false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleNotification,
      child: widget.child,
    );
  }
}
