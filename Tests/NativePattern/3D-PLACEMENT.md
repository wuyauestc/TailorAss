# 裁片初始三维摆放：固定上游规则与原生装配接口

本文记录 GarmentCode `d449629979028123a5c4dc9e732a2ec19b7fce31` 的初始摆放规则，供全部款式的原生装配继续实现。初始摆放、实际缝合、人体接触和最终物理效果是四项不同的验证，不能互相代替。这里没有宣称全部款式已经接入 App。

## 已可重复验证的内容

```sh
sh Tests/NativePattern/run-panel-placement.sh
python3 Tests/NativePattern/verify-torso-placement.py
```

第一条对 14 个真实官方裁片检查源单位、实际 meshgen 的复合旋转、腰零点及原布面法向，覆盖 Shirt、FittedShirt、Pants、PencilSkirt、袖片、翻领及帽领；另检查单轴 90°、米／厘米等价、缺失和非有限变换拒绝、原生二维纸样无摆放标记拒绝、源 JSON 不变与取消。输出默认位于 `/private/tmp/TailorAssPanelPlacement`。

第二条只用标准 Python 库，对 480 个固定官方 torso 裁片检查动态摆放公式：两组人体的完整 meta 组合网格，以及默认、长宽裙摆变化、非对称、抹胸、袖片、翻领及帽领版本。平移误差为 0 cm，旋转均为零。输出默认位于 `/private/tmp/TailorAssTorsoPlacement`，同时记录输入 fixture 哈希与生成脚本哈希。fixture 由 `GenerateOfficialGoldens.py` 生成，该脚本要求上述完整固定提交；本检查不需要上游 Python 依赖，也不重新生成官方文件。

`GarmentCodePanelPlacement` 是读取已有摆放的通用原语。它不把只有二维几何的原生文档当成已有三维装配，不负责猜测袖领角色、修改人体姿势或生成最终缝合结果。

## 坐标、旋转与 pivot

实际上游 `pygarment/meshgen/boxmeshgen.py` 调用 `pygarment/pattern/rotation.py:euler_xyz_to_R`：

```
p_world_m = Rz(z°) * Ry(y°) * Rx(x°) * p_source_m
            + translation / units_in_meter
            - (0, body._waist_level / 100, 0)
```

`geometryPanels()` 已把源单位转换为厘米，mesher 又转为米，因此不能再次缩放 `mesh.flatPositions`。源 `translation` 仍采用文档声明的单位，必须单独除以 `units_in_meter`。当前本地人体以腰线为 Y=0、+Y 向上、+Z 向前；上游初始平移则以地面为原点。

不要依靠 RealityKit 的 Euler 命名猜测次序。上游 Panel 使用 SciPy `Rotation.as_euler('XYZ')` 导出，但实际 meshgen 用上述显式乘积；复合角验证以实际 meshgen 为准。

上游 `Panel.set_pivot(q, replicate_placement=True)` 先将平移设为旧变换下的完整 `q`，然后在源二维顶点中减去 `int(q.x), int(q.y)`，两者不是同一值。`int` 向零截断。`Panel.assembly()` 会对第一条边起点再做一次这种操作。当前 Swift 已保留源二维的整数 pivot 约定；装配不能重复扣除这些整数，也不能把完整小数 pivot 替换成整数。

`Panel.mirror()` 对源二维 x 反射、平移 x 取反，Euler 的 y/z 取反，再以 `autonorm()` 恢复外侧布面法向。Swift 左片已经在二维反射并反转边序，三维装配不能再次反射一次。`mesh.sourceClockwise` 保留原法向符号：源 CCW 为 +Z，源 CW 为 −Z，再使用同一个旋转变换法向。单纯平移和腰零点变更不影响法向。

## 四片上装：Shirt / FittedShirt

以下量均为厘米；`t` 使用角度转弧度后的正切。

```
H = height - head_l
t = tan(_shoulder_incl)
F = (bust - back_width) / 2
B = back_width / 2
S = shoulder_w / 2
```

所有四片 torso 的旋转均为 `[0,0,0]`。前片平面 z=+30 cm，后片 z=−25 cm。左右片的 x 平移均为 0；左右形状已在源二维坐标中镜像。前片原法向 +Z，后片原法向 −Z，**没有额外的 180° 后片旋转**。

### Shirt

```
Wf = shirt.width * F
Wb = shirt.width * B
Lb = shirt.length * waist_line
Lf = Lb - t * (F - B)
T_front = (0, H - Lf - t * Wf, +30)
T_back  = (0, H - Lb - t * Wb, -25)
```

