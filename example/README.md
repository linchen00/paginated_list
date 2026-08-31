# 分页示例

运行 `flutter run` 查看 Riverpod 示例，根组件包含 ProviderScope。

- `pagination_notifier.dart` 直接使用 `Notifier<PaginatedState<int>>`，不包装或转发分页通知。
- 主页面通过 `ref.watch` 同时更新列表和标题中的数据数量。
- 刷新按钮使用独立 PaginatedController；普通手势不要求 Controller。
- `isNoMore` 判断是否还有下一页，刷新成功统一重置加载状态。
- 示例业务用请求代次隔离过期响应；这不是分页组件提供的网络功能。
- 顶部入口展示普通 StatefulWidget 在首帧前发布 loading 快照的场景。

`flutter test` 验证页面渲染、挂载前加载、Provider 释放及旧加载响应隔离。
