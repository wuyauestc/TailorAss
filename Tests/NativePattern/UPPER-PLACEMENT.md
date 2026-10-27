# 原生上装三维初始摆放

`GarmentCodeUpperPlacement` 将完整原生 `Shirt` / `FittedShirt` 的全部独立裁片放到固定 GarmentCode 构造时的三维位置。它不缝合裁片，不修改纸样、质量、接缝、人体、支撑点或物理验收标准。构造时的分片摆放不能作为成衣仿真通过的证据。

固定上游提交：`d449629979028123a5c4dc9e732a2ec19b7fce31`。主要依据：

- [`bodice.py`](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/bodice.py)：四片衣身、领袖投影、袖片接口、左右依赖参数、抹胸。
- [`tee.py`](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/tee.py)：普通上装衣身的长度与肩斜。
- [`sleeves.py`](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/sleeves.py)：袖片原点、袖口的层级旋转和接口摆放、人体手臂姿态。
- [`collars.py`](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/collars.py)、[`bands.py`](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/bands.py)：立领、翻领、风帽与三类袖口。

## 接口与来源约束

`sourceMap(document:body:design:)` 返回全部源 panel 的刚体矩阵、原始序列化纸样顶点的三维坐标和旋转后的面料法向。这里的顶点仍然是纸样顶点，不是三角化布料网格。

`prepare(document:body:design:targetEdgeMeters:)` 必须为全部源 panel 建立真实 `GarmentCodePanelMesher.Mesh`，再对每个 `flatPositions` 应用相同矩阵。任何一片的三角化失败都会带 panel 名称抛错；不能退回轮廓、丢弃袖领或声称已完成网格。默认目标边长 0.04 m，每片最多 6000 顶点 / 16000 面，全套最多 60000 顶点。

两种接口都要求：

1. 原生文档标明固定上游提交及 `includes_3d_placement=false`。
2. 文档内完整人体与完整设计参数，必须与调用参数精确一致。
3. 校验原文档，并按排序键、不转义斜杠的 JSON 计算 canonical SHA-256；重新运行原生二维生成器，整份源 SHA 必须一致。
4. `meta.upper` 仅为 `Shirt` 或 `FittedShirt`，且没有腰头、下装。组合须交给完整组合映射，不能只拿上装丢弃其它组件。
5. 结果的 panel ID 集合必须与完整源集合完全相同，半身组件集合也逐一验证。

## 坐标、序列化原点与矩阵

上游人体与构造几何使用厘米，最终本地三维使用米，以 `_waist_level` 为 y=0。源纸样顶点已经被上游序列化规则减去了首顶点的**向零截断整数**；不能再次把完整首顶点减掉，也不能丢掉小数残差。

每片状态记录 `anchor`：原构造首顶点的三维世界坐标，单位厘米。层级 bbox / 接口计算使用：

```text
physical(p) = anchor + Rphysical × (p − serializedFirstVertex)
Rphysical   = Rx × Ry × Rz       // SciPy intrinsic "XYZ"
```

最后给真实 meshgen 的变换则为：

```text
placed(localMetres) = (Rz × Ry × Rx) × localMetres
                    + anchor / 100 − [0, _waist_level / 100, 0]
```

这两个欧拉约定在翻领后片 `[90°,45°,0°]` 时明显不同，不能混用。`GarmentCodePanelPlacement.Transform` 已负责最终 meshgen 的旋转约定和单位换算。面料法向使用同一个旋转矩阵，不含平移。

左半身源纸样本身已反射并反转边顺序。为重放构造层级，先恢复右向局部几何；全半身构造完后 `anchor.x` 取反、Euler y/z 取反，再使用实际左源纸样。前后衣身均无额外 180° 旋转；它们的法向来自真实源绕向。

## 动态构造公式

以下公式单位均为厘米，`H=height−head_l`，`t=tan(_shoulder_incl)`，`F=(bust−back_width)/2`，`B=back_width/2`，`S=shoulder_w/2`。

### 四片衣身

普通上装：`Lb=shirt.length×waist_line`，`Lf=Lb−t(F−B)`。

| 右向 panel | anchor.x | anchor.y | anchor.z |
|---|---:|---|---:|
| 前身 | 0 | `H−Lf−t×shirt.width×F` | 30 |
| 后身 | 0 | `H−Lb−t×shirt.width×B` | −25 |

合体上装：`Lf=waist_over_bust_line−t(F−S)`，`Lb=waist_line−t(B−S)`。

