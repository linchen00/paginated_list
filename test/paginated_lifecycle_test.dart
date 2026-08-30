import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paginated_list/paginated_list.dart';

Widget _buildHost({
  required PaginatedState<int> state,
  AsyncCallback? onRefresh,
  AsyncCallback? onLoading,
  Duration refreshResultDuration = const Duration(seconds: 1),
}) {
  return MaterialApp(
    home: PaginatedList<int>(
      key: const ValueKey<String>('paginated-list'),
      state: state,
      onRefresh: onRefresh,
      onLoading: onLoading,
      refreshResultDuration: refreshResultDuration,
      headerBuilder: (_) => const SizedBox.shrink(),
      footerBuilder: (_) => const SizedBox.shrink(),
      itemsBuilder: (_) => ListView(children: const [Text('item')]),
    ),
  );
}

void main() {
  testWidgets('替换 state 后刷新请求与旧 Future 隔离', (tester) async {
    final oldState = PaginatedState<int>();
    final newState = PaginatedState<int>();
    final oldCompleter = Completer<void>();
    final newCompleter = Completer<void>();
    var newCalls = 0;

    await tester.pumpWidget(
      _buildHost(state: oldState, onRefresh: () => oldCompleter.future),
    );
    await tester.pump();
    final oldFuture = oldState.requestRefresh();
    await tester.pump();

    await tester.pumpWidget(
      _buildHost(
        state: newState,
        onRefresh: () {
          newCalls++;
          return newCompleter.future;
        },
      ),
    );
    await tester.pump();
    final newFuture = newState.requestRefresh();
    await tester.pump();

    expect(identical(oldFuture, newFuture), isFalse);
    expect(identical(newState.requestRefresh(), newFuture), isTrue);
    await tester.pumpAndSettle();
    expect(newCalls, 1);

    oldCompleter.complete();
    await oldFuture;
    expect(identical(newState.requestRefresh(), newFuture), isTrue);

    newCompleter.complete();
    await newFuture;
  });

  testWidgets('替换 state 后加载请求与旧 Future 隔离', (tester) async {
    final oldState = PaginatedState<int>();
    final newState = PaginatedState<int>();
    final oldCompleter = Completer<void>();
    final newCompleter = Completer<void>();
    var newCalls = 0;

    await tester.pumpWidget(
      _buildHost(state: oldState, onLoading: () => oldCompleter.future),
    );
    await tester.pump();
    final oldFuture = oldState.requestLoading();
    await tester.pump();

    await tester.pumpWidget(
      _buildHost(
        state: newState,
        onLoading: () {
          newCalls++;
          return newCompleter.future;
        },
      ),
    );
    await tester.pump();
    final newFuture = newState.requestLoading();
    await tester.pump();

    expect(identical(oldFuture, newFuture), isFalse);
    expect(identical(newState.requestLoading(), newFuture), isTrue);
    expect(newCalls, 1);

    oldCompleter.complete();
    await oldFuture;
    expect(identical(newState.requestLoading(), newFuture), isTrue);

    newCompleter.complete();
    await newFuture;
  });

  testWidgets('结果展示期间修改时长会重新计时', (tester) async {
    final state = PaginatedState<int>();
    state.startRefresh();
    await tester.pumpWidget(_buildHost(state: state, onRefresh: () async {}));
    await tester.pump();
    state.refreshCompleted();
    await tester.pump();

    await tester.pumpWidget(
      _buildHost(
        state: state,
        onRefresh: () async {},
        refreshResultDuration: const Duration(milliseconds: 10),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));

    expect(state.refreshStatus, RefreshStatus.idle);
  });
}
