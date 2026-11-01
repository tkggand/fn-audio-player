import 'package:flutter/widgets.dart';

/// 与 `design/v3` 同口径的三档断点（映射 Flutter WindowSizeClass）。
enum FnBp { mobile, laptop, desktop }

const double kFnBpLaptop = 600;
const double kFnBpDesktop = 1024;

/// 壳层度量（design/v3/css/tokens.css）。
const double kFnRailW = 72;
const double kFnSideW = 232;
const double kFnSideWC = 72;
const double kFnBarH = 72;
const double kFnDrawerW = 380;

FnBp fnBpForWidth(double width) {
  if (width < kFnBpLaptop) return FnBp.mobile;
  if (width < kFnBpDesktop) return FnBp.laptop;
  return FnBp.desktop;
}

/// 读取当前窗口档位；随窗口尺寸变化自动重建。
FnBp fnBpOf(BuildContext context) =>
    fnBpForWidth(MediaQuery.sizeOf(context).width);

extension FnBpX on FnBp {
  bool get isMobile => this == FnBp.mobile;
  bool get isWide => this != FnBp.mobile;
}