| 右向 panel | anchor.x | anchor.y | anchor.z |
|---|---:|---|---:|
| 前身 | 0 | `H−Lf−tF` | 30 |
| 后身 | 0 | `H−Lb−tB+tB/4` | −25 |

合体后片首顶点原本有 `tB/4` 的非整数 y 偏移，这一项必须保留。领口 / 袖窿投影、腰省、侧省、宽度、下摆张量改变的实际轮廓全部从当前源几何取，不使用固定默认轮廓。

### 袖片与袖口

1. 使用实际袖片闭合端：前袖为最终最后一条边的 start，后袖为最终第一条边的 end。
2. 对该闭合端按原上游 `set_pivot` 的整数截断得到最初 anchor：`[−S−Int(closing.x), H−Int(closing.y), ±15]`。
3. 三类袖口保留全部真实前后片：`CuffBand` 两片，`CuffSkirt` 两片，`CuffBandSkirt` 四片。组合袖口先将裙袖口放在条袖口下方，bbox 间隔 2 cm。
4. 全袖口组件围绕自身完整 bbox 的顶部中心旋转 −90°；用其真实 top 接口对袖片 out 接口，顶部对齐，沿原 `place_by_interface` 方向留 2 cm。
5. 全袖组件（包括全部袖口）围绕完整 bbox 顶部中心旋转人体 `arm_pose_angle`。
6. 从原始 stitch 引用恢复 sleeve.in 与 torso armhole 接口，包含投影后的所有拆分边；顶部对齐，间隔 `−1−arm_pose_angle/10`。

接口摆放逐帧重建实际几何 bbox。直线取端点；曲线取 9 个内部样本及两个端点，圆弧按参数等分，Bezier 按弧长等分，复现上游的边界采样。没有复用某个 fixture 的袖片平移。

上游仅对无袖款使用 `ArmholeSquare` / `ArmholeAngle`；有袖时强制实际 `ArmholeCurve`。模块遵守真实源的这个分支，不为不存在的方形反袖窿制造替代袖片。

### 领片与风帽

下表为右向半身，`d=collar.component.depth`，宽度、弧长、领口端点都取真实源。

| 组件 | 构造 anchor / 旋转 |
|---|---|
| Turtle 前 / 后片 | `[-panelWidth, H+d−Int(d), ±10]`，无旋转 |
| SimpleLapel 前片 | `[-2d,H+2d,35]`，无旋转 |
| SimpleLapel 立式后片 | `[-panelWidth,H+2d−Int(d),−10]`，无旋转 |
| SimpleLapel 平翻后片 | `[-topArcLength,H+2d,−10] + Rx90×Ry45×[-topChord/2,0,0]`，序列化 Euler `[90,45,0]` |
| Hood2Panels 半片 | `[-frontNeckHalfWidth,H+10−backNeckDepth,−frontNeckHalfWidth]`，Euler `[0,−90,0]` |

七种领口轮廓仍是衣身投影，本身不等于新增领片；`Turtle` / `SimpleLapel` / `Hood2Panels` 的真实附加片单独映射。全七领型及三种领组件的上游依赖关系保持不变。

左右不对称遵守 `Shirt.eval_dep_params`：左右共用右侧 shirt.length、前后领深，组件领被抑制；左右其它袖 / 衣身参数分别保留。Fitted strapless 分支不生成领袖组件，即使原设计中的袖开关仍为有袖，也不能凭开关额外添加原源不存在的片。

## 独立证明与已知二维问题

长期 oracle 为 `Fixtures/upper-placement-oracles.json`，包含固定提交、两个人体的完整量体、完整默认设计、逐例改动、原官方完整 paper、上游源文件 SHA、生成器 SHA。原官方 `MetaGarment` 实际生成 **108 例 / 868 片**：普通 / 合体、有袖 / 无袖、立肩、长宽角度、三袖口、三领组件、七领型、三袖窿、手臂姿态 30° / 60°、左右不对称与抹胸。

有袖原生二维轮廓与原官方轮廓存在既有差异。例：默认 Shirt 袖口宽原生为 21.022650290876637 cm，官方为 21.074827322322385 cm；袖片顶点最大差约 0.052479 cm，衣身袖窿顶点也约差 0.009104 cm。变化会经接口 bbox 和组件旋转改变初始平移，当前矩阵与原官方不同纸样的最大平移差约 **2.013 mm**。初始严格原官方对比失败证据仍保留，不能用放宽公式容差或复制原 fixture 的平移来掩盖。

