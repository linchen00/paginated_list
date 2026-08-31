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
import 'paginated_controller.dart';
import 'paginated_state.dart';
import 'paginated_status.dart';

/// 支持下拉刷新、上拉加载与程序化请求的分页滚动组件。
class PaginatedList<T> extends StatefulWidget {
  const PaginatedList({
    super.key,
    required this.state,
    this.controller,
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
  final PaginatedController? controller;
  final PaginatedItemsBuilder<T> itemsBuilder;
  final PaginatedHeaderBuilder headerBuilder;
  final PaginatedFooterBuilder footerBuilder;
  final FirstPageIndicatorBuilder? firstPageEmptyIndicatorBuilder;
  final FirstPageErrorIndicatorBuilder? firstPageErrorIndicatorBuilder;
  final FirstPageIndicatorBuilder? firstPageProgressIndicatorBuilder;
  final AsyncCallback? onRefresh;

  /// 加载更多回调；为 null 时不构建或展示 Footer。
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
  (int, RefreshStatus)? _visibleResult;
  (int, RefreshStatus)? _consumedResult;
  bool _refreshArmed = false;
  bool _loadingArmed = false;
  Object? _refreshPresentation;
  Object? _loadingPresentation;
  int _refreshResultToken = 0;
  int _programmaticAnimations = 0;
  bool _isCollapsingRefreshResult = false;

  (int, RefreshStatus) get _resultKey =>
      (widget.state.refreshRevision, widget.state.refreshStatus);

  RefreshStatus get _refreshStatus {
    if (widget.state.isRefreshing) return RefreshStatus.refreshing;
    if (_visibleResult == _resultKey) return widget.state.refreshStatus;
    if (_refreshPresentation != null) return RefreshStatus.refreshing;
    return _refreshArmed ? RefreshStatus.canRefresh : RefreshStatus.idle;
  }

  LoadStatus get _loadStatus {
    if (widget.state.isLoading || _loadingPresentation != null) {
      return LoadStatus.loading;
    }
    if (_loadingArmed && !widget.state.isNoMore) return LoadStatus.canLoading;
    return widget.state.loadStatus;
  }

  @override
  void initState() {
    super.initState();
    widget.controller?.bind(this);
    if (widget.state.refreshStatus.isResult) _consumedResult = _resultKey;
  }

  @override
  void didUpdateWidget(covariant PaginatedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.unbind(this);
      _invalidateRequests();
      widget.controller?.bind(this);
    }
    if (oldWidget.state.refreshRevision != widget.state.refreshRevision ||
        oldWidget.state.refreshStatus != widget.state.refreshStatus) {
      _refreshPresentation = null;
    }
    if (oldWidget.state.loadStatus != widget.state.loadStatus) {
      _loadingPresentation = null;
    }
    if (widget.state.isRefreshing || widget.onRefresh == null) {
      _refreshArmed = false;
    }
    if (widget.state.isLoading ||
        widget.state.isNoMore ||
        widget.onLoading == null) {
      _loadingArmed = false;
    }
    if (oldWidget.refreshResultDuration != widget.refreshResultDuration &&
        _visibleResult != null) {
      _invalidateRefreshResult();
    }
    _scheduleRefreshResultIfNeeded();
  }

  void _scheduleRefreshResultIfNeeded() {
    if (!widget.state.refreshStatus.isResult || widget.state.items.isEmpty) {
      if (widget.state.refreshStatus.isResult) _consumedResult = _resultKey;
      _invalidateRefreshResult();
      return;
    }
    if (_consumedResult == _resultKey) return;
    if (_visibleResult == _resultKey) return;
    _invalidateRefreshResult();
    _visibleResult = _resultKey;
    final token = _refreshResultToken;
    _refreshResultTimer = Timer(widget.refreshResultDuration, () {
      if (!mounted || token != _refreshResultToken) return;
      _startCollapsingRefreshResult(token);
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
    setState(() {
      _consumedResult = _visibleResult;
      _invalidateRefreshResult();
    });
  }

  void _clearRefreshResultTimer() {
    _refreshResultTimer?.cancel();
    _refreshResultTimer = null;
  }

  void _invalidateRefreshResult() {
    _visibleResult = null;
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
    );
  }

  @override
  Future<void> requestLoading({bool animate = true}) {
    final requestState = widget.state;
    return _request(
      operation: 'requestLoading()',
      callbackName: 'onLoading',
      slot: _loadingRequest,
      isRunning: requestState.isLoading,
      callback: requestState.items.isNotEmpty ? widget.onLoading : null,
      animate: animate,
      leading: false,
      duration: widget.requestLoadingDuration,
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
    required AsyncCallback callback,
  }) async {
    final refreshRevision = widget.state.refreshRevision;
    final presentation = Object();
    setState(() {
      if (leading) {
        _consumedResult = _visibleResult ?? _consumedResult;
        _invalidateRefreshResult();
        _refreshArmed = false;
        _refreshPresentation = presentation;
      } else {
        _loadingArmed = false;
        _loadingPresentation = presentation;
      }
    });
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
      // External refresh may have both started and finished during the animation.
      // Checking only the current busy flag would repeat that completed request.
      if (leading && widget.state.refreshRevision != refreshRevision) return;
      if (leading ? widget.state.isRefreshing : widget.state.isLoading) return;
      if (!leading && widget.state.items.isEmpty) {
        return;
      }
      // Presentation ends when business takes over. In particular, a callback
      // may publish start and completion before the next frame, then await cleanup.
      setState(() {
        if (identical(_refreshPresentation, presentation)) {
          _refreshPresentation = null;
        }
        if (identical(_loadingPresentation, presentation)) {
          _loadingPresentation = null;
        }
      });
      await callback();
    } finally {
      if (mounted) {
        setState(() {
          if (identical(_refreshPresentation, presentation)) {
            _refreshPresentation = null;
          }
          if (identical(_loadingPresentation, presentation)) {
            _loadingPresentation = null;
          }
        });
      }
    }
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

  void _triggerRetry() {
    requestRefresh().catchError(_reportGestureError);
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
    // Even first-page indicators use the source viewport configuration.
    final view = widget.itemsBuilder(widget.state.items);
    final firstPageIndicator = _buildFirstPageIndicator();
    final hasItems = widget.state.items.isNotEmpty;
    final showFooter = hasItems && widget.onLoading != null;
    final header = hasItems
        ? widget.headerBuilder(_refreshStatus)
        : const SizedBox.shrink();
    final footer = showFooter
        ? widget.footerBuilder(_loadStatus)
        : const SizedBox.shrink();
    final headerSliver = PaginatedRefreshSliver(
      occupiesLayout:
          hasItems &&
          !_isCollapsingRefreshResult &&
          _refreshStatus != RefreshStatus.idle &&
          _refreshStatus != RefreshStatus.canRefresh,
      child: PaginatedIndicatorHost(
        key: const ValueKey('pagination-header'),
        axis: view.scrollDirection,
        onLayout: (extent, position) =>
            _updateIndicatorLayout(extent, position, leading: true),
        child: header,
      ),
    );
    final footerSliver = PaginatedLoadSliver(
      occupiesLayout: showFooter && _loadStatus != LoadStatus.canLoading,
      child: PaginatedIndicatorHost(
        key: const ValueKey('pagination-footer'),
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
        refreshBusy:
            _refreshRequest.inFlight != null ||
            widget.state.isRefreshing ||
            _visibleResult != null,
        loadingBusy: _loadingRequest.inFlight != null || widget.state.isLoading,
        onRefreshArmed: (value) => setState(() => _refreshArmed = value),
        onLoadingArmed: (value) => setState(() => _loadingArmed = value),
        refreshTriggerDistance: widget.refreshTriggerDistance,
        loadingTriggerDistance: widget.loadingTriggerDistance,
        onRefresh: widget.onRefresh == null || !hasItems
            ? null
            : _triggerGestureRefresh,
        onLoading: widget.onLoading == null || !hasItems
            ? null
            : _triggerGestureLoading,
        child: composeScrollView(
          context: context,
          source: view,
          firstPageIndicator: firstPageIndicator,
          headerSliver: headerSliver,
          footerSliver: footerSliver,
          bottomPadding: widget.bottomPadding,
        ),
      ),
    );
  }

  Widget? _buildFirstPageIndicator() {
    if (widget.state.items.isNotEmpty) return null;
    final refreshStatus = _refreshPresentation != null
        ? RefreshStatus.refreshing
        : widget.state.refreshStatus;
    return switch (refreshStatus) {
      RefreshStatus.refreshing =>
        widget.firstPageProgressIndicatorBuilder?.call(),
      RefreshStatus.failed => widget.firstPageErrorIndicatorBuilder?.call(
        widget.onRefresh == null ? null : _triggerRetry,
      ),
      _ => widget.firstPageEmptyIndicatorBuilder?.call(),
    };
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

  void _invalidateRequests() {
    _refreshRequest.invalidate(detach: true);
    _loadingRequest.invalidate(detach: true);
    _refreshPresentation = null;
    _loadingPresentation = null;
    _refreshArmed = false;
    _loadingArmed = false;
  }

  @override
  void cancelControllerRequests() {
    _invalidateRequests();
    // Controller disposal may occur while a parent is unmounting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void deactivate() {
    // A replacement Key mounts before the old State is disposed.
    widget.controller?.unbind(this);
    _invalidateRequests();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    widget.controller?.bind(this);
  }

  @override
  void dispose() {
    widget.controller?.unbind(this);
    _invalidateRequests();
    _invalidateRefreshResult();
    _position?.removeListener(_handlePositionChanged);
    _position = null;
    super.dispose();
  }
}

extension on RefreshStatus {
  bool get isResult =>
      this == RefreshStatus.completed || this == RefreshStatus.failed;
}
