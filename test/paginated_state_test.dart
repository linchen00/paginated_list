import 'package:flutter_test/flutter_test.dart';
import 'package:paginated_list/paginated_list.dart';

void main() {
  test('items 始终保存不可修改副本', () {
    final source = [1, 2];
    final state = PaginatedState<int>(items: source);
    source.add(3);
    expect(state.items, [1, 2]);
    expect(() => state.items.add(4), throwsUnsupportedError);

    final next = [5];
    state.items = next;
    next.add(6);
    expect(state.items, [5]);
  });

  test('刷新合法状态转移并原子重置加载状态', () {
    final state = PaginatedState<int>(items: [1]);
    var notifications = 0;
    state.addListener(() => notifications++);
    state.startLoading();
    state.startRefresh();
    notifications = 0;
    state.refreshCompleted();
    expect(state.refreshStatus, RefreshStatus.completed);
    expect(state.loadStatus, LoadStatus.idle);
    expect(notifications, 1);
    state.refreshCompleted();
    expect(notifications, 1);
  });

  test('首屏刷新与普通刷新使用互斥状态', () {
    final state = PaginatedState<int>();

    expect(state.isRefreshing, isFalse);
    expect(state.firstPageStatus, FirstPageStatus.idle);
    state.startRefresh();
    expect(state.isRefreshing, isTrue);
    expect(state.firstPageStatus, FirstPageStatus.loading);
    expect(state.refreshStatus, RefreshStatus.idle);

    state.refreshFailed();
    expect(state.isRefreshing, isFalse);
    expect(state.firstPageStatus, FirstPageStatus.error);
    expect(state.refreshStatus, RefreshStatus.idle);

    state.startRefresh();
    state.items = [1];
    state.refreshCompleted();
    expect(state.firstPageStatus, FirstPageStatus.completed);
    expect(state.refreshStatus, RefreshStatus.idle);

    state.startRefresh();
    expect(state.isRefreshing, isTrue);
    expect(state.firstPageStatus, FirstPageStatus.completed);
    expect(state.refreshStatus, RefreshStatus.refreshing);
    state.refreshFailed();
    expect(state.isRefreshing, isFalse);
    expect(state.firstPageStatus, FirstPageStatus.completed);
    expect(state.refreshStatus, RefreshStatus.failed);
  });

  test('加载状态机拒绝非法调用，但允许直接标记没有更多数据', () {
    final state = PaginatedState<int>();
    var notifications = 0;
    state.addListener(() => notifications++);
    state.loadCompleted();
    state.loadFailed();
    expect(notifications, 0);
    state.loadNoData();
    expect(state.loadStatus, LoadStatus.noMore);
    expect(notifications, 1);
    state.resetNoData();
    expect(notifications, 2);

    expect(state.isLoading, isFalse);
    state.startLoading();
    expect(state.isLoading, isTrue);
    state.loadNoData();
    expect(state.isLoading, isFalse);
    expect(state.loadStatus, LoadStatus.noMore);
    state.resetNoData();
    expect(state.loadStatus, LoadStatus.idle);
  });

  test('未绑定的 request 返回清晰错误', () async {
    final state = PaginatedState<int>();
    await expectLater(state.requestRefresh(), throwsA(isA<StateError>()));
    await expectLater(state.requestLoading(), throwsA(isA<StateError>()));
  });
}
