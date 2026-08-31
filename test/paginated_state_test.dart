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
    expect(updated.refreshStatus, RefreshStatus.idle);
    expect(updated.items, [1]);
    final refreshing = state.startRefresh();
    expect(identical(refreshing.startRefresh(), refreshing), isTrue);
    final loading = state.startLoading();
    expect(identical(loading.startLoading(), loading), isTrue);
  });

  test('copyWith 增删数据保持快照不可变且不改变刷新状态', () {
    final initial = PaginatedState<int>();
    final cases = [
      initial,
      initial.startRefresh().refreshCompleted(),
      initial.startRefresh().refreshFailed(),
    ];
    for (final old in cases) {
      final source = [1];
      final updated = old.copyWith(items: source);
      source.add(2);
      expect(updated.items, [1]);
      expect(updated.refreshStatus, old.refreshStatus);
      expect(old.items, isEmpty);
      expect(() => updated.items.add(3), throwsUnsupportedError);
      final cleared = updated.copyWith(items: []);
      expect(cleared.items, isEmpty);
      expect(cleared.refreshStatus, old.refreshStatus);
      expect(cleared.copyWith(items: [2]).items, [2]);
      expect(old.copyWith(items: []).refreshStatus, old.refreshStatus);
    }
  });

  test('copyWith 保留首屏请求，仍可正常提交刷新结果', () {
    final loading = PaginatedState<int>().startRefresh().startLoading();
    final updated = loading.copyWith(items: [1]);
    expect(updated.refreshStatus, RefreshStatus.refreshing);
    expect(updated.isRefreshing, isTrue);
    expect(updated.loadStatus, LoadStatus.loading);
    expect(updated.refreshRevision, loading.refreshRevision);
    final completed = updated.refreshCompleted();
    expect(completed.items, [1]);
    expect(completed.refreshStatus, RefreshStatus.completed);
    expect(completed.isRefreshing, isFalse);
    expect(completed.loadStatus, LoadStatus.idle);
  });

  test('copyWith 增删数据时保留刷新和加载更多状态', () {
    final initial = PaginatedState<int>(items: [1]);
    final cases = [
      initial.startRefresh().startLoading(),
      initial.startRefresh().refreshFailed().startLoading().loadFailed(),
      initial.startRefresh().refreshCompleted().loadNoData(),
    ];
    for (final old in cases) {
      final cleared = old.copyWith(items: []);
      final updated = cleared.copyWith(items: [2]);
      expect(cleared.refreshStatus, old.refreshStatus);
      expect(updated.refreshStatus, old.refreshStatus);
      for (final next in [cleared, updated]) {
        expect(next.refreshStatus, old.refreshStatus);
        expect(next.loadStatus, old.loadStatus);
        expect(next.refreshRevision, old.refreshRevision);
      }
    }
  });

  test('首屏与有数据的刷新共用刷新状态，数据独立更新', () {
    var state = PaginatedState<int>();
    expect(state.refreshStatus, RefreshStatus.idle);
    expect(state.items, isEmpty);
    state = state.startRefresh();
    expect(state.refreshStatus, RefreshStatus.refreshing);
    state = state.refreshFailed();
    expect(state.refreshStatus, RefreshStatus.failed);
    state = state.startRefresh().refreshCompleted(items: []);
    expect(state.items, isEmpty);
    expect(state.refreshStatus, RefreshStatus.completed);
    state = state.startRefresh().refreshCompleted(items: [1]);
    expect(state.items, [1]);
    expect(state.refreshStatus, RefreshStatus.completed);
    state = state.startRefresh().refreshFailed();
    expect(state.items, [1]);
    expect(state.refreshStatus, RefreshStatus.failed);
    state = state.startRefresh().refreshCompleted(items: []);
    expect(state.items, isEmpty);
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

  test('业务取消首屏和清除普通结果均回到 idle 并保留数据', () {
    final error = PaginatedState<int>().startRefresh().refreshFailed();
    expect(
      error.startRefresh().refreshToIdle().refreshStatus,
      RefreshStatus.idle,
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
