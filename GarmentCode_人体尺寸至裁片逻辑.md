# GarmentCode：人体尺寸到裁片的完整计算链

> 对照基准：GarmentCode 仓库固定 commit `d449629979028123a5c4dc9e732a2ec19b7fce31`（PyGarment 2.0.2）。本文件描述该版本公开的 2D 纸样路径；所有公式按对应源码整理，不把 TailorAss 的经验假设写成上游公式。人体默认值和 122 个设计参数的原始值、类型、取值范围见 [`GarmentCodeParameterCatalog.json`](TrailorAss/Resources/GarmentCodeParameterCatalog.json)。

## 1. 从输入到裁片的流程

```text
body.yaml（26 个基础身体量）
        ↓ BodyParameters.eval_dependencies
body 字典（7 个派生量 + 原始量）
        + design.yaml（服装组合及款式参数）
        ↓ MetaGarment 选程序、按 rise 组装组件
tee / bodice / sleeve / collar / waistband / skirt / pants / godet...
        ↓ Panel：有向闭合边界、曲线、dart/cut、命名 Interface
        ↓ StitchingRule：接口方向、分段/比例匹配、ruffle 系数
2D pattern：裁片、边、裁片标签和 stitch 引用
```

纯 2D 的核心调用是按身体和设计参数建立 `MetaGarment`、运行 `assembly()`，再用 `serialize(with_3d=False, with_printable=True)` 序列化。`placement`/3D 悬垂物理不是裁片尺寸来源；但组件在组装时会使用接口定位和方向，使其裁片与 stitch 对应。

## 2. Body：原始量与派生量

官方 `assets/bodies/mean_all.yaml` 中 26 个输入量如下。长度/围度以 cm 计，角度以度计；不同 body 文件可能提供不同个体值，下面是字段定义，不是固定人体比例假设。

| 原始字段 | 含义 | 主要进入的纸样计算 |
| --- | --- | --- |
| `height` | 身高 | 腰位与腿长基准 |
| `head_l` | 头长 | `_waist_level`、组件定位 |
| `bust`, `back_width` | 胸围、后背宽 | 上衣前后片宽、裤/裙臀量的分配基准 |
| `waist`, `waist_back_width` | 腰围、后腰宽 | 上衣腰省/腰口、裙裤前后腰片、腰带 |
| `hips`, `hip_back_width` | 臀围、后臀宽 | 下装前后片臀量和后片分配 |
| `bust_points`, `bum_points` | 胸点距、臀点距 | 前后省道位置 |
| `bust_line`, `vert_bust_line`, `waist_line`, `waist_over_bust_line` | 胸线/垂直胸线/腰线高度/腰胸差 | 胸省、上衣长度校正 |
| `hips_line`, `crotch_hip_diff` | 臀线高度、裆臀高度差 | 裙裤 rise、裤裆 |
| `shoulder_w`, `shoulder_incl`, `neck_w`, `armscye_depth` | 肩宽、肩倾角、颈宽、袖窿深 | 上衣肩线、领口、袖窿和袖山 |
| `arm_length`, `arm_pose_angle`, `wrist` | 臂长、手臂姿态角、腕围 | 袖长、袖片姿态与最小袖口 |
| `leg_circ` | 腿围（上游字段名；裤片算法用作裤腿扩量基准） | 裤腿扩展/裤裆外展 |
| `underbust` | 下胸围 | 身体数据字段；这些基础程序未在主要片型公式中普遍直接使用 |
| `hip_inclination` | 臀部倾角 | 裙裤侧缝线形 |

其余字段也必须保留在 body 配置中；某个款式不使用某字段，不表示它是无效输入。不要用 TailorAss 自行推导的数替代用户实测值。

`BodyParameters.eval_dependencies` 的派生值：

| 派生量 | 上游计算 | 用途 |
| --- | --- | --- |
| `_waist_level` | `height - head_l - waist_line` | 腰线在身体坐标中的高度 |
| `_leg_length` | `_waist_level - hips_line` | 从臀线以下量化的腿长；是长度，不是比例 |
| `_base_sleeve_balance` | `shoulder_w - 2` | 袖窿/袖山的平衡宽 |
| `_bust_line` | 有 `vert_bust_line` 时：`(2/3) × vert_bust_line + (1/3) × bust_line`；否则 `bust_line` | 上衣胸线及省道深度 |
| `_hip_inclination` | `hip_inclination / 2` | 裙裤侧面倾斜角 |
| `_shoulder_incl` | `shoulder_incl` | 肩线与袖山角度 |
| `_armscye_depth` | `armscye_depth + 2.5` | 袖窿开口/袖子连接尺寸 |

