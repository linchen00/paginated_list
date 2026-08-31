import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paginated_list/paginated_list.dart';

import 'support/pagination_test_host.dart';

Widget buildHost(
  PaginationTestHost<int> owner, {
  Key key = const ValueKey('list'),
  PaginatedController? controller,
  AsyncCallback? onRefresh,
  AsyncCallback? onLoading,
  ScrollController? scrollController,
  Duration duration = Duration.zero,
  Duration resultDuration = const Duration(milliseconds: 100),
  ValueChanged<RefreshStatus>? onHeader,
  ValueChanged<LoadStatus>? onFooter,
}) => owner.build(
  () => MaterialApp(
    home: PaginatedList<int>(
      key: key,
      state: owner.value,
      controller: controller ?? owner.controller,
      requestRefreshDuration: duration,
      requestLoadingDuration: duration,
      refreshResultDuration: resultDuration,
      onRefresh: onRefresh,
      onLoading: onLoading,
      headerBuilder: (status) {
        onHeader?.call(status);
        return SizedBox(height: status == RefreshStatus.idle ? 0 : 48);
      },
      footerBuilder: (status) {
        onFooter?.call(status);
        return SizedBox(height: status == LoadStatus.idle ? 0 : 48);
      },
      itemsBuilder: (items) => ListView.builder(
        controller: scrollController,
        itemExtent: 40,
        itemCount: items.length,
        itemBuilder: (_, index) => Text('item${items[index]}'),
      ),
    ),
  ),
);

