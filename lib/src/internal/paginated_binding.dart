/// Controller 驱动其唯一视图所需的内部端口。
abstract interface class PaginatedBinding {
  Future<void> requestRefresh({bool animate = true});
  Future<void> requestLoading({bool animate = true});
  void cancelControllerRequests();
}

final class PaginatedBindingErrors {
  const PaginatedBindingErrors._();

  static StateError notBound(String operation) => StateError(
    '$operation 需要一个已挂载且完成布局的 PaginatedList。'
    '若只想在 UI 挂载前改变状态，请发布 startRefresh() 或 startLoading() 返回的新状态。',
  );
}