这些依赖只在相关 key 改变时更新。实现时应保证身高/头长/腰线/臀线任一依赖改变后，腰位和腿长一起重算；肩宽变化应重算 sleeve balance，不能只更新直接测量值。

## 3. Design：122 个参数的分组和尺度

官方 `default.yaml` 的设计参数树总计 122 个叶参数。原始路径、`v` 默认值、`range`、`type` 和 `default_prob` 已逐项保存在随 App 收录的 JSON 映射目录里；它是审查参数是否遗漏的机器可读清单。主要组为：

| 组 | 参数数 | 控制内容 |
| --- | ---: | --- |
| `meta` | 3 | 选上衣、腰带/腰头、下装；各自允许 `null` |
| `waistband` | 2 | 腰围比例、腰带宽度比例 |
| `shirt` | 4 | 抹胸开关、衣长比例、上衣宽度/下摆比例 |
| `collar` | 18 | 前/后领型、宽度、深度、角度、Bezier 控制和翻曲线、领部组件 |
| `sleeve` | 17 | 无袖、袖窿类型、袖长/宽、角度、ruffle、耸肩、袖口类型及尺寸 |
| `left` | 32 | 不对称开关及左侧独立上衣、领口、袖子参数 |
| `skirt` | 5 | 两片裙长度、rise、抽褶、下摆开衩、flare |
| `flare-skirt` | 10 | 圆裙长度/rise/展开量、多片数/曲率、前后长差、开衩 |
| `godet-skirt` | 5 | 基础裙款、插片宽/深/数量、开口间距 |
| `pencil-skirt` | 9 | 铅笔裙长度/rise/下摆量/角度、前后左右开衩、侧切图案 |
| `levels-skirt` | 7 | 基裙/层型、层数、抽褶、总长、rise、基裙长度占比 |
| `pants` | 10 | 裤长、宽度、裤脚扩量、rise、裤口组件/抽褶 |

很多 design 数值是无单位比例/角度/类别值；比如 `shirt.length` 乘 `waist_line`，`skirt.length` 乘 `_leg_length`，`pants.length` 也乘 `_leg_length`，不能一律标成 cm。每个参数具体 range 与条件路径以目录为准。

### 3.1 上衣：宽松 tee 与合体 bodice

**宽松 Shirt/tee 半片**（前后片各自计算，随后左右镜像）：

令 `m = shirt.width × bust`，`b = shirt.flare × m`。

- 前片占身宽比例 `f = (bust - back_width) / (2 × bust)`；前片宽 `Wf = f × m`，下摆宽 `Bf = f × b`。
- 后片比例 `r = (back_width / 2) / bust`；后片宽 `Wb = r × m`，下摆宽 `Bb = r × b`。
- 肩倾量 `S = tan(shoulder_incl) × W`。
- 基础衣长 `L = shirt.length × waist_line`。前片还要减前后平衡修正：`fb_diff = (f - (0.5 - f)) × bust`，`L_front = L - tan(shoulder_incl) × fb_diff`。后片不减这个差值。
- 片的基本锚点是 `[0,0] → [-B,0] → [-W,L] → [0,L+S]`。底边的 `ruffle` 目标把前/后下摆接口长度分别映射到 `(waist-waist_back_width)/2` 与 `waist_back_width/2`。

**合体 FittedShirt/bodice 半片**：前后片分别使用胸围/后背宽与腰围/后腰宽分配；另增加肩倾修正和省道，而不是仅把宽松 tee 收窄。

- 前片半宽 `front_frac × bust`，其中 `front_frac=(bust-back_width)/(2×bust)`；后片宽 `back_width/2`。
- 前片半腰宽 `(waist-waist_back_width)/2`；后片半腰宽 `waist_back_width/2`。
- `shoulder_incl = tan(shoulder_incl°) × panel_width`。前片上身长度根据 `waist_over_bust_line` 和肩宽位置做修正；侧边长度还根据 `waist_line` 与 `fb_diff` 修正。
- 前片侧省：省尖高度由胸线及 `0.75 × (前片宽 - bust_points/2)` 定位；省宽由直身高与侧缝目标长度差得到。
- 前片腰省宽约为 `(前片宽 - 前片腰宽) × 2/3`，省深按 `0.9 × (waist_line - _bust_line)` 计算，位置由半胸点距定位。
- 后片先以 `back_width/2` 与 `waist_back_width/2` 建形，再按腰臀差在后腰加入双省；臀省位置由 `bum_points` 确定，间距由源码比例确定。小腰臀差下不一定加省。
- `add_dart` 会把省形状插入闭合边界，并把省两腿作为内部 stitch；省不是额外摆在裁片外面的三角形。