为隔离“二维几何差异”与“三维层级摆放错误”，`ReplayUpperPlacement.py` 对**完全相同的当前原生源纸样**实际调用未修改上游的 `Panel.set_pivot/top_center_pivot/center_x`、`Component.rotate_by/place_below/place_by_interface/mirror/assembly`。衣身首 pivot 用真实官方衣身构造器恢复；衣身和领片保留独立原 `MetaGarment` oracle 的结果，不调用 Swift 摆放代码。

该严格同源 oracle 的冻结结果：

- 107 个实际生成的原生输入，完整 **860 片**矩阵 / 基向量 / 原顶点位置 / 法向 / 源 SHA 检查通过；最大平移误差 **2.926e−14 m**。
- 10 套默认及领袖组合的全部真实网格通过，**92 片 / 17550 顶点**。
- 取消、不同人体、不同设计、组合中丢弃腰头或下装均拒绝。
- Swift 5 + 默认 MainActor 隔离类型检查通过。

仍有一个原生二维生成失败：`all-FittedShirt-standing`。完整输入和原官方8片结果都保存在 oracle 内，原生没有生成可供摆放的纸样。最小复现是在 oracle 的 all body / baseDesign 上设：

```json
{
  "meta.upper": "FittedShirt",
  "meta.bottom": null,
  "meta.wb": null,
  "sleeve.sleeveless": false,
  "sleeve.sleeve_angle": 40
}
```

`standing_shoulder=false` 和 `true` 均抛 `invalidPanel("right-front-sleeve-opening-inverse")`。因此不能把问题仅归为立肩参数。测试明确输出 `fullNativeInputCoverageComplete=false`，不会把该例当成摆放成功。这轮不改既有二维程序；后续修复需重新导出源、更新同源 oracle，并将这例纳入真实成功计数。

三角化预算是另一个独立限制：试验目标边长 0.08 m 时曾触发既有 mesher refinement 预算失败；改为当前默认 0.04 m 后上述 10 套完整源网格均通过。`sourceMap` 证明与 `prepare` 网格成功分别报告；单有纸样顶点位置证明不代表布料网格已完成。

## 日常回归与重建 oracle

日常回归只需本仓库 Swift / JSON，不依赖临时上游环境：

```sh
sh Tests/NativePattern/run-upper-placement.sh
```

`GARMENTCODE_UPPER_OUTPUT` 指定输出目录；默认 `/private/tmp/TailorAssUpperPlacement`。每次先复制全部模型、资源、fixture、测试和生成脚本到独立快照，保存 `build-input-manifest.json` 后编译。`GARMENTCODE_UPPER_KEEP_SNAPSHOT=1` 可保留该快照。报告同时记录原官方不同源的差异与严格同源误差，不能把前者称为原纸样一致。

需重建时，先用固定提交的未修改上游，运行：

```sh
python3 Tests/NativePattern/GenerateUpperPlacementGoldens.py \
  --upstream-dir /absolute/path/to/GarmentCode
GARMENTCODE_UPPER_EXPORT_NATIVE=/private/tmp/UpperNativeExport \
  sh Tests/NativePattern/run-upper-placement.sh
python3 Tests/NativePattern/ReplayUpperPlacement.py \
  --upstream-dir /absolute/path/to/GarmentCode \
  --native-exports /private/tmp/UpperNativeExport
sh Tests/NativePattern/run-upper-placement.sh
```

生成器也支持显式 `--extracted-source-proof` 的固定提交只读提取，记录该证明的 SHA。官方生成器的 Python 环境为 NumPy 1.26.4 / SciPy 1.13.1，另需 PyYAML、svgpathtools、matplotlib、psutil。仅未使用的 Cairo 图片输出被 stub；实际几何和刚体构造不替换。Replay 逐个核对 oracle 保存的上游源文件 SHA，并核对原生导出整份 canonical 源 SHA。原生导出模式只调用现有二维生成器，不调用 UpperPlacement。

目前最后一个原生失败会使 replay 在保存所有成功结果与明确失败列表后以非零码结束；这是有意保留的不完整状态。修复完成前不能将该退出码解释为全量成功。

上游构造的人体尺寸 / 手臂姿态与本地三维人台仍可能不同。此模块交付的是完整、保真、可验证的初始化；成衣需要后续真实缝合、碰撞和原有严格质量验收。
