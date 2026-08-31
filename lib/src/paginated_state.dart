import 'package:flutter/foundation.dart';

import 'internal/paginated_binding.dart';
import 'paginated_status.dart';

/// 保存分页数据及刷新、加载状态的可变状态对象。
class PaginatedState<T> extends ChangeNotifier {
  PaginatedState({List<T> items = const []})
    : _items = List<T>.unmodifiable(items),
      _firstPageStatus = items.isEmpty
          ? FirstPageStatus.idle
          : FirstPageStatus.completed;

  List<T> _items;
  FirstPageStatus _firstPageStatus;
  FirstPageStatus _firstPageStatusBeforeLoading = FirstPageStatus.idle;
  RefreshStatus _refreshStatus = RefreshStatus.idle;
  LoadStatus _loadStatus = LoadStatus.idle;
  LoadStatus _loadStatusBeforeCanLoading = LoadStatus.idle;
  PaginatedBinding? _binding;
  bool _disposed = false;

  /// 当前数据的不可修改快照。
  List<T> get items => _items;

  set items(List<T> value) {
    _items = List<T>.unmodifiable(value);
    notifyListeners();
  }

  /// 当前刷新状态。
  RefreshStatus get refreshStatus => _refreshStatus;

  /// 当前首屏状态。
  FirstPageStatus get firstPageStatus => _firstPageStatus;

  /// 首屏请求或普通刷新是否正在进行。
  bool get isRefreshing =>
      _firstPageStatus == FirstPageStatus.loading ||
      _refreshStatus == RefreshStatus.refreshing;

  /// 当前加载状态。
  LoadStatus get loadStatus => _loadStatus;

  /// 下一页加载是否正在进行。
  bool get isLoading => _loadStatus == LoadStatus.loading;

  @internal
  LoadStatus get loadStatusBeforeCanLoading => _loadStatusBeforeCanLoading;

  /// 通过已绑定的视图展示 Header，然后执行刷新回调。
  Future<void> requestRefresh() {
    final binding = _binding;
    if (binding == null) {
      return Future<void>.error(
        PaginatedBindingErrors.notBound('requestRefresh()'),
      );
    }
    return binding.requestRefresh();
  }

  /// 通过已绑定的视图展示 Footer，然后执行加载回调。
  Future<void> requestLoading() {
    final binding = _binding;
    if (binding == null) {
      return Future<void>.error(
        PaginatedBindingErrors.notBound('requestLoading()'),
      );
    }
    return binding.requestLoading();
  }

  /// 将刷新状态切换为进行中；不会触发 UI 回调。
  void startRefresh() {
    if (isRefreshing) return;
    _binding?.invalidateRefreshResult();
    if (_firstPageStatus != FirstPageStatus.completed) {
      _firstPageStatusBeforeLoading = _firstPageStatus;
      _firstPageStatus = FirstPageStatus.loading;
    } else {
      _refreshStatus = RefreshStatus.refreshing;
    }
    notifyListeners();
  }

  /// 将加载状态切换为进行中；不会触发 UI 回调。
  void startLoading() {
    if (_loadStatus == LoadStatus.loading) return;
    _setLoad(LoadStatus.loading);
  }

  /// 结束刷新并进入成功结果状态。
  void refreshCompleted({bool resetLoadStatus = true}) {
    if (_firstPageStatus == FirstPageStatus.loading) {
      _firstPageStatus = _items.isEmpty
          ? FirstPageStatus.empty
          : FirstPageStatus.completed;
    } else if (_refreshStatus == RefreshStatus.refreshing) {
      _refreshStatus = RefreshStatus.completed;
      if (_items.isEmpty) _firstPageStatus = FirstPageStatus.empty;
    } else {
      return;
    }
    if (resetLoadStatus) _loadStatus = LoadStatus.idle;
    notifyListeners();
  }

  /// 结束刷新并进入失败结果状态。
  void refreshFailed() {
    if (_firstPageStatus == FirstPageStatus.loading) {
      _firstPageStatus = FirstPageStatus.error;
    } else if (_refreshStatus == RefreshStatus.refreshing) {
      _refreshStatus = RefreshStatus.failed;
    } else {
      return;
    }
    notifyListeners();
  }

