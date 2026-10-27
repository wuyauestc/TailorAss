# 逆袖窿零交点分支修复

修复只涉及 `GarmentCodeGeometry.swift` 的 `GarmentCodeSleeveGeometry.evenOpenings` / `intersectionParameter`：垂直平分线与前逆袖窿没有交点时返回 `nil`、不切分原曲线，随后照常旋转前后曲线。未修改优化器、人体、设计参数、立肩、曲线方向、面料、接缝、panel 有效性或成衣质量门槛。

## 实际根因

固定 GarmentCode `d449629979028123a5c4dc9e732a2ec19b7fce31` 的 [`operators.py:410`](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/pygarment/garmentcode/operators.py#L410) 中，`even_armhole_openings` 允许 SVG 交点列表为空：仅 `len(intersect_t)>=1` 且交点不在端点附近时才重新分配前后开口，否则保留原曲线，再执行最终旋转。

原生实现将“没有交点”错误地当成 `invalidPanel`。异常发生在前后逆曲线均拟合返回之后，不是优化器抛错，也不是袖片闭合检查失败。

最小输入为旧 `upper-placement-oracles.json` 的 all body / baseDesign，加上：

```json
{
  "meta.upper": "FittedShirt",
  "meta.bottom": null,
  "meta.wb": null,
  "sleeve.sleeveless": false,
  "sleeve.sleeve_angle": 40
}
```

`standing_shoulder=false` 与 `true` 都能触发旧原生错误，而未修改上游都生成 8 片有效纸样。官方前后逆曲线 L-BFGS-B 均正常收敛，初值为五个 0，无 bounds，目标函数包含弧长、两端切向、70 点最大曲率和末端扩展正则；目标值分别约 `0.0129711718515` / `0.0122071696916`。两半身的真实交点列表全部为 `[]`。

原生失败快照的实测 bisector signed cross-product 范围为 `[-531.8930255,-2.3894137]`，全负，也确实无交点。这是允许的可选重分配分支，不能据此判断后续完整袖片无效。

全套官方初始控制点、目标、初值、bounds、迭代、最终 shift / 控制点、重分配前后曲线和完整源纸样均已长期保存于 `Fixtures/inverse-sleeve-oracles.json`。观察脚本只包装记录参数和返回值，实际计算仍调用未修改上游。

## 新回归与历史证据

`GenerateInverseSleeveGoldens.py` 首先逐一核对旧上装 oracle 保存的固定上游源 SHA，再运行 12 套官方样例：两人体 × Shirt / FittedShirt × 默认有袖 / angle40 立肩关 / angle40 立肩开。

`run-inverse-sleeve.sh` 覆盖 4 次无交点、20 次正常有交点的真实官方曲线，逐条验证整个曲线、边数和原总弧长；同时要求 12 套完整原生纸样都生成、保持原参数来源且通过原有效性检查。严格官方重分配误差为约 `2.493e-14 cm`。

同一长期 fixture 还通过 `ReplayUpperPlacement.py` 保存 12 套 angle40 立肩关 / 开及默认款的**相同原生纸样**官方三维 frame；回归逐片验证完整 96 片的矩阵、三基向量、全部原纸样顶点与面料法向，最大 frame 平移误差 `9.632e-14 m`。

该测试也单独报告现有原生 simplex 与官方 L-BFGS 的二维差异。报告中的 `existingNativeVsOfficialMatchedEdgeSampleDifferenceCentimeters` 是源局部坐标下同边序号 / 同参数的直接比较，包含序列化 pivot 差异，不是独立刚体对齐后的轮廓 Hausdorff 距离，不能据此宣称完整原生二维与官方精确一致。本次没有为它添加宽松通过门槛；没有交点这一错误分支与拟合差异分别处理。

新 `Fixtures/upper-placement-complete-oracles.json` 基于原官方 108 例，使用修复后的完整原生源重新调用未修改上游刚体构造，保存逐片实际 frame。旧 `upper-placement-oracles.json` 及 860 片 / 一个二维失败的旧报告均未覆盖。新导出中**原来可生成的 107 套 canonical source SHA 逐一完全不变**，仅新增此前失败的那一套。

新完整上装严格 frame 回归为 **108 例 / 868 片**通过，无源生成失败，最大同源平移误差 `9.626e-14 m`；10 套完整网格仍为 92 片 / 17550 顶点通过。不同于原官方二维纸样造成的原始平移差另行报告，最大约 2.090 mm，不混同于严格同源误差。

统一快照下完整 `run-acceptance.sh` 已通过：356 源几何 / 拓扑 / 缝合关系、拟合质量与 ULP 稳定、导入、中文、接缝显示、打印规划、56 页 PDF、缝份、制造标记和 9 页制造 PDF、基础模式 54 个实际量测、25 个官方下装分支。该快照同时包含另行修复的 Fitted+flare-rise 调度；本修复自身只改变可选交点语义。

当前完整上装回归应使用：

```sh
sh Tests/NativePattern/run-inverse-sleeve.sh
sh Tests/NativePattern/run-upper-placement-complete.sh
sh Tests/NativePattern/run-acceptance.sh
```

`run-upper-placement-complete.sh` 在独立快照中将新 complete fixture 映射到原严格 harness 的旧文件名，不修改仓库的历史 fixture 或严格断言。旧 `run-upper-placement.sh` 的历史 fixture 仍描述修复前一个失败，不能拿它作为修复后完整输入的最新 oracle。

重建新的独立重放：

```sh
python3 Tests/NativePattern/GenerateInverseSleeveGoldens.py \
  --upstream-dir /absolute/path/to/GarmentCode
GARMENTCODE_INVERSE_EXPORT_NATIVE=/private/tmp/InverseSleeveNative \
  sh Tests/NativePattern/run-inverse-sleeve.sh
python3 Tests/NativePattern/ReplayUpperPlacement.py \
  --upstream-dir /absolute/path/to/GarmentCode \
  --native-exports /private/tmp/InverseSleeveNative \
  --fixture Tests/NativePattern/Fixtures/inverse-sleeve-oracles.json
sh Tests/NativePattern/run-inverse-sleeve.sh
cp Tests/NativePattern/Fixtures/upper-placement-oracles.json \
  Tests/NativePattern/Fixtures/upper-placement-complete-oracles.json
GARMENTCODE_UPPER_EXPORT_NATIVE=/private/tmp/UpperCompleteNative \
  sh Tests/NativePattern/run-upper-placement-complete.sh
python3 Tests/NativePattern/ReplayUpperPlacement.py \
  --upstream-dir /absolute/path/to/GarmentCode \
  --native-exports /private/tmp/UpperCompleteNative \
  --fixture Tests/NativePattern/Fixtures/upper-placement-complete-oracles.json
sh Tests/NativePattern/run-upper-placement-complete.sh
```

Python 环境与原上装 oracle 相同：NumPy 1.26.4 / SciPy 1.13.1。日常 Swift 回归读取已保存 JSON，无需上游仓库和 Python 依赖。

新测试每次复制完整依赖，保存精确源 SHA 后编译。`GARMENTCODE_INVERSE_OUTPUT` / `GARMENTCODE_UPPER_OUTPUT` 指定报告目录，`GARMENTCODE_INVERSE_KEEP_SNAPSHOT=1` / `GARMENTCODE_UPPER_KEEP_SNAPSHOT=1` 保留编译快照。三维 frame 通过仍只证明真实裁片的初始摆放，不等于已缝合或可穿成衣。
