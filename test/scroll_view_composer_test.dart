import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paginated_list/paginated_list.dart';

Widget _emptyHeader(RefreshStatus _) => const SizedBox.shrink();

Widget _emptyFooter(LoadStatus _) => const SizedBox.shrink();

void main() {
  testWidgets('ListView 的 controller、方向和内容顺序得到保留', (tester) async {
    final controller = ScrollController();
    final state = PaginatedState<int>(items: [1, 2]);
    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: state,
          headerBuilder: (_) => const Text('header'),
          footerBuilder: (_) => const Text('footer'),
          itemsBuilder: (items) => ListView(
            controller: controller,
            reverse: true,
            padding: const EdgeInsets.all(12),
            children: items.map((item) => Text('item$item')).toList(),
          ),
        ),
      ),
    );
    await tester.pump();

    final composed = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(composed.controller, same(controller));
    expect(composed.reverse, isTrue);
    expect(controller.positions, hasLength(1));
    expect(find.text('header'), findsNothing);
    expect(find.text('item1'), findsOneWidget);
    expect(find.text('footer'), findsOneWidget);
  });

  testWidgets('GridView 与 CustomScrollView 均可组合', (tester) async {
    final gridState = PaginatedState<int>(items: [1]);
    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: gridState,
          headerBuilder: _emptyHeader,
          footerBuilder: _emptyFooter,
          itemsBuilder: (items) => GridView.count(
            crossAxisCount: 1,
            children: items.map((item) => Text('$item')).toList(),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    final customState = PaginatedState<int>(items: [1]);
    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: customState,
          headerBuilder: _emptyHeader,
          footerBuilder: _emptyFooter,
          itemsBuilder: (_) => const CustomScrollView(
            slivers: [SliverToBoxAdapter(child: Text('custom'))],
          ),
        ),
      ),
    );
    expect(find.text('custom'), findsOneWidget);
  });
}