左右对称时右侧作为模板、左侧镜像。开启 `left.enable_asym` 后左侧读取 `left.*` 参数；源码为避免不匹配会禁用复合领，并强制左右衣长及前后领深兼容。成衣长度和纸样平衡要对照这个兼容步骤。

### 3.2 领口和领部组件

`collar.f_collar` / `b_collar` 分别生成前/后半领口边界。7 种基础曲线为 Circle、Curvy、V、Square、Trapezoid、CircleArc、Bezier2。类型决定线段/圆弧/Bezier 的控制方式；深度、宽度、角度、翻转、Bezier x/y 进入对应生成器。前后领可不同。

`BodiceHalf.eval_dep_params` 会在裁片生成前重解释部分值：

- 领口宽度参数 `v ≥ 0` 在线性区间 `neck_w…(_base_sleeve_balance - 2)` 插值；`v < 0` 在线性区间 `0…neck_w` 映射。
- 前后领深分别先用 `fc_depth/bc_depth × _bust_line`，并按肩倾补偿；最大深度限制在领角剩余长度减肩倾修正和 1 cm。
- `component.style` 可为无组件、Turtle、SimpleLapel、Hood2Panels。额外片各自生成裁片，再把 neck projection 接口与衣身领口接口配对；hood 深度/长度按头长或领宽缩放。
- `strapless` 只对 fitted bodice 生效：调整前后上边裁切深度，并补偿前后侧缝长度差。

### 3.3 袖窿、袖片、袖口

袖片不是独立矩形。`bodice` 先给袖子 `get_width(level)` 查询对应袖窿高度的前/后身宽，然后 sleeve 根据肩线角、连接宽和 armhole shape 生成前/后袖窿投影；再用 `cut_corner` 把匹配区域从衣身肩角取出，生成同一组待缝接口。

- 有袖时程序强制使用 `ArmholeCurve`；无袖时才允许 Square/Angle/Curve 袖窿类型。
- 袖子连接宽根据 `_armscye_depth` 和 `connecting_width` 比例换算，并限制于肩角允许的最大范围。
- 袖山开口通过前后投影曲线构造；前后宽不同会用 `even_armhole_openings` 细分/协调开口边段。
- 袖片有效长度 `sleeve.length × (arm_length - opening_length)`，最短 5 cm；`sleeve_angle` 不小于身体 `shoulder_incl`。
- 袖口宽 `max(end_width × 袖口投影高度, wrist/2)`，保证腕围空间；袖口 ruffle 调整连接长度。
- 耸肩开关和长度只在用户 sleeve angle 比人体肩倾角至少高指定 margin 时生效，否则忽略耸肩造型。
- CuffBand/CuffSkirt/CuffBandSkirt 的围度由袖口接口总长和 top_ruffle 推导，再确保至少等于腕围；袖口长度 `cuff_len × arm_length`。组合型袖口按 `skirt_fraction` 分配到直筒袖口和喇叭段。

### 3.4 腰带/腰头

`waistband.waist` 是围度比例（允许 hips 到 waist 的 1…2倍），`waistband.width` 不是 cm，而是乘 `hips_line` 得到竖直宽度。下装的 rise 传给腰头；上装单独配腰头时 rise 为 1。

设 `r=rise`、`w=waistband.width×hips_line`。腰带顶部取身体 rise `r+w/hips_line` 对应围度：`linearInterpolation(hips,waist,r+w/hips_line)`；前/后分配比例也在 hipBackFraction 与 waistBackFraction 间插值。若 `r + w/hips_line > 1`，上游将 rise 截到 `1 - w/hips_line`。

- StraightWB：前后各一片直条，按前腰/后腰各自宽度切分；边界接口设置长度匹配比例。
- FittedWB：前后各一片圆弧四边形；底边使用 rise 对应的围度，顶边使用 rise+腰带宽对应的围度，使腰头随身体由臀到腰收进。
- 两片腰头左右侧接口缝合；组合时上口接上衣下口（若有），下口接下装上口（若有）。

