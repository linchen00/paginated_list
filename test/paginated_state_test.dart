import 'package:flutter_test/flutter_test.dart';
import 'package:paginated_list/paginated_list.dart';

void main() {
  test('输入和旧快照不可变，纯状态转换复用列表', () {
    final source = [1, 2];
    final original = PaginatedState<int>(items: source);
    source.add(3);
    expect(original.items, [1, 2]);
    expect(() => original.items.add(4), throwsUnsupportedError);
    final refreshing = original.startRefresh();
    expect(identical(original.items, refreshing.items), isTrue);
    expect(original.isRefreshing, isFalse);
    expect(refreshing.isRefreshing, isTrue);
    final next = [5];
    final result = refreshing.refreshCompleted(items: next);
    next.add(6);
    expect(result.items, [5]);
    expect(original.items, [1, 2]);
    expect(refreshing.refreshStatus, RefreshStatus.refreshing);
    expect(result.refreshStatus, RefreshStatus.completed);
  });

  test('copyWith 只替换数据，空调用和无效转换返回原对象', () {
    final state = PaginatedState<int>();
    expect(identical(state.copyWith(), state), isTrue);
    expect(identical(state.refreshCompleted(items: [1]), state), isTrue);
    expect(identical(state.refreshFailed(), state), isTrue);
    expect(identical(state.refreshToIdle(), state), isTrue);
    expect(identical(state.loadCompleted(items: [1]), state), isTrue);
    expect(identical(state.loadFailed(), state), isTrue);
    expect(identical(state.resetNoData(), state), isTrue);
    final updated = state.copyWith(items: [1]);
    expect(updated.firstPageStatus, FirstPageStatus.idle);
    expect(updated.items, [1]);
    final refreshing = state.startRefresh();
    expect(identical(refreshing.startRefresh(), refreshing), isTrue);
    final loading = state.startLoading();
    expect(identical(loading.startLoading(), loading), isTrue);
  });

  test('首屏失败、重试、空数据和普通刷新状态互斥', () {
    var state = PaginatedState<int>();
    expect(state.firstPageStatus, FirstPageStatus.idle);
    state = state.startRefresh();
    expect(state.firstPageStatus, FirstPageStatus.loading);
    expect(state.refreshStatus, RefreshStatus.idle);
    state = state.refreshFailed();
    expect(state.firstPageStatus, FirstPageStatus.error);
    state = state.startRefresh().refreshCompleted(items: []);
    expect(state.firstPageStatus, FirstPageStatus.empty);
    state = state.startRefresh().refreshCompleted(items: [1]);
    expect(state.firstPageStatus, FirstPageStatus.completed);
    expect(state.refreshStatus, RefreshStatus.idle);
    state = state.startRefresh().refreshFailed();
    expect(state.items, [1]);
    expect(state.firstPageStatus, FirstPageStatus.completed);
    expect(state.refreshStatus, RefreshStatus.failed);
    state = state.startRefresh().refreshCompleted(items: []);
    expect(state.firstPageStatus, FirstPageStatus.empty);
    expect(state.refreshStatus, RefreshStatus.completed);
  });

  test('刷新成功从所有业务加载状态原子重置 idle', () {
    final initial = PaginatedState<int>(items: [1]);
    final cases = [
      initial,
      initial.startLoading(),
      initial.startLoading().loadFailed(),
      initial.loadNoData(),
    ];
    for (final old in cases) {
      final running = old.startRefresh();
      final completed = running.refreshCompleted(items: [2]);
      expect(completed.items, [2]);
      expect(completed.refreshStatus, RefreshStatus.completed);
      expect(completed.loadStatus, LoadStatus.idle);
      expect(completed.isLoading, isFalse);
      expect(completed.isNoMore, isFalse);
      expect(running.loadStatus, old.loadStatus);
      expect(running.refreshFailed().loadStatus, old.loadStatus);
      expect(identical(old.refreshCompleted(items: [3]), old), isTrue);
    }
  });

  test('isNoMore、最后一页原子提交和显式重新加载', () {
    final initial = PaginatedState<int>(items: [1]);
    final noMore = initial.loadNoData(items: [1, 2]);
    expect(initial.isNoMore, isFalse);
    expect(noMore.items, [1, 2]);
    expect(noMore.isNoMore, isTrue);
    expect(identical(noMore.loadNoData(), noMore), isTrue);
    expect(noMore.resetNoData().isNoMore, isFalse);
    final loading = noMore.startLoading();
    expect(loading.isNoMore, isFalse);
    expect(loading.isLoading, isTrue);
    final completed = loading.loadCompleted(items: [1, 2, 3]);
    expect(completed.items, [1, 2, 3]);
    expect(completed.loadStatus, LoadStatus.idle);
    expect(loading.loadFailed().loadStatus, LoadStatus.failed);
  });

  test('业务取消首屏恢复先前状态，清除普通结果保留数据', () {
    final error = PaginatedState<int>().startRefresh().refreshFailed();
    expect(
      error.startRefresh().refreshToIdle().firstPageStatus,
      FirstPageStatus.error,
    );
    final completed = PaginatedState<int>(
      items: [1],
    ).startRefresh().refreshCompleted();
    final idle = completed.refreshToIdle();
    expect(idle.refreshStatus, RefreshStatus.idle);
    expect(identical(idle.items, completed.items), isTrue);
  });

  test('并发时刷新成功重置加载但不接受无效的旧加载完成', () {
    final both = PaginatedState<int>(items: [1]).startLoading().startRefresh();
    expect(both.isLoading && both.isRefreshing, isTrue);
    final refreshed = both.refreshCompleted(items: [2]);
    expect(
      identical(refreshed.loadCompleted(items: [1, 3]), refreshed),
      isTrue,
    );
  });
}
