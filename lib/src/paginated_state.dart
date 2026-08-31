import 'package:flutter/foundation.dart';

import 'paginated_status.dart';

/// 不可变分页快照。转换方法返回新值，调用方负责发布新状态。
///
/// 列表会复制为不可修改快照；元素本身不会深拷贝。
@immutable
class PaginatedState<T> {
  PaginatedState({List<T> items = const []})
    : this._(
        items: List<T>.unmodifiable(items),
        firstPageStatus: items.isEmpty
            ? FirstPageStatus.idle
            : FirstPageStatus.completed,
      );

  const PaginatedState._({
    required this.items,
    required this.firstPageStatus,
    this.refreshStatus = RefreshStatus.idle,
    this.loadStatus = LoadStatus.idle,
    this._firstPageBeforeLoading = FirstPageStatus.idle,
    this.refreshRevision = 0,
  });

  final List<T> items;
  final FirstPageStatus firstPageStatus;
  final RefreshStatus refreshStatus;
  final LoadStatus loadStatus;
  final FirstPageStatus _firstPageBeforeLoading;

  /// 仅用于视图区分连续刷新提示，不代表网络请求令牌。
  @internal
  final int refreshRevision;

  bool get isRefreshing =>
      firstPageStatus == FirstPageStatus.loading ||
      refreshStatus == RefreshStatus.refreshing;
  bool get isLoading => loadStatus == LoadStatus.loading;
  bool get isNoMore => loadStatus == LoadStatus.noMore;

  /// 替换完整数据；不改变请求状态，也不自动合并数据。
  PaginatedState<T> copyWith({List<T>? items}) =>
      items == null ? this : _next(items: items);

  PaginatedState<T> startRefresh() {
    if (isRefreshing) return this;
    return _next(
      firstPageStatus: firstPageStatus == FirstPageStatus.completed
          ? firstPageStatus
          : FirstPageStatus.loading,
      refreshStatus: firstPageStatus == FirstPageStatus.completed
          ? RefreshStatus.refreshing
          : RefreshStatus.idle,
      firstPageBeforeLoading: firstPageStatus,
      refreshRevision: refreshRevision + 1,
    );
  }

  /// 原子提交完整数据和刷新结果，始终重置加载状态。
  ///
  /// 不取消尚未完成的加载请求；业务需自行忽略过期响应。
  PaginatedState<T> refreshCompleted({List<T>? items}) {
    if (!isRefreshing) return this;
    final empty = (items ?? this.items).isEmpty;
    return _next(
      items: items,
      firstPageStatus: empty
          ? FirstPageStatus.empty
          : FirstPageStatus.completed,
      refreshStatus: firstPageStatus == FirstPageStatus.loading
          ? RefreshStatus.idle
          : RefreshStatus.completed,
      loadStatus: LoadStatus.idle,
    );
  }

  PaginatedState<T> refreshFailed() {
    if (!isRefreshing) return this;
    return firstPageStatus == FirstPageStatus.loading
        ? _next(firstPageStatus: FirstPageStatus.error)
        : _next(refreshStatus: RefreshStatus.failed);
  }

  /// 业务主动结束刷新或清除结果；视图收起提示不会调用本方法。
  PaginatedState<T> refreshToIdle() {
    if (firstPageStatus == FirstPageStatus.loading) {
      return _next(firstPageStatus: _firstPageBeforeLoading);
    }
    if (refreshStatus == RefreshStatus.idle) return this;
    return _next(refreshStatus: RefreshStatus.idle);
  }

  PaginatedState<T> startLoading() =>
      isLoading ? this : _next(loadStatus: LoadStatus.loading);

  /// [items] 为业务合并后的完整列表，不是待追加的一页。
  PaginatedState<T> loadCompleted({List<T>? items}) =>
      isLoading ? _next(items: items, loadStatus: LoadStatus.idle) : this;

  PaginatedState<T> loadFailed() =>
      isLoading ? _next(loadStatus: LoadStatus.failed) : this;

  /// 可直接标记没有更多；允许同时提交最后一页合并后的完整列表。
  PaginatedState<T> loadNoData({List<T>? items}) => isNoMore && items == null
      ? this
      : _next(items: items, loadStatus: LoadStatus.noMore);

  PaginatedState<T> resetNoData() =>
      isNoMore ? _next(loadStatus: LoadStatus.idle) : this;

  PaginatedState<T> _next({
    List<T>? items,
    FirstPageStatus? firstPageStatus,
    RefreshStatus? refreshStatus,
    LoadStatus? loadStatus,
    FirstPageStatus? firstPageBeforeLoading,
    int? refreshRevision,
  }) => PaginatedState._(
    items: items == null ? this.items : List<T>.unmodifiable(items),
    firstPageStatus: firstPageStatus ?? this.firstPageStatus,
    refreshStatus: refreshStatus ?? this.refreshStatus,
    loadStatus: loadStatus ?? this.loadStatus,
    firstPageBeforeLoading: firstPageBeforeLoading ?? _firstPageBeforeLoading,
    refreshRevision: refreshRevision ?? this.refreshRevision,
  );
}