### 3.5 裙装

所有 rise 使用共同换算。`BaseBottoms.eval_rise(r)`：

- `waist_r = lerp(hips, waist, r)`
- `hipDepth_r = r × hips_line`
- `backWaist_r = lerp(hip_back_width, waist_back_width, r)`

**Skirt2 两片裙**：前片腰宽 `waist_r - backWaist_r`，后片腰宽 `backWaist_r`；长度 `max(hipDepth_r + skirt.length×_leg_length, 5)`。片上宽度再乘 ruffle，底宽加两侧 flare；`bottom_cut` 依比例在下摆开衩。前后片侧接口缝合，顶边分别向身体前腰/后腰设置 ruffle 匹配。

**SkirtCircle 圆裙**：总展开份额 `suns`，前/后各用 `suns/2`。单片顶弧长 `waist_r/2`，圆心角 `π×suns`，所以半径 `R=(waist_r/2)/(π×suns)`；外半径 `R+L`。端点由弦长 `2R sin(angle/2)` 与垂直高 `L cos(angle/2)` 求出；上/下边为圆弧、两侧为直边。长度 `L=max(hipDepth_r+flare-skirt.length×_leg_length,5)`。前后片侧缝相接，顶弧分别匹配前腰与后腰。

**AsymmSkirtCircle**：完整圆裙的前后不对称裁片。腰半径 `R=waist_r/(2π)`；前长 `Lf=asymm.front_length×L`，源码依据几何关系计算共享侧长，使前后片不对称而侧缝仍可配对。不是简单只加长一片的径向边。`cut.add` 在选定前/后片的下摆按比例位置插入开衩形状。

**SkirtManyPanels**：总腰围均分 `panel_w=waist_r/N`；下摆/腰口宽比系数 `1 + suns×L×2π/waist_r`；每片下摆弧度由 `panel_curve` 控制。单片按规则沿圆周复制 N 份，相邻片左右侧接口缝合，首尾闭合。

**PencilSkirt**：前后各一片曲面轮廓，以 `waist_r/backWaist_r` 和 rise 后臀围分配前后片腰臀宽。总长按 `_leg_length` 缩放，后片 hipline 扩展系数 1.05。侧臀倾斜来自 `_hip_inclination`；腰臀差拆成侧缝位移与 dart（`w_diff=hipsHalf-waistHalf`，`hw_shift=min(tan(hipInclination)×hipDepth,w_diff)`，剩余差量由省收掉）。前后省位置分别按 `bust_points/2` 与 `bum_points/2`；前后省深比例不同，后片可双省。四个 slit 参数分别在对应下摆/侧边切开；可选侧切形状依据 hips 与胸点距离缩放。

**SkirtLevels**：`total = levels.length×_leg_length`；基裙长 `total×base_length_frac + hips_line×rise`；剩余总长均分到 `num_levels`。每一层的腰围取上一层下摆接口总长乘 `level_ruffle`，前后腰围分别由前/后下摆长度派生；逐层 stitch 上一层 bottom→下一层 top。`base` 和 `level` 都能在圆裙/两片裙/铅笔裙等允许集合中选择，基裙开衩被关掉。

**GodetSkirt**：先按 `godet-skirt.base` 生成 Skirt2 或 PencilSkirt，强制关基础裙开衩。沿基础裙下摆接口分布插片：下摆长度扣除 cuts_distance 后均分插口；插片两条斜边长度 `sqrt((insert_w/2)^2 + insert_depth^2)`，由此反算裙摆 V 形切口深度。源裙边被实际替换成切口边，插片两条边与切口两侧形成 stitch。插片数量均分到基裙下摆边段；可放不下时缩窄 cut 或调整间距。

### 3.6 裤装

`PantsHalf` 前/后片先按 rise 得到 waist/hip depth/back waist。腿根基础外展 `min_ext=leg_circ - hips/2 + 5`，乘 `pants.width`；前档外展 `front_ext=(hips-hip_back_width)/4`，后档外展为总外展减前档外展。裤长扣除 cuff 长后乘 `_leg_length`。

