import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'internal/paginated_binding.dart';
import 'internal/paginated_gesture_control.dart';
import 'internal/paginated_indicator_host.dart';
import 'internal/paginated_indicator_slivers.dart';
import 'internal/paginated_request_coordinator.dart';
import 'internal/scroll_view_composer.dart';
import 'paginated_builders.dart';
import 'paginated_state.dart';
import 'paginated_status.dart';

/// 支持下拉刷新、上拉加载与程序化请求的分页滚动组件。
class PaginatedList<T> extends StatefulWidget {
  const PaginatedList({
    super.key,
    required this.state,
    required this.itemsBuilder,
    required this.headerBuilder,
    required this.footerBuilder,
    this.firstPageEmptyIndicatorBuilder,
    this.firstPageErrorIndicatorBuilder,
    this.firstPageProgressIndicatorBuilder,
    this.onRefresh,
    this.onLoading,
    this.bottomPadding = 0,
    this.refreshTriggerDistance = 60,
    this.loadingTriggerDistance = 60,
    this.requestRefreshDuration = const Duration(milliseconds: 500),
    this.requestLoadingDuration = const Duration(milliseconds: 300),
    this.refreshResultDuration = const Duration(milliseconds: 500),
    this.requestCurve = Curves.linear,
  }) : assert(bottomPadding >= 0 && bottomPadding < double.infinity),
       assert(refreshTriggerDistance >= 0),
       assert(loadingTriggerDistance >= 0);

  final PaginatedState<T> state;
  final PaginatedItemsBuilder<T> itemsBuilder;
  final PaginatedHeaderBuilder headerBuilder;
  final PaginatedFooterBuilder footerBuilder;
  final FirstPageIndicatorBuilder? firstPageEmptyIndicatorBuilder;
  final FirstPageErrorIndicatorBuilder? firstPageErrorIndicatorBuilder;
  final FirstPageIndicatorBuilder? firstPageProgressIndicatorBuilder;
  final AsyncCallback? onRefresh;
  final AsyncCallback? onLoading;

  /// Footer 之后随内容滚动的留白，必须为有限非负值，默认不留白。
  ///
  /// 横向列表沿水平方向留白；reverse 与 RTL 下仍位于内容末端。
  final double bottomPadding;
  final double refreshTriggerDistance;
  final double loadingTriggerDistance;
  final Duration requestRefreshDuration;
  final Duration requestLoadingDuration;
  final Duration refreshResultDuration;
  final Curve requestCurve;

  @override
  State<PaginatedList<T>> createState() => _PaginatedListState<T>();
}