  /// 立即结束当前刷新状态并收起 Header。
  void refreshToIdle() {
    if (_firstPageStatus == FirstPageStatus.loading) {
      _firstPageStatus = _firstPageStatusBeforeLoading;
    } else if (_refreshStatus != RefreshStatus.idle) {
      _refreshStatus = RefreshStatus.idle;
    } else {
      return;
    }
    _binding?.invalidateRefreshResult();
    notifyListeners();
  }

  /// 完成加载并恢复空闲状态。
  void loadComplete() {
    if (_loadStatus != LoadStatus.loading) return;
    _setLoad(LoadStatus.idle);
  }

  /// 结束加载并进入失败状态。
  void loadFailed() {
    if (_loadStatus != LoadStatus.loading) return;
    _setLoad(LoadStatus.failed);
  }

  /// 标记没有更多数据，不限制当前加载状态。
  void loadNoData() {
    _setLoad(LoadStatus.noMore);
  }

  /// 清除没有更多数据状态。
  void resetNoData() {
    if (_loadStatus != LoadStatus.noMore) return;
    _setLoad(LoadStatus.idle);
  }

  @internal
  void bind(PaginatedBinding binding) {
    if (_disposed) {
      throw StateError('已 dispose 的 PaginatedState 不能绑定 PaginatedList。');
    }
    if (_binding != null && !identical(_binding, binding)) {
      throw FlutterError(
        '一个 PaginatedState 同一时刻只能绑定一个 PaginatedList。\n'
        '请为第二个列表创建独立的 PaginatedState，或先卸载原列表。',
      );
    }
    _binding = binding;
  }

  @internal
  void unbind(PaginatedBinding binding, {LoadStatus? previousLoadStatus}) {
    if (!identical(_binding, binding)) return;
    _binding = null;
    var changed = false;
    if (_refreshStatus == RefreshStatus.canRefresh) {
      _refreshStatus = RefreshStatus.idle;
      changed = true;
    }
    if (_loadStatus == LoadStatus.canLoading) {
      _loadStatus = previousLoadStatus ?? _loadStatusBeforeCanLoading;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  @internal
  void normalizeForMount() {
    var changed = false;
    if (_refreshStatus != RefreshStatus.idle &&
        _refreshStatus != RefreshStatus.refreshing) {
      _refreshStatus = RefreshStatus.idle;
      changed = true;
    }
    if (_loadStatus == LoadStatus.canLoading) {
      _loadStatus = LoadStatus.idle;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  @internal
  void markCanRefresh() {
    if (_firstPageStatus == FirstPageStatus.completed &&
        _refreshStatus == RefreshStatus.idle) {
      _setRefresh(RefreshStatus.canRefresh);
    }
  }

  @internal
  void cancelCanRefresh() {
    if (_refreshStatus == RefreshStatus.canRefresh) {
      _setRefresh(RefreshStatus.idle);
    }
  }

  @internal
  bool markCanLoading() {
    if (_loadStatus == LoadStatus.noMore ||
        _loadStatus == LoadStatus.loading ||
        _loadStatus == LoadStatus.canLoading) {
      return false;
    }
    _loadStatusBeforeCanLoading = _loadStatus;
    _setLoad(LoadStatus.canLoading);
    return true;
  }

  @internal
  void cancelCanLoading([LoadStatus? previous]) {
    if (_loadStatus == LoadStatus.canLoading) {
      _setLoad(previous ?? _loadStatusBeforeCanLoading);
    }
  }

  @internal
  void restoreRefreshAfterInterruptedRequest() {
    if (_firstPageStatus == FirstPageStatus.loading) {
      _firstPageStatus = _firstPageStatusBeforeLoading;
      notifyListeners();
    } else if (_refreshStatus == RefreshStatus.refreshing) {
      _setRefresh(RefreshStatus.idle);
    }
  }

  @internal
  void restoreLoadAfterInterruptedRequest(LoadStatus previous) {
    if (_loadStatus == LoadStatus.loading) _setLoad(previous);
  }

  void _setRefresh(RefreshStatus value) {
    if (_refreshStatus == value) return;
    _refreshStatus = value;
    notifyListeners();
  }

  void _setLoad(LoadStatus value) {
    if (_loadStatus == value) return;
    _loadStatus = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _binding = null;
    super.dispose();
  }
}