void main() {
  test('未绑定和已释放的 Controller 请求返回错误', () async {
    final controller = PaginatedController();
    expect(controller.isAttached, isFalse);
    await expectLater(controller.requestRefresh(), throwsStateError);
    await expectLater(controller.requestLoading(), throwsStateError);
    controller.dispose();
    await expectLater(controller.requestRefresh(), throwsStateError);
  });

  for (final loading in [false, true]) {
    testWidgets('${loading ? '加载' : '刷新'}快照变化不打断请求且重复调用共享 Future', (
      tester,
    ) async {
      final owner = PaginationTestHost<int>(items: List.generate(50, (i) => i));
      final scroll = ScrollController(initialScrollOffset: 400);
      addTearDown(scroll.dispose);
      final callback = Completer<void>();
      var calls = 0;
      Future<void> run() {
        calls++;
        owner.value = loading
            ? owner.value.startLoading()
            : owner.value.startRefresh();
        return callback.future;
      }

      await tester.pumpWidget(
        buildHost(
          owner,
          scrollController: scroll,
          duration: const Duration(milliseconds: 200),
          onRefresh: run,
          onLoading: run,
        ),
      );
      await tester.pump();
      Future<void> request() => loading
          ? owner.controller.requestLoading()
          : owner.controller.requestRefresh();
      final first = request();
      expect(identical(request(), first), isTrue);
      expect(calls, 0);
      await tester.pump();
      final position = scroll.position;
      owner.value = owner.value.copyWith(
        items: List.generate(50, (i) => i + 1),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(identical(scroll.position, position), isTrue);
      expect(identical(request(), first), isTrue);
      expect(calls, 0);
      await tester.pumpAndSettle();
      expect(calls, 1);
      owner.value = owner.value.copyWith(
        items: List.generate(50, (i) => i + 2),
      );
      await tester.pump();
      expect(identical(request(), first), isTrue);
      callback.complete();
      await first;
    });
  }

  testWidgets('业务快照更新保留滚动位置', (tester) async {
    final owner = PaginationTestHost<int>(items: List.generate(50, (i) => i));
    final scroll = ScrollController(initialScrollOffset: 300);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(buildHost(owner, scrollController: scroll));
    await tester.pump();
    final position = scroll.position;
    owner.value = owner.value.copyWith(items: List.generate(50, (i) => i + 1));
    await tester.pump();
    expect(identical(scroll.position, position), isTrue);
    expect(scroll.offset, 300);
  });

  testWidgets('同一不可变状态可供两个无 Controller 列表使用', (tester) async {
    final state = PaginatedState<int>(items: [1]);
    Widget list() => Expanded(
      child: PaginatedList<int>(
        state: state,
        headerBuilder: (_) => const SizedBox.shrink(),
        footerBuilder: (_) => const SizedBox.shrink(),
        itemsBuilder: (items) => ListView(children: [Text('${items.first}')]),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: Row(children: [list(), list()])));
    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('更换 Controller 使旧展示操作失效，不改变业务状态', (tester) async {
    final owner = PaginationTestHost<int>(items: List.generate(50, (i) => i));
    final second = PaginatedController();
    addTearDown(second.dispose);
    final scroll = ScrollController(initialScrollOffset: 400);
    addTearDown(scroll.dispose);
    var calls = 0;
    Future<void> callback() async {
      calls++;
    }

    await tester.pumpWidget(
      buildHost(
        owner,
        onRefresh: callback,
        scrollController: scroll,
        duration: const Duration(milliseconds: 200),
      ),
    );
    await tester.pump();
    final snapshot = owner.value;
    final old = owner.controller.requestRefresh();
    final error = expectLater(old, throwsStateError);
    await tester.pump();
    await tester.pumpWidget(
      buildHost(
        owner,
        controller: second,
        scrollController: scroll,
        onRefresh: callback,
      ),
    );
    expect(owner.controller.isAttached, isFalse);
    expect(second.isAttached, isTrue);
    await tester.pumpAndSettle();
    await error;
    expect(calls, 0);
    expect(identical(snapshot, owner.value), isTrue);
    final next = second.requestRefresh();
    await tester.pumpAndSettle();
    await next;
    expect(calls, 1);
  });

  testWidgets('更换 Key 隔离旧业务 Future 和新请求', (tester) async {
    final owner = PaginationTestHost<int>(items: [1]);
    final oldCallback = Completer<void>();
    final newCallback = Completer<void>();
    await tester.pumpWidget(
      buildHost(owner, onRefresh: () => oldCallback.future),
    );
    await tester.pump();
    final old = owner.controller.requestRefresh();
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      buildHost(
        owner,
        key: const ValueKey('new-list'),
        onRefresh: () => newCallback.future,
      ),
    );
    await tester.pump();
    final next = owner.controller.requestRefresh();
    expect(identical(old, next), isFalse);
    await tester.pumpAndSettle();
    oldCallback.complete();
    await old;
    expect(identical(owner.controller.requestRefresh(), next), isTrue);
    newCallback.complete();
    await next;
  });

  testWidgets('卸载前未开始业务的请求失败，业务开始后卸载不取消 Future', (tester) async {
    final owner = PaginationTestHost<int>(items: [1]);
    var calls = 0;
    final callback = Completer<void>();
    await tester.pumpWidget(
      buildHost(
        owner,
        onRefresh: () {
          calls++;
          return callback.future;
        },
      ),
    );
    await tester.pump();
    final early = owner.controller.requestRefresh();
    final error = expectLater(early, throwsStateError);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await error;
    expect(calls, 0);
    expect(owner.controller.isAttached, isFalse);
    await tester.pumpWidget(
      buildHost(
        owner,
        onRefresh: () {
          calls++;
          return callback.future;
        },
      ),
    );
    await tester.pump();
    final running = owner.controller.requestRefresh();
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    callback.complete();
    await running;
  });

  testWidgets('动画期间外部开始业务则跳过重复回调', (tester) async {
    final owner = PaginationTestHost<int>(items: List.generate(50, (i) => i));
    final scroll = ScrollController(initialScrollOffset: 400);
    addTearDown(scroll.dispose);
    var calls = 0;
    await tester.pumpWidget(
      buildHost(
        owner,
        scrollController: scroll,
        duration: const Duration(milliseconds: 200),
        onRefresh: () async {
          calls++;
        },
      ),
    );
    await tester.pump();
    final request = owner.controller.requestRefresh();
    await tester.pump();
    owner.value = owner.value.startRefresh();
    await tester.pumpAndSettle();
    await request;
    expect(calls, 0);
    expect(owner.value.isRefreshing, isTrue);
  });

  testWidgets('双向展示串行且业务可并发，Future 等待各自完整回调', (tester) async {
    final owner = PaginationTestHost<int>(items: List.generate(50, (i) => i));
    final refresh = Completer<void>();
    final loading = Completer<void>();
    final calls = <String>[];
    await tester.pumpWidget(
      buildHost(
        owner,
        duration: const Duration(milliseconds: 100),
        onRefresh: () {
          calls.add('refresh');
          owner.value = owner.value.startRefresh();
          return refresh.future;
        },
        onLoading: () {
          calls.add('loading');
          owner.value = owner.value.startLoading();
          return loading.future;
        },
      ),
    );
    await tester.pump();
    final first = owner.controller.requestRefresh();
    final second = owner.controller.requestLoading();
    await tester.pumpAndSettle();
    expect(calls, ['refresh', 'loading']);
    expect(owner.value.isLoading && owner.value.isRefreshing, isTrue);
    expect(identical(owner.controller.requestRefresh(), first), isTrue);
    expect(identical(owner.controller.requestLoading(), second), isTrue);
    refresh.complete();
    await first;
    expect(identical(owner.controller.requestLoading(), second), isTrue);
    loading.complete();
    await second;
  });

  testWidgets('结果提示收起不发业务通知，普通更新不重播，同帧相同结果可再次展示', (tester) async {
    final owner = PaginationTestHost<int>(items: [1]);
    RefreshStatus? presented;
    var notifications = 0;
    owner.addListener(() {
      notifications++;
    });
    await tester.pumpWidget(buildHost(owner, onHeader: (s) => presented = s));
    owner.value = owner.value.startRefresh().refreshCompleted();
    await tester.pump();
    expect(presented, RefreshStatus.completed);
    final result = owner.value;
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(presented, RefreshStatus.idle);
    expect(identical(owner.value, result), isTrue);
    expect(notifications, 1);
    owner.value = owner.value.copyWith(items: [2]).startLoading();
    await tester.pump();
    expect(presented, RefreshStatus.idle);
    owner.value = owner.value.startRefresh().refreshCompleted();
    await tester.pump();
    expect(presented, RefreshStatus.completed);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(presented, RefreshStatus.idle);
  });

  testWidgets('挂载不补播旧结果，修改时长不重播已消费结果', (tester) async {
    final owner = PaginationTestHost<int>(items: [1]);
    owner.value = owner.value.startRefresh().refreshFailed();
    RefreshStatus? presented;
    await tester.pumpWidget(buildHost(owner, onHeader: (s) => presented = s));
    expect(presented, RefreshStatus.idle);
    await tester.pumpWidget(
      buildHost(
        owner,
        resultDuration: Duration.zero,
        onHeader: (s) => presented = s,
      ),
    );
    expect(presented, RefreshStatus.idle);
    expect(owner.value.refreshStatus, RefreshStatus.failed);
  });

  testWidgets('新刷新使旧结果计时器失效，活动结果修改时长重新计时', (tester) async {
    final owner = PaginationTestHost<int>(items: [1]);
    RefreshStatus? presented;
    await tester.pumpWidget(
      buildHost(
        owner,
        resultDuration: const Duration(seconds: 1),
        onHeader: (s) => presented = s,
      ),
    );
    owner.value = owner.value.startRefresh().refreshCompleted();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    owner.value = owner.value.startRefresh();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(presented, RefreshStatus.refreshing);
    owner.value = owner.value.refreshFailed();
    await tester.pump();
    await tester.pumpWidget(
      buildHost(
        owner,
        resultDuration: const Duration(milliseconds: 10),
        onHeader: (s) => presented = s,
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(presented, RefreshStatus.idle);
    expect(owner.value.refreshStatus, RefreshStatus.failed);
  });
  testWidgets('同帧业务完成优先于未结束的回调 Future', (tester) async {
    final owner = PaginationTestHost<int>(items: [1]);
    final cleanup = Completer<void>();
    LoadStatus? presented;
    await tester.pumpWidget(
      buildHost(
        owner,
        onFooter: (s) => presented = s,
        onLoading: () {
          owner.value = owner.value.startLoading().loadCompleted(items: [1, 2]);
          return cleanup.future;
        },
      ),
    );
    await tester.pump();
    final request = owner.controller.requestLoading();
    await tester.pumpAndSettle();
    expect(owner.value.items, [1, 2]);
    expect(presented, LoadStatus.idle);
    expect(identical(owner.controller.requestLoading(), request), isTrue);
    cleanup.complete();
    await request;
  });

  testWidgets('外部滚动中断展示时不执行业务且快照不变', (tester) async {
    final owner = PaginationTestHost<int>(items: List.generate(50, (i) => i));
    final scroll = ScrollController(initialScrollOffset: 600);
    addTearDown(scroll.dispose);
    var calls = 0;
    await tester.pumpWidget(
      buildHost(
        owner,
        scrollController: scroll,
        duration: const Duration(seconds: 1),
        onRefresh: () async {
          calls++;
        },
      ),
    );
    await tester.pump();
    final before = owner.value;
    final request = owner.controller.requestRefresh();
    final error = expectLater(request, throwsStateError);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    scroll.jumpTo(300);
    await tester.pumpAndSettle();
    await error;
    expect(calls, 0);
    expect(identical(owner.value, before), isTrue);
  });

  testWidgets('释放已绑定 Controller 使未开始的业务失效', (tester) async {
    final owner = PaginationTestHost<int>(items: [1]);
    var calls = 0;
    await tester.pumpWidget(
      buildHost(
        owner,
        onRefresh: () async {
          calls++;
        },
      ),
    );
    await tester.pump();
    final request = owner.controller.requestRefresh();
    final error = expectLater(request, throwsStateError);
    owner.controller.dispose();
    expect(owner.controller.isAttached, isFalse);
    await tester.pumpAndSettle();
    await error;
    expect(calls, 0);
    await expectLater(owner.controller.requestLoading(), throwsStateError);
  });

  testWidgets('布局完成前和缺少回调的请求返回清晰错误', (tester) async {
    final owner = PaginationTestHost<int>(items: [1]);
    Future<void>? early;
    await tester.pumpWidget(
      buildHost(
        owner,
        onRefresh: () async {},
        onHeader: (_) {
          if (early == null) {
            early = owner.controller.requestRefresh();
            early!.ignore();
          }
        },
      ),
    );
    await expectLater(early!, throwsStateError);
    await tester.pumpWidget(buildHost(owner));
    await expectLater(owner.controller.requestRefresh(), throwsStateError);
    await expectLater(owner.controller.requestLoading(), throwsStateError);
  });

  testWidgets('业务异常由 Future 传播，组件不自动生成失败状态', (tester) async {
    final owner = PaginationTestHost<int>(items: [1]);
    final error = StateError('business');
    await tester.pumpWidget(
      buildHost(
        owner,
        onRefresh: () async {
          owner.value = owner.value.startRefresh();
          throw error;
        },
      ),
    );
    await tester.pump();
    final request = owner.controller.requestRefresh();
    final result = expectLater(request, throwsA(same(error)));
    await tester.pumpAndSettle();
    await result;
    expect(owner.value.refreshStatus, RefreshStatus.refreshing);
    await owner.controller.requestRefresh(); // 已忙，不重复执行业务。
  });

  testWidgets('刷新结果保留时仍可再次下拉，未配置 Controller 也能交互', (tester) async {
    final owner = PaginationTestHost<int>(items: List.generate(50, (i) => i));
    var calls = 0;
    await tester.pumpWidget(
      owner.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: owner.value,
            refreshResultDuration: const Duration(milliseconds: 20),
            headerBuilder: (_) => const SizedBox(height: 48),
            footerBuilder: (_) => const SizedBox.shrink(),
            onRefresh: () async {
              calls++;
              owner.value = owner.value.startRefresh().refreshCompleted();
            },
            itemsBuilder: (items) => ListView.builder(
              itemExtent: 40,
              itemCount: items.length,
              itemBuilder: (_, i) => Text('${items[i]}'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 1; i <= 2; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(calls, i);
      expect(owner.value.refreshStatus, RefreshStatus.completed);
    }
    expect(owner.controller.isAttached, isFalse);
  });

  testWidgets('noMore 阻止手势加载但允许显式程序化请求', (tester) async {
    final owner = PaginationTestHost<int>(items: [1]);
    owner.value = owner.value.loadNoData();
    var calls = 0;
    await tester.pumpWidget(
      buildHost(
        owner,
        onLoading: () async {
          calls++;
        },
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(calls, 0);
    final request = owner.controller.requestLoading();
    await tester.pumpAndSettle();
    await request;
    expect(calls, 1);
    expect(owner.value.isNoMore, isTrue);
  });
  for (final outcome in ['completed', 'failed', 'cancelled']) {
    for (final publishStart in [false, true]) {
      testWidgets('动画期间外部刷新 $outcome 后不重复请求（开始单独发布：$publishStart）', (
        tester,
      ) async {
        final owner = PaginationTestHost<int>(
          items: List.generate(50, (i) => i),
        );
        final scroll = ScrollController(initialScrollOffset: 400);
        addTearDown(scroll.dispose);
        var calls = 0;
        await tester.pumpWidget(
          buildHost(
            owner,
            scrollController: scroll,
            duration: const Duration(milliseconds: 500),
            resultDuration: const Duration(seconds: 2),
            onRefresh: () async {
              calls++;
            },
          ),
        );
        await tester.pump();
        final request = owner.controller.requestRefresh();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final started = owner.value.startRefresh();
        if (publishStart) {
          owner.value = started;
          await tester.pump(const Duration(milliseconds: 50));
        }
        owner.value = switch (outcome) {
          'completed' => started.refreshCompleted(),
          'failed' => started.refreshFailed(),
          _ => started.refreshToIdle(),
        };
        final terminal = owner.value;
        await tester.pumpAndSettle();
        await request;
        expect(calls, 0);
        expect(identical(owner.value, terminal), isTrue);
      });
    }
  }

  for (final kind in ['list', 'grid', 'custom']) {
    for (final axis in Axis.values) {
      testWidgets('首屏进度与错误切换保留 $kind 的 $axis 视口并支持重试', (tester) async {
        final owner = PaginationTestHost<int>();
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        const viewKey = ValueKey('source-scroll-view');
        const centerKey = ValueKey('source-center');
        final pending = <Completer<void>>[];
        VoidCallback? retry;
        var calls = 0;
        await tester.pumpWidget(
          owner.build(
            () => MaterialApp(
              home: PaginatedList<int>(
                state: owner.value,
                controller: owner.controller,
                firstPageProgressIndicatorBuilder: () => const Text('progress'),
                firstPageErrorIndicatorBuilder: (onRetry) {
                  retry = onRetry;
                  return const Text('error');
                },
                onRefresh: () {
                  calls++;
                  owner.value = owner.value.startRefresh();
                  final completion = Completer<void>();
                  pending.add(completion);
                  return completion.future;
                },
                headerBuilder: (_) => const SizedBox.shrink(),
                footerBuilder: (_) => const SizedBox.shrink(),
                itemsBuilder: (items) => switch (kind) {
                  'list' => ListView(
                    key: viewKey,
                    controller: scroll,
                    scrollDirection: axis,
                    reverse: true,
                    children: [for (final item in items) Text('item$item')],
                  ),
                  'grid' => GridView.count(
                    key: viewKey,
                    controller: scroll,
                    scrollDirection: axis,
                    reverse: true,
                    crossAxisCount: 1,
                    children: [for (final item in items) Text('item$item')],
                  ),
                  _ => CustomScrollView(
                    key: viewKey,
                    controller: scroll,
                    scrollDirection: axis,
                    reverse: true,
                    center: centerKey,
                    anchor: 0.25,
                    slivers: [
                      SliverList(
                        key: centerKey,
                        delegate: SliverChildListDelegate([
                          for (final item in items) Text('item$item'),
                        ]),
                      ),
                    ],
                  ),
                },
              ),
            ),
          ),
        );
        await tester.pump();
        final position = scroll.position;
        void checkViewport() {
          final view = tester.widget<CustomScrollView>(find.byKey(viewKey));
          expect(view.controller, same(scroll));
          expect(view.scrollDirection, axis);
          expect(view.reverse, isTrue);
          expect(scroll.positions, hasLength(1));
          expect(scroll.position, same(position));
        }

        checkViewport();
        final request = owner.controller.requestRefresh();
        request.ignore();
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(find.text('progress'), findsOneWidget);
        checkViewport();
        owner.value = owner.value.refreshFailed();
        pending[0].complete();
        await request;
        await tester.pumpAndSettle();
        expect(find.text('error'), findsOneWidget);
        checkViewport();
        retry!();
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(find.text('progress'), findsOneWidget);
        checkViewport();
        owner.value = owner.value.refreshCompleted(items: [1]);
        pending[1].complete();
        await tester.pumpAndSettle();
        expect(find.text('item1'), findsOneWidget);
        checkViewport();
        if (kind == 'custom') {
          final view = tester.widget<CustomScrollView>(find.byKey(viewKey));
          expect(view.center, centerKey);
          expect(view.anchor, 0.25);
        }
      });
    }
  }
}
