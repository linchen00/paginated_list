import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paginated_list/paginated_list.dart';

/// 示例数据源可在测试中替换，不属于分页组件的职责。
final fetchPageProvider = Provider<Future<List<int>> Function(int)>((ref) {
  return (page) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return page > 3 ? [] : List.generate(20, (i) => (page - 1) * 20 + i + 1);
  };
});

final paginationProvider =
    NotifierProvider.autoDispose<PaginationNotifier, PaginatedState<int>>(
      PaginationNotifier.new,
    );

class PaginationNotifier extends Notifier<PaginatedState<int>> {
  int _page = 0;
  int _generation = 0;
  Object? _loadingRequest;

  @override
  PaginatedState<int> build() => PaginatedState<int>();

  Future<void> refresh() async {
    if (state.isRefreshing) return;
    final generation = ++_generation;
    // 过期加载属于业务数据源，需要由业务隔离。
    _loadingRequest = null;
    state = state.startRefresh();
    try {
      final items = await ref.read(fetchPageProvider)(1);
      if (!ref.mounted || generation != _generation) return;
      _page = 1;
      // 刷新期间启动的加载也不能覆盖本次刷新结果。
      _generation++;
      _loadingRequest = null;
      state = state.refreshCompleted(items: items);
    } catch (_) {
      if (!ref.mounted || generation != _generation) return;
      state = _loadingRequest == null && state.isLoading
          ? state.refreshFailed().loadFailed()
          : state.refreshFailed();
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isNoMore || _loadingRequest != null) return;
    final generation = _generation;
    final request = Object();
    _loadingRequest = request;
    final page = _page + 1;
    state = state.startLoading();
    try {
      final next = await ref.read(fetchPageProvider)(page);
      if (!ref.mounted ||
          generation != _generation ||
          !identical(request, _loadingRequest)) {
        return;
      }
      if (next.isEmpty) {
        state = state.loadNoData();
      } else {
        _page = page;
        state = state.loadCompleted(items: [...state.items, ...next]);
      }
    } catch (_) {
      if (!ref.mounted ||
          generation != _generation ||
          !identical(request, _loadingRequest)) {
        return;
      }
      state = state.loadFailed();
    } finally {
      if (identical(request, _loadingRequest)) _loadingRequest = null;
    }
  }
}
