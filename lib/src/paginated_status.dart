/// 刷新的当前状态，包括首屏请求和下拉刷新。
enum RefreshStatus {
  /// 未进行刷新交互。
  idle,

  /// 已拉过触发阈值，松手后可刷新；仅供视图展示，不存入业务快照。
  canRefresh,

  /// 刷新正在进行。
  refreshing,

  /// 刷新成功；业务保留结果，视图独立决定提示的展示时间。
  completed,

  /// 刷新失败；无数据时显示首屏错误，有数据时短暂展示 Header 提示。
  failed,
}

/// 加载下一页的当前状态。
enum LoadStatus {
  /// 未进行加载交互。
  idle,

  /// 已拉过触发阈值，松手后可加载；仅供视图展示，不存入业务快照。
  canLoading,

  /// 加载正在进行。
  loading,

  /// 已没有更多数据。
  noMore,

  /// 最近一次加载失败，可再次上拉重试。
  failed,
}