`shirt.flare` 只改变源几何。领口、袖窿投影不会改变这条底部 pivot 或上述原始平移。非对称左侧使用 `left.shirt.width`；官方强制两侧使用主 `shirt.length`，不能因左侧字段没有 length 而取一个新默认长度。

### FittedShirt

```
Lf = waist_over_bust_line - t * (F - S)
Lb = waist_line - t * (B - S)
p0_back_y = t * B / 4
T_front = (0, H - Lf - t * F, +30)
T_back  = (0, H - Lb - t * B + p0_back_y, -25)
```

后片的序列化源顶点已经减去 `Int(p0_back_y)`；其第一个顶点还保留小数余量。平移中必须加完整 `p0_back_y`，这与实际上游固定输出一致；不能只加 `Int(p0_back_y)`，也不能再从 mesh 中减一次。默认前片 Ty 为 97.85775552378857 cm，后片为 103.895647186128 cm；这两个数只是公式的回归例，运行时必须根据当前人体重新计算。

侧省、腰省、领袖投影、左右非对称和抹胸改变实际源轮廓与接缝图，不能用四片普通 T 恤替代。抹胸顶边标签为 `strapless_top`，其图中没有肩缝，不能虚构肩缝或普通肩支撑。

### 源边角色与辅助支撑

完整源 `stitches` 是缝合关系依据；`right_ftorso-e2` 一类序列化边编号会因投影、分段、无省道或抹胸改变，不能跨所有参数硬编码。对于已确认的 native 四片程序：

- 同片接缝为实际省道，保留真实省口和共用省尖。
- 相同左右侧的前／后片之间，肩边位于 `*_armhole` 和 `*_collar` 两个标签边之间，其余连接为分段侧缝。
- 左右前片相连为前中缝，左右后片相连为后中缝。
- 抹胸使用 `strapless_top` 单独建立装配与支撑语义。

普通接缝在实际 meshgen 中为 A 正向、B 反向；带 `right_wrong` 标记时为 A/B 同向。标签、真实源边和已确认程序一起确定角色，未知导入不能只看长度或边号猜测意图。

±30/25 cm 的前后分离平面只用于初始摆放。若把两侧肩点都固定在那里，肩缝不可能闭合。实际肩缝两侧必须可自由靠拢；辅助支撑只能使用明确的人体锚点，保留源边长和真实缝合间距，并在文案中标明数值支撑。

## 袖片及袖口

源程序：`assets/garment_programs/sleeves.py:SleevePanel/Sleeve`、`bodice.py:BodiceHalf.add_sleeves`。

1. SleevePanel 在源形状的 `edges[-1].start` 设置整数 pivot，然后初始移到 `(-shoulder_w/2, H, 0)`。
2. 前／后袖片分别再移 z=+15 / −15 cm。
3. 可选袖口先以组件 top-center bbox pivot 旋转 z=−90°，再按袖端接口 `alignment='top', gap=2` 放置。
4. 整个袖子组件围绕其三维 bbox 顶部中心，旋转 z=`body.arm_pose_angle`；不能只旋转局部点而忘记旋转各片之间的相对平移。
5. 袖子与真实袖窿接口再做 `alignment='top'` 放置，`gap=-1-arm_pose_angle/10` cm。该值是上游针对 30°～60°手臂姿势的启发式，不是碰撞间距或实际缝份。
6. 左半身最后做镜像；袖山褶量、袖口抽褶和站肩都保留真实源接口，不强行压成等长。

袖口三种类型为 `CuffBand`、`CuffSkirt`、`CuffBandSkirt`；裤口也复用它们。组件初始前后 z 为 ±15 cm，再经所属袖／裤接口的组合变换。最终需要保留全套 sleeve/cuff 源裁片、接口褶量及组件 pivot，不能复制某个默认 fixture 的最终变换用于不同参数。

当前标准人体只按腰、臀及高度有限拟合，没有根据 `arm_pose_angle` 重摆手臂，也未按全部上身量体重建。直接读取官方袖片平面不证明其与当前 MakeHuman 肩、臂和腕的位置匹配；需有上肢锚点/姿势映射和独立人体穿插验证。

## 领口组件

源程序：`assets/garment_programs/collars.py`。`lf/lb` 为实际前／后领口投影弧长；d 为领深，H 同上。