`PantPanel` 的裤脚扩量 `flare=leg_circ×(pants.flare-1)/4`。臀腰差 `w_diff=hipHalf-waistHalf` 在侧臀倾斜量 `hw_shift=min(tan(_hip_inclination)×hipDepth,w_diff)` 与腰省间分配；前片腰宽 `(waist-riseBack)/2`，后片为 `riseBack/2`，后片臀围量用 `hip_back_width/2` 且臀线外扩 1.1。裤裆上点在臀线以上 `0.45×hipDepth`，裤裆弧由 tangent constrained curve 构造，底点位置受 `crotch_hip_diff` 与前/后档外展控制。前后片省的位置分别来自胸点距/臀点距；前后片左右镜像。外缝、内缝、前后裆片接口成对 stitch；如选裤口组件，以裤口周长和 top_ruffle 生成 cuff，并 stitch 到裤脚。

## 4. Edge、Interface、Stitch：生成后还要配边

- 一个 `Panel` 是有序、闭合的边序列。边可为直线、圆弧、二次/三次曲线；一条边的 endpoint、curve 控制值与方向一起确定实际弧长和形状。
- `Interface` 是组件公开的拼接口，可以包含多条有序边、方向翻转、每段 ruffle 系数。比如上衣的 `bottom`、裤装 `top`、袖山 `in`、领口 `front_proj`，不是通过裁片名字猜边。
- `ruffle` 把实际边长映射到目标连接长度；系数不是泛用松量厘米。两侧总长度不同不自动表示任意抽褶都正确，要核对预期的接口系数和分段。
- `StitchingRule` 按两侧接口序列顺序配对。如果两侧边数或相对分段比例不同，PyGarment 会在较长/分段不同的接口上细分边，使匹配边界比例一致；verbose 检查两侧 projected length 的差，默认约 3 mm 容差提示。
- 一件衣服还会把多个子组件合成上层接口：例如左右衣身中缝、前后衣身肩缝和侧缝；袖窿会先切出接合片段，袖片按前/后两段与其 stitch；裁片/省道内部接缝同样进入最终 pattern。
- 只有已登记的接口/拼缝才会进入 stitch 列表。一个“所有 stitch 长度校验通过”的 JSON，不能证明遗漏的接口已经存在。

## 5. TailorAss 对照时的建议检查顺序

按一个具体设计配置，逐层比对中间结果，不要一开始只比最终图：

1. 对齐 body 原始 26 个字段和单位；检查 7 个派生量及更新依赖。
2. 对齐 design 树的 `v`、类型和 range；确认比例参数乘了正确的身体量。
3. 检查各 piece 的关键锚点和实际曲线长度（胸/腰/臀、袖窿/袖山、前后腰口、裤裆）。
4. 检查每个组件公开的 Interface 边序、方向、总长和 ruffle；再检查对接的 StitchingRule 和细分后的 stitch 对。
5. 最后比序列化的 panel、vertices、edges curvature、stitches，并确认长度单位/坐标变换一致。

尤其留意这些常见的“表面出图、尺寸却错了”情形：把 ratio 误当 cm；腿长 `_leg_length` 当成身高比例；对称性左右镜像错误；前后片共用同一个腰/胸宽；曲线只比弦长；缝线边存在但 stitch 关系未生成；为了通过容差而放宽长度校验，却没有 ruffle/gather 规则作为依据。

## 6. 上游源码索引

所有链接固定到本文件开头的 commit，便于复查：

- [body 参数依赖](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/bodies/body_params.py)
- [官方默认设计参数树](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/design_params/default.yaml)；[身体默认值](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/bodies/mean_all.yaml)
- [meta 组合与组件拼接](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/meta_garment.py)；[基底 rise 和长度](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/base_classes.py)
- [宽松 tee](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/tee.py)；[合体 bodice/衬衫](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/bodice.py)
- [袖片和袖窿](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/sleeves.py)；[领型/领片](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/collars.py)；[腰带/袖口](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/bands.py)
- [圆裙/不对称圆裙](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/circle_skirt.py)；[两片/多片/铅笔裙](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/skirt_paneled.py)；[Godet 插片](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/godet.py)；[层叠裙](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/skirt_levels.py)
- [裤片和裤口组件](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/garment_programs/pants.py)；[接口与拼缝定义](https://github.com/maria-korosteleva/GarmentCode/tree/d449629979028123a5c4dc9e732a2ec19b7fce31/pygarment/garmentcode)

> 使用上游代码与公式作为对照时应保留 GarmentCode 的 MIT 许可证和版权声明。几何公式正确与否不等于成衣 fit 已经通过实物验证；服装仍需要多尺码纸样、缝长和平衡检查及试样核版。
