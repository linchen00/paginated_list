/// 下拉刷新的当前状态。
enum RefreshStatus {
  /// 未进行刷新交互。
  idle,

  /// 已拉过触发阈值，松手后可刷新。
  canRefresh,

  /// 刷新正在进行。
  refreshing,

  /// 刷新成功，结果正在短暂展示。
  completed,

  /// 刷新失败，结果正在短暂展示。
  failed,
}

/// 加载下一页的当前状态。
enum LoadStatus {
  /// 未进行加载交互。
  idle,

  /// 已拉过触发阈值，松手后可加载。
  canLoading,

  /// 加载正在进行。
  loading,

  /// 已没有更多数据。
  noMore,

  /// 最近一次加载失败，可再次上拉重试。
  failed,
}
