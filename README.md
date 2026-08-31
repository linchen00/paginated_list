# paginated_list

一个精简的 Flutter 分页滚动组件。它负责下拉刷新、上拉加载、指示器和请求展示动画；页码、网络请求及数据合并仍由业务管理。

## 功能

- 支持 `ListView`、`GridView` 和 `CustomScrollView`
- 支持竖向、横向、`reverse` 与 RTL
- 可自定义 Header/Footer，尺寸由 builder 的实际输出决定
- UI 挂载前可通过 `startRefresh()` / `startLoading()` 改变状态
- UI 挂载后可通过 `requestRefresh()` / `requestLoading()` 展示指示器并执行回调
- items 始终以不可修改快照对外提供

## 安装

在 `pubspec.yaml` 中添加：

```yaml
dependencies:
  paginated_list: ^0.0.1
```

## 使用

```dart
final state = PaginatedState<String>();

Future<void> refresh() async {
  try {
    state.startRefresh();
    state.items = await fetchFirstPage();
    state.refreshCompleted();
  } catch (_) {
    state.refreshFailed();
  }
}

Future<void> loadMore() async {
  try {
    state.startLoading();
    final next = await fetchNextPage();
    if (next.isEmpty) {
      state.loadNoData();
    } else {
      state.items = [...state.items, ...next];
      state.loadCompleted();
    }
  } catch (_) {
    state.loadFailed();
  }
}

PaginatedList<String>(
  state: state,
  onRefresh: refresh,
  onLoading: loadMore,
  headerBuilder: (status) => status == RefreshStatus.idle
      ? const SizedBox.shrink()
      : const SizedBox(
          height: 48,
          child: Center(child: CircularProgressIndicator()),
        ),
  footerBuilder: (status) => status == LoadStatus.idle
      ? const SizedBox.shrink()
      : const SizedBox(
          height: 48,
          child: Center(child: CircularProgressIndicator()),
        ),
  itemsBuilder: (items) => ListView.builder(
    itemCount: items.length,
    itemBuilder: (_, index) => ListTile(title: Text(items[index])),
  ),
)
```

`start*()` 只改变状态，不滚动也不调用回调。`request*()` 必须在列表完成挂载后调用，会先展示对应指示器，再等待完整业务回调。同类并发 request 会共享同一个 Future。

数据更新与状态结束彼此独立：`refreshCompleted()`、`loadCompleted()` 不会替换或追加 items。一个 `PaginatedState` 同一时刻只能绑定一个 `PaginatedList`，并由业务方负责 `dispose()`。

`loadingTriggerDistance` 使用列表的真实滚动距离：长列表向末端滚动进入该距离时会直接预加载；内容不足一屏时不会在挂载后自动加载，只有用户主动上拉超过该距离并松手才会触发。一次滚动手势最多触发一次加载请求。

## 自定义指示器

`headerBuilder` 与 `footerBuilder` 为必填参数，返回普通 Widget。组件不提供默认指示器，也不强制尺寸或动画；若某状态应隐藏，请返回 `SizedBox.shrink()`。

```dart
headerBuilder: (status) => switch (status) {
  RefreshStatus.idle => const SizedBox.shrink(),
  RefreshStatus.refreshing => const SizedBox(
      height: 56,
      child: Center(child: CircularProgressIndicator()),
    ),
  _ => const SizedBox(height: 56),
},
```

## 范围

首个版本不支持 `NestedScrollView`、自定义 `ScrollView` 子类、自动页码/游标管理、请求取消或自动数据合并。
