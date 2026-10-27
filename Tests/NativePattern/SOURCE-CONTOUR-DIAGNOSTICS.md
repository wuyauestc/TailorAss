# 原始裁片轮廓诊断与半圆修复

生成纸样时提前报告已能严格确认的轮廓内部交叉；不修改源顶点、曲线、参数、接缝或导入 JSON 字节。报告包含中文裁片名、从 1 开始的源边号，以及多片裙或插片裙的调整建议。导入的异常纸样保留预览及 JSON 导出，禁用制作设置、打印和 3D。修正参数后同款式可正常生成。

## 诊断边界

`GarmentCodeContourDiagnostics` 对原始储存坐标做向外舍入区间计算，确认直线／直线或圆弧／直线的严格内部、横向交叉。相邻边也检查，但排除真实端点交点。根参数、圆弧扫向和横向性必须都能确认；分母包含零、区间不确定、非有限值、退化或超出 200,000 对预算不冒充交叉证据。圆弧参数使用与 SVG 一致的半径修正和选弧规则。

空报告不是简单闭合轮廓证书。Bezier 组合、圆弧／圆弧、相切、重叠及不确定情况仍依赖后续网格和制作校验；不得用这个提前提示替代那些门槛。最初的普通浮点交点筛选曾将接近平行的简单四边形误报，已用独立精确分数反例否定并替换；反例保存在 `Fixtures/contour-diagnostics/`。

## 已验证的原始问题

目录中 4 个不同源确实自交：两个体型下的四片拼接裙（圆周倍数 0.75、下摆弧线 −0.35），以及两个体型下的指定铅笔基础／Sun 插片组合。独立原曲线解析求交和未改动的固定上游 `d449629` 都确认相同问题，未调用渲染器。不能通过放宽网格校验接收这些输入，也不能因此整体禁用多片裙、负弧度或 Sun 插片。

独立原始证明：`/private/tmp/TailorAssActualSourceCrossingDiagnostic-smsmv0i9/delivery-manifest.json`。关于弧度临界值的补充说明位于 `/private/tmp/TailorAssSourceCrossingThresholdReviewAddendum-wo88wk2e/`：正射线上的交点还必须落在有限边与所选圆弧内，不能仅凭一个弧度临界值拒绝参数。

## 半圆一致性

正好 180° 的圆弧中，大弧标志不应反转给定扫向。旧 helper 在 `largeArc=true` 时会反转半圆；这同时影响显示、打印和部分网格采样。现已修正共享 Geometry、PrintPlan、PanelMesher 及 6 个相关采样点，包含 SVG 半径不足而自动修正到半圆的情况；非半圆公式不变。

测试包括 8 个半圆半径／扫向／大弧组合，和未改动 `svgpathtools` 的独立对照。23 个平面网格案例通过；618 个目录 case 重新生成的全部源字节与分层裙修复后的基准一致，548 个不同源没有被重新缩放或改写。

## 实际运行证据

- 19 个解析诊断控制、4 个真实源、12 个反向／平移／缩放变体通过；每个交叉边对及位置都检查。618 case 扫描恰好报告上述 4 个，原纸样字节保持。冻结运行分别为 `/private/tmp/TailorAssContourDiagnosticsCertifiedFinal/` 与后续全部 helper 修正后的 `/private/tmp/TailorAssContourDiagnostics.hbi5h8tw/`，不能将前者描述为包含后来所有 helper 的单次运行。
- 主几何、局部化、接缝、PDF、缝份与制作标记、基础模式、25 个下装分支、24 个分层裙对照及诊断测试通过。初次整体命令曾因合成 fixture 放错目录而失败，随后 PDF 检查又揭示重复半圆 helper；两次失败保留，修复后的受影响测试实际通过。日志为 `/private/tmp/TailorAss2DGeometryAllArcHelpers.log`、`/private/tmp/TailorAss2DAfterSemicircleRemainingRepaired.log`、`/private/tmp/TailorAssPanelMesherSemicircle.log`。
- 同一 788 文件快照的 iOS arm64 和 Simulator arm64/x86_64 Release 构建实际通过，116 个 App Swift 文件、9 个 Native Swift 文件、每架构 25 个 C++ 编译输入与 12 个资源核对通过。该 App 明确绑定 Native111，不能冒充后来的 Native117。
- Device Hub 中 iPhone 17／iOS 27.0 Simulator 的安装包 15 个文件与构建产物哈希一致。实际操作验证异常生成提示、同款曲线改回 0 后正常生成四片、系统文件选择器导入异常源、制作／PDF／3D 禁用、JSON 原样保存。通过系统分享保存的 31,536 字节 JSON 与输入 SHA256 相同：`62acbe6c0332cfcefba6486f7b7c45b13b63e5b01ce94b104229654f361c47ae`。截图、AX 文本、构建与安装绑定在 `/private/tmp/TailorAssCurrentFullAppReleaseFSC111Arc/`。

这些是二维诊断、打印一致性、构建和实际模拟器界面证据，不是所有款式的成衣仿真验收，也不是 iPhone 17 Pro 真机性能测量。

后续截图复查发现：原固定高度预览在长警告或展开 JSON 时会挤出可视区域，虽然禁用与原字节导出行为正常，页面布局仍不合格。当前源码已将整页改为可滚动，并为画布设置随窗口变化的有界高度；长警告完整参与布局，不再独立截断。此修正晚于上述 App788 冻结构建。后续 App795 已独立完成两平台 Release 构建，并在 Device Hub 实装核验完整长警告、整页滚动、展开 JSON 后底部导出、异常源禁用选项及普通双片裙的选择／接缝高亮／平移／适配全图。当前安装包绑定 Native117 与新单 ULP 求解修正，交付记录为 `/private/tmp/TailorAssCurrentFullAppReleaseFSC117Scrollable/delivery-manifest.json`（SHA256 `dbd22dac1fb93a7285d1e502ba6cdab1e5d5877a07bb8c267f7c5d91a07fb5c1`）。普通纸样 PDF／制作菜单可用；本次没有重复原字节保存测试，不将此前 App788 的保存证据冒充新运行。

复现诊断：

```sh
python3 Tests/NativePattern/run-contour-diagnostics.py
# 可额外传入 run-native-catalog-inputs.py 的冻结输出根目录
python3 Tests/NativePattern/run-contour-diagnostics.py --catalog-inputs /path/to/catalog-export
```
