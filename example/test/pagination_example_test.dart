import 'package:example/main.dart';
import 'package:example/pre_bound_refresh_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('示例首页可以构建', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('PaginatedList 示例'), findsOneWidget);
    expect(find.byTooltip('程序化刷新'), findsOneWidget);
    expect(find.byTooltip('绑定前刷新示例'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('PaginatedState 可在绑定 UI 前进入刷新状态', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PreBoundRefreshExample()));
    await tester.pump();

    expect(find.text('绑定前刷新示例'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('pre-bound-refreshing')),
      findsOneWidget,
    );
    expect(find.text('绑定前已进入 refreshing'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(find.text('预绑定刷新第 1 项'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
  });
}