class _PaginatedListState<T> extends State<PaginatedList<T>>
    implements PaginatedBinding {
  final PaginatedRequestCoordinator _requestCoordinator =
      PaginatedRequestCoordinator();
  final PaginatedRequestSlot _refreshRequest = PaginatedRequestSlot();
  final PaginatedRequestSlot _loadingRequest = PaginatedRequestSlot();
  ScrollPosition? _position;
  double _headerExtent = 0;
  double _footerExtent = 0;
  Timer? _refreshResultTimer;
  RefreshStatus? _scheduledResultStatus;
  int _refreshResultToken = 0;
  int _programmaticAnimations = 0;
  bool _isCollapsingRefreshResult = false;

  @override
  void initState() {
    super.initState();
    widget.state.normalizeForMount();
    widget.state.bind(this);
    widget.state.addListener(_stateChanged);
    _scheduleRefreshResultIfNeeded();
  }

  @override
  void didUpdateWidget(covariant PaginatedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state.removeListener(_stateChanged);
      oldWidget.state.unbind(this);
      _cancelOperations();
      widget.state.normalizeForMount();
      widget.state.bind(this);
      widget.state.addListener(_stateChanged);
    }
    if (oldWidget.refreshResultDuration != widget.refreshResultDuration) {
      invalidateRefreshResult();
    }
    _scheduleRefreshResultIfNeeded();
  }

  void _stateChanged() {
    _scheduleRefreshResultIfNeeded();
    if (mounted) setState(() {});
  }

  void _scheduleRefreshResultIfNeeded() {
    final status = widget.state.refreshStatus;
    if (!status.isResult) {
      _isCollapsingRefreshResult = false;
      _clearRefreshResultTimer();
      return;
    }
    if (_refreshResultTimer != null && _scheduledResultStatus == status) return;
    _refreshResultTimer?.cancel();
    _scheduledResultStatus = status;
    final token = ++_refreshResultToken;
    _refreshResultTimer = Timer(widget.refreshResultDuration, () {
      if (!mounted || token != _refreshResultToken) return;
      if (widget.state.refreshStatus.isResult) {
        _startCollapsingRefreshResult(token);
      }
    });
  }

  void _startCollapsingRefreshResult(int token) {
    _isCollapsingRefreshResult = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _refreshResultToken) return;
      _finishCollapsingRefreshResultIfAtBoundary();
    });
  }

  void _handlePositionChanged() {
    _finishCollapsingRefreshResultIfAtBoundary();
  }

  void _finishCollapsingRefreshResultIfAtBoundary() {
    if (!_isCollapsingRefreshResult) return;
    final position = _position;
    if (_headerExtent > 0 &&
        position != null &&
        position.hasPixels &&
        position.pixels < position.minScrollExtent - 0.5) {
      return;
    }
    _isCollapsingRefreshResult = false;
    _clearRefreshResultTimer();
    if (widget.state.refreshStatus.isResult) {
      widget.state.refreshToIdle();
    }
  }

  void _clearRefreshResultTimer() {
    _refreshResultTimer?.cancel();
    _refreshResultTimer = null;
    _scheduledResultStatus = null;
  }

  @override
  void invalidateRefreshResult() {
    _refreshResultToken++;
    _isCollapsingRefreshResult = false;
    _clearRefreshResultTimer();
  }

  @override
  Future<void> requestRefresh({bool animate = true}) {
    final requestState = widget.state;
    return _request(
      operation: 'requestRefresh()',
      callbackName: 'onRefresh',
      slot: _refreshRequest,
      isRunning: requestState.isRefreshing,
      callback: widget.onRefresh,
      animate: animate,
      leading: true,
      duration: widget.requestRefreshDuration,
      start: requestState.startRefresh,
      restore: requestState.restoreRefreshAfterInterruptedRequest,
    );
  }

  @override
  Future<void> requestLoading({bool animate = true}) {
    final requestState = widget.state;
    final previousStatus = requestState.loadStatus == LoadStatus.canLoading
        ? requestState.loadStatusBeforeCanLoading
        : requestState.loadStatus;
    return _request(
      operation: 'requestLoading()',
      callbackName: 'onLoading',
      slot: _loadingRequest,
      isRunning: requestState.loadStatus == LoadStatus.loading,
      callback: requestState.firstPageStatus == FirstPageStatus.completed
          ? widget.onLoading
          : null,
      animate: animate,
      leading: false,
      duration: widget.requestLoadingDuration,
      start: requestState.startLoading,
      restore: () =>
          requestState.restoreLoadAfterInterruptedRequest(previousStatus),
    );
  }

  Future<void> _request({
    required String operation,
    required String callbackName,
    required PaginatedRequestSlot slot,
    required bool isRunning,
    required AsyncCallback? callback,
    required bool animate,
    required bool leading,
    required Duration duration,
    required VoidCallback start,
    required VoidCallback restore,
  }) {
    final existing = slot.inFlight;
    if (existing != null) return existing;
    if (isRunning) return Future<void>.value();
    if (callback == null) {
      return Future<void>.error(
        StateError('$operation 无法执行：PaginatedList.$callbackName 未配置。'),
      );
    }

    final position = _position;
    if (!mounted || position == null || !position.hasPixels) {
      return Future<void>.error(PaginatedBindingErrors.notBound(operation));
    }

    return slot.start(
      (isCurrent) => _runRequest(
        animate: animate,
        leading: leading,
        duration: duration,
        requestPosition: position,
        isCurrent: isCurrent,
        start: start,
        restore: restore,
        callback: callback,
      ),
    );
  }

  Future<void> _runRequest({
    required bool animate,
    required bool leading,
    required Duration duration,
    required ScrollPosition requestPosition,
    required bool Function() isCurrent,
    required VoidCallback start,
    required VoidCallback restore,
    required AsyncCallback callback,
  }) async {
    start();
    try {
      if (animate) {
        await _requestCoordinator.enqueue(
          () => _showIndicator(
            leading: leading,
            duration: duration,
            requestPosition: requestPosition,
            operationIsCurrent: isCurrent,
          ),
        );
      }
      _verifyRequest(isCurrent() && identical(_position, requestPosition));
    } catch (_) {
      restore();
      rethrow;
    }
    await callback();
  }

  Future<void> _showIndicator({
    required bool leading,
    required Duration duration,
    required ScrollPosition requestPosition,
    required bool Function() operationIsCurrent,
  }) async {
    await WidgetsBinding.instance.endOfFrame;
    _verifyRequest(
      operationIsCurrent() && identical(_position, requestPosition),
    );
    final originalPosition = requestPosition;
    final measuredExtent = leading ? _headerExtent : _footerExtent;
    if (measuredExtent == 0) return;
    final target = leading
        ? originalPosition.minScrollExtent
        : originalPosition.maxScrollExtent;
    if ((originalPosition.pixels - target).abs() <= 0.5) return;

    _programmaticAnimations++;
    if (mounted) setState(() {});
    try {
      if (duration == Duration.zero) {
        originalPosition.jumpTo(target);
      } else {
        await originalPosition.animateTo(
          target,
          duration: duration,
          curve: widget.requestCurve,
        );
      }
    } finally {
      _programmaticAnimations--;
      if (mounted) setState(() {});
    }
    _verifyRequest(
      operationIsCurrent() && identical(_position, originalPosition),
    );
    if ((originalPosition.pixels - target).abs() > 1) {
      throw StateError('分页指示器展示动画被外部滚动中断，业务回调未执行。');
    }
  }

  void _verifyRequest(bool operationIsCurrent) {
    if (!mounted || !operationIsCurrent || _position == null) {
      throw StateError('PaginatedList 在请求展示期间已解绑或滚动位置已失效。');
    }
  }

  void _triggerGestureRefresh() {
    requestRefresh(animate: false).catchError(_reportGestureError);
  }

  void _triggerGestureLoading() {
    requestLoading(animate: false).catchError(_reportGestureError);
  }

  void _reportGestureError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'paginated_list',
        context: ErrorDescription('执行分页手势回调时'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = _buildItemsView();
    final firstPageCompleted =
        widget.state.firstPageStatus == FirstPageStatus.completed;
    final header = firstPageCompleted
        ? widget.headerBuilder(widget.state.refreshStatus)
        : const SizedBox.shrink();
    final footer = firstPageCompleted
        ? widget.footerBuilder(widget.state.loadStatus)
        : const SizedBox.shrink();
    final headerSliver = PaginatedRefreshSliver(
      occupiesLayout:
          firstPageCompleted &&
          !_isCollapsingRefreshResult &&
          widget.state.refreshStatus != RefreshStatus.idle &&
          widget.state.refreshStatus != RefreshStatus.canRefresh,
      child: PaginatedIndicatorHost(
        key: ValueKey<(PaginatedState<T>, bool)>((widget.state, true)),
        axis: view.scrollDirection,
        onLayout: (extent, position) =>
            _updateIndicatorLayout(extent, position, leading: true),
        child: header,
      ),
    );
    final footerSliver = PaginatedLoadSliver(
      occupiesLayout:
          firstPageCompleted &&
          widget.state.loadStatus != LoadStatus.canLoading,
      child: PaginatedIndicatorHost(
        key: ValueKey<(PaginatedState<T>, bool)>((widget.state, false)),
        axis: view.scrollDirection,
        onLayout: (extent, position) =>
            _updateIndicatorLayout(extent, position, leading: false),
        child: footer,
      ),
    );

    return IgnorePointer(
      ignoring: _programmaticAnimations > 0,
      child: PaginatedGestureControl<T>(
        state: widget.state,
        refreshTriggerDistance: widget.refreshTriggerDistance,
        loadingTriggerDistance: widget.loadingTriggerDistance,
        onRefresh: widget.onRefresh == null || !firstPageCompleted
            ? null
            : _triggerGestureRefresh,
        onLoading: widget.onLoading == null || !firstPageCompleted
            ? null
            : _triggerGestureLoading,
        child: composeScrollView(
          context: context,
          source: view,
          headerSliver: headerSliver,
          footerSliver: footerSliver,
          bottomPadding: widget.bottomPadding,
        ),
      ),
    );
  }

  ScrollView _buildItemsView() {
    return switch (widget.state.firstPageStatus) {
      FirstPageStatus.idle || FirstPageStatus.empty => _buildFirstPageView(
        widget.firstPageEmptyIndicatorBuilder?.call(),
      ),
      FirstPageStatus.loading => _buildFirstPageView(
        widget.firstPageProgressIndicatorBuilder?.call(),
      ),
      FirstPageStatus.error => _buildFirstPageView(
        widget.firstPageErrorIndicatorBuilder?.call(
          widget.onRefresh == null ? null : widget.state.requestRefresh,
        ),
      ),
      FirstPageStatus.completed => widget.itemsBuilder(widget.state.items),
    };
  }

  ScrollView _buildFirstPageView(Widget? indicator) {
    if (indicator == null) {
      return widget.itemsBuilder(widget.state.items);
    }
    return CustomScrollView(
      slivers: [SliverFillRemaining(hasScrollBody: false, child: indicator)],
    );
  }

  void _updateIndicatorLayout(
    double extent,
    ScrollPosition? position, {
    required bool leading,
  }) {
    if (leading) {
      _headerExtent = extent;
    } else {
      _footerExtent = extent;
    }
    if (position != null && !identical(position, _position)) {
      _position?.removeListener(_handlePositionChanged);
      _position = position;
      position.addListener(_handlePositionChanged);
    }
  }

  void _cancelOperations() {
    _refreshRequest.invalidate(detach: true);
    _loadingRequest.invalidate(detach: true);
    invalidateRefreshResult();
    _position?.removeListener(_handlePositionChanged);
    _position = null;
  }

  @override
  void dispose() {
    widget.state.removeListener(_stateChanged);
    _cancelOperations();
    widget.state.unbind(this);
    super.dispose();
  }
}

extension on RefreshStatus {
  bool get isResult =>
      this == RefreshStatus.completed || this == RefreshStatus.failed;
}
