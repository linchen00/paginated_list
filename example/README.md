# 分页示例

运行 `flutter run` 查看 Riverpod 示例，根组件包含 ProviderScope。

- `pagination_notifier.dart` 直接使用 `Notifier<PaginatedState<int>>`，不包装或转发分页通知。
- 主页面通过 `ref.watch` 同时更新列表和标题中的数据数量。
- 刷新按钮使用独立 PaginatedController；普通手势不要求 Controller。
- `isNoMore` 判断是否还有下一页，刷新成功统一重置加载状态。
- 示例业务用请求代次隔离过期响应；这不是分页组件提供的网络功能。
- 顶部入口展示普通 StatefulWidget 在首帧前发布 loading 快照的场景。
- 点击首页右上角「数据增删与空状态」进入 `items_state_example.dart` 演示：添加一项、逐项删除或清空数据，直接观察 `copyWith` 后的列表与空页面切换。
- 演示页可手动开始刷新并选择成功或失败，实时显示 `items` 数量和 `refreshStatus`；刷新期间也可增删数据。无数据时展示进度、错误或空页面，有数据时始终展示列表。该页面不发送网络请求。
- 演示页分别显示业务状态与界面展示状态。添加数据后开始刷新并选择失败，可以看到 Header 提示默认在 500ms 后开始收起，展示状态回到 `idle`，业务状态仍保留 `failed`。无数据时错误页面持续保留，直到重试或点击「重置状态」。Header 状态直接取自 `headerBuilder` 的参数，不通过额外计时器模拟，也不写回业务状态。

`flutter test` 验证页面渲染、数据增删与空状态切换、挂载前加载、Provider 释放及旧加载响应隔离。