| 组件 | 构造时的摆放规则 | 仍需保留的内容 |
|---|---|---|
| Turtle | 前带 `(-lf/2,H+d,+10)`，后带 `(-lb/2,H+d,-10)` | 先应用 StraightBandPanel 的 top-center pivot 与 center_x；上述是增量，不可直接冒充最终 JSON 平移 |
| SimpleLapel 前领 | `(-2d,H+2d,+35)` | 真正前领形状、翻折缝的 right_wrong、原颈接口 |
| SimpleLapel 后领（立领） | `(-lb/2,H+2d,-10)` | 普通带状后领，部分接口 right_wrong |
| SimpleLapel 后领（平翻） | `(-lb,H+2d,-10)`，绕 panel pivot 转 `[90°,45°,0°]` | 圆弧后领与复合旋转；实际 meshgen 为 RzRyRx |
| Hood2Panels | 每侧 hood 先转 y=−90°、移 x=−width/2，再加 y=H+10；左侧镜像后 y 旋转为 +90° | 真实前后领底曲线、两片帽中缝、帽深/帽长及原始 pivot |

最终 JSON 还包含 `Panel.assembly()` 的第一点 pivot 更新。文档中表格是构造操作顺序，不能丢弃既有 pivot 后只写一组平移。通用模块已验证非零帽领和复合翻领源变换，但这些组件的 native 动态摆放、缝合后形态和人体接触尚需独立集成验证。

## 裤装

源程序：`assets/garment_programs/pants.py:PantPanel/PantsHalf/Pants`。无袖口独立裤装的最终序列化变换可用下式重建；默认及 `pants-varied` 的 8 片已对原始 fixture 核对，最大误差 1.43e−14 cm。该公式不是裤装已收敛的证明。

```
frontHip = (hips - hip_back_width) / 2
frontExtension = frontHip / 4
totalExtension = (leg_circ - hips/2 + 5) * pants.width
backExtension = totalExtension - frontExtension
flare = leg_circ * (pants.flare - 1) / 4
L = pants.length * _leg_length
D_front = pants.rise * hips_line
D_back  = D_front * 1.1
hip_front = frontHip
hip_back  = hip_back_width/2

T_right.x = -0.5 - flare - Int(hip + extension)
T_right.y = _waist_level - D - crotch_hip_diff - Int(L-crotch_hip_diff)
T_right.z = front ? +25 : -20
T_left.x  = -T_right.x
T_left.yz = T_right.yz
rotation  = [0,0,0]
```

这包括早期 crotch-bottom pivot 与最终第一点 pivot 的整数约定。袖口会先扣减裤身长度，因此启用 cuff 时 L 要改为扣减后值，并把真实 cuff 组件按裤口 `alignment='left',gap=5` 放置。负 flare、极短裤及复杂接口的完整参数覆盖仍需额外 fixture 和三维测试，不能把上述 8 片外推成全范围完成。

裤装需要独立左右腿包体和真正裆缝，不能用裙装包络代替。前后裤片原法向仍为 +Z/−Z。1.1 的后侧腰臀深度带来实际吃势；默认源码中的同片腰省、两段裆缝、两段外侧缝、内侧缝都必须保留，不能把所有不等长接缝认作普通等长缝。

## 铅笔裙及其他裙类

PencilSkirt 的前／后片先用源轮廓 bbox 的 top-center 做整数 pivot，再移到 `(0,_waist_level,+25/-20)`，最后序列化第一点 pivot。普通轮廓中，设每片 hip 为 `frontHip` 或 `hip_back_width/2`：

```
lowWidth = hips * (flare-1)/4 + hip
angleShift = tan(low_angle) * lowWidth
topY = length * _leg_length + rise * hips_line * (front ? 1 : 1.05)
T.x = hip - lowWidth - Int(hip)
T.y = _waist_level + angleShift - Int(max(topY,abs(angleShift)))
T.z = front ? +25 : -20
```

默认及窄低／宽低／宽高四种配置的 8 片已核对平移完全一致。复杂装饰切口若改变 bbox 或原始第一点，需要依照实际源操作重新计算，不能盲用此简化式。实际省道、前后和左右开衩、Sun/SIGGRAPH 装饰切口均须保留。

| 裙类／组件 | 上游初始摆放结构 | native 后续要求 |
|---|---|---|
| Skirt2 | 两片自然腰高度，前 z+25、后 z−20，top-center pivot | 当前已有旧结构网格/辅助抽褶预览；完整独立缝合及腰头连接需新验收 |
| SkirtCircle | 真实环扇形前后片，Y=`_waist_level`、z±15 | 已有真实源圆裙基础；整体平面展开与缝后锥形不同，不可修改源径向长度 |
| AsymmSkirtCircle | 非同心/非等长下摆的两片源面板 | 独立计算两片形状和高度差，不能替换为对称圆裙 |
| SkirtManyPanels | dist=`bottom edge length/(2*tan(pi/n))`，首片移 `(-dist,_waist_level,0)`，先 Ry−90 再使法向对齐 `(-dist,0,panel_w/2)`，沿 Y 轴分布 n 片 | 圆周放置与每条真实侧缝；弧形 panel_curve 和不同片数均需覆盖 |
| SkirtLevels | 逐层生成真实基础组件；若基础裙有 low_angle，每个后续层绕 Z 转 `-low_angle`，再按真实 top/bottom 接口加 gap5 放置 | 保留所有层和褶量，不把多层缩成单片裙；每层自由连接而非全部固定腰线 |
| GodetSkirt | 先生成 PencilSkirt 或 Skirt2，再把每块三角插片按真实切口位置放置 | 插片、切口两侧和省道全部保留；插片不是图案纹理 |
| StraightWB / FittedWB | 真实带状／环扇形；矩形做 top-center pivot，环扇形以内弧端点 y=0 构造；按 rise/width 取腰臀尺寸，前 z+20 后−15，再经组合接口移动 | 已有独立腰头求解；与衣/裙/裤连接时必须取消连接处多余固定，按真实接口决定吃势／抽褶 |

