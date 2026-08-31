import 'package:flutter/material.dart';
import 'package:paginated_list/paginated_list.dart';

import 'pre_bound_refresh_example.dart';

void main() => runApp(const ExampleApp());

Widget _buildHeader(RefreshStatus status) => switch (status) {
  RefreshStatus.idle => SizedBox(
    height: 48,
    child: Center(child: Text('下拉刷新')),
  ),
  RefreshStatus.canRefresh => const SizedBox(
    height: 48,
    child: Center(child: Text('松开刷新')),
  ),
  RefreshStatus.refreshing => const SizedBox(
    height: 48,
    child: Center(child: CircularProgressIndicator()),
  ),
  RefreshStatus.completed => const SizedBox(
    height: 48,
    child: Center(child: Text('刷新完成')),
  ),
  RefreshStatus.failed => const SizedBox(
    height: 48,
    child: Center(child: Text('刷新失败')),
  ),
};

Widget _buildFooter(LoadStatus status) => switch (status) {
  LoadStatus.idle => const SizedBox.shrink(),
  LoadStatus.canLoading => const SizedBox(
    height: 48,
    child: Center(child: Text('松开加载')),
  ),
  LoadStatus.loading => const SizedBox(
    height: 48,
    child: Center(child: CircularProgressIndicator()),
  ),
  LoadStatus.noMore => const SizedBox(
    height: 48,
    child: Center(child: Text('没有更多了')),
  ),
  LoadStatus.failed => const SizedBox(
    height: 48,
    child: Center(child: Text('加载失败')),
  ),
};

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: PaginationExample());
  }
}

class PaginationExample extends StatefulWidget {
  const PaginationExample({super.key});

  @override
  State<PaginationExample> createState() => _PaginationExampleState();
}

class _PaginationExampleState extends State<PaginationExample> {
  late final PaginatedState<int> state;
  var page = 0;

  @override
  void initState() {
    super.initState();
    state = PaginatedState<int>();
    _refresh();
  }

  Future<void> _refresh() async {
    state.startRefresh();
    try {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      page = 1;
      state.items = List.generate(20, (index) => index + 1);
      state.refreshCompleted();
    } catch (_) {
      state.refreshFailed();
    }
  }

  Future<void> _loadMore() async {
    state.startLoading();
    try {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (page >= 3) {
        state.loadNoData();
        return;
      }
      final start = state.items.length;
      state.items = [
        ...state.items,
        ...List.generate(20, (index) => start + index + 1),
      ];
      page++;
      state.loadCompleted();
    } catch (_) {
      state.loadFailed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PaginatedList 示例'),
        actions: [
          IconButton(
            tooltip: '绑定前刷新示例',
            icon: const Icon(Icons.hourglass_top),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PreBoundRefreshExample(),
              ),
            ),
          ),
        ],
      ),
      body: PaginatedList<int>(
        loadingTriggerDistance: 100,
        state: state,
        headerBuilder: _buildHeader,
        footerBuilder: _buildFooter,
        onRefresh: _refresh,
        onLoading: _loadMore,
        itemsBuilder: (items) => ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, index) => ListTile(
            leading: CircleAvatar(child: Text('${items[index]}')),
            title: Text('第 ${items[index]} 项'),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: state.requestRefresh,
        tooltip: '程序化刷新',
        child: const Icon(Icons.refresh),
      ),
    );
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }
}
