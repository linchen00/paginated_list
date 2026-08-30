import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paginated_list/paginated_list.dart';

void main() {
  test('公开类型可从根 library 导入', () {
    final state = PaginatedState<int>(items: [1]);
    ScrollView list(List<int> _) => ListView();
    ScrollView grid(List<int> _) => GridView.count(crossAxisCount: 1);
    ScrollView custom(List<int> _) => const CustomScrollView();

    final PaginatedItemsBuilder<int> listBuilder = list;
    final PaginatedItemsBuilder<int> gridBuilder = grid;
    final PaginatedItemsBuilder<int> customBuilder = custom;

    expect(state.items, [1]);
    expect(listBuilder([]), isA<ListView>());
    expect(gridBuilder([]), isA<GridView>());
    expect(customBuilder([]), isA<CustomScrollView>());
  });
}