SkirtLevels/Godet/多片裙的完整 native 变换和三维结果尚未由本文验证。上表用于保留全部目标范围，不意味着仅实现 torso 即完成“全部3D”。

## 组合装配及未完成的验证

上游 `BaseComponent.place_by_interface()` 用真实接口的三维 bbox 定义对齐点。center 取中心；top/bottom 取 Y 最大/最小；源码中的 left 取 X 最大、right 取 X 最小，不能按名称猜相反方向。缺省 gap 方向是接口中心减组件 bbox 中心，再归一化；增量为 `targetAlignmentPoint - (selfAlignmentPoint + gapDirection*gap)`。它只改变平移，不自动补旋转。

MetaGarment 依次添加 upper、WB、lower：后一个组件通过真实接口置于前一个组件下方，gap=5 cm，再追加真实接缝。Fitted 上衣会令 lower rise=1。组合后的最终变换与各组件独立变换不同；不能简单并排显示，也不能用多个独立文档的哈希冒充完整源文档。

**腰头与圆裙的自然腰语义**：`bands.py:58–66` 令 `rise+width≤1`，顶口按 `rise+width` 取尺寸，FittedWB 下口按 `rise`；StraightBandPanel 顶部 pivot 后带身向下，随后 `bands.py:70–71` 将其移到 `_waist_level`。`meta_garment.py:82–91` 把裙腰连接到腰头下口，没有把裙子独立腰线固定在自然腰、再令腰头向上延伸的步骤。由于整数 pivot 约定，默认 StraightWB 的初始上缘端点实际位于自然腰上方 0.69674 cm，下缘位于自然腰下方 4 cm；FittedWB 顶口端点在自然腰、下口端点约在下方 4.47/4.68 cm，口沿圆弧本身也不是恒高线。官方初始接口 gap=5 cm 是装配分离距离，不是最终缝后腰高或固定间距。不得为了让某次物理测试通过而反转这条腰位语义。

尚需逐款完成并保留证据的项目包括：

- native 动态袖领、袖口、裤装、全部裙类和层级/完整成衣摆放；左右非对称及特殊切口不能省略。
- 每条真实 source stitch 的方向、翻面、普通/吃势/抽褶意图；细分后实际未附着节点、完整源 SHA、源边长/面积/质量不变。
- 与本地标准人体的肩颈、上肢、裆部、双腿位置/姿势匹配；当前三围与身高有限拟合不能冒充所有人体尺寸重建。
- 合理辅助支撑、真实连接处自由受力、末态自交及人体面交叉、独立闭合人体内外检查、接缝间隙和持续收敛。
- 各实验面料、完整 UI 配置/取消/重新计算/导出链、不同参数与两组人体，以及 iPhone 实机性能。

二维源几何、JSON 导出和打印数据保持独立。没有同人体、同参数、同材料的官方最终三维网格前，不能把初始变换一致或本地数值质量通过表述为与 GarmentCode/Design2GarmentCode 最终三维效果等价。

## 源依据

所有路径对应固定上游提交：

- `pygarment/garmentcode/panel.py`：`set_pivot`、`mirror`、`autonorm`、`assembly`、`point_to_3D`。
- `pygarment/garmentcode/component.py`：组件 bbox 顶部中心 pivot、保持子组件相对位置的旋转。
- `pygarment/garmentcode/base.py`：`place_by_interface`。
- `pygarment/pattern/rotation.py`、`pygarment/meshgen/boxmeshgen.py`：实际网格旋转与 `right_wrong` 的 seam swap。
- `assets/garment_programs/tee.py`、`bodice.py`、`sleeves.py`、`collars.py`、`pants.py`、`skirt_paneled.py`、`circle_skirt.py`、`bands.py`、`skirt_levels.py`、`godet.py`、`meta_garment.py`。
