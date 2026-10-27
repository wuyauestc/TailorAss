# 26项人体输入与7项派生值：实际3D映射审查

本记录来自2026-10-27对当前生产源码和既有冻结数据的只读审查。没有重新运行布料Newton、人体优化、整衣或联网。本记录区分参数来源绑定、实际几何响应、项目表面量法和成衣合身；四者不能相互替代。后续App入口接通情况单独见 [JOINT-DRAPE-VIEW.md](JOINT-DRAPE-VIEW.md)。

## 三种实际人体路径

1. scaledTemplate + legacyTemplate：StandardBody以腰原点坐标执行五尺度变形；仍可使用旧逆映射SDF。可见人体与BodyMesh的顶点、面编号必须相同。
2. scaledTemplate + matchPatternReference：同一五尺度形状，再按原CC0完整蒙皮权重摆臂。输入角仅匹配肩到肘骨代理的XY投影约定，不是独立人体尺寸拟合；不携带旧SDF。
3. surfaceMeasurements + matchPatternReference：BodySurfaceFitter求四控制量，Replay同场变形可见点和1117辅助源点，FittedBody重放并重测六个rest目标，再摆臂，完成rest和最终表面的完整静态检查、BodyMesh和Q，才签发私有表面凭证。全部33值绑定同一纸样；这不表示33个量均驱动了几何。

JointInput只保留全源绑定、零固定点、真实参考面积质量与缝合计划，不执行人体尺寸拟合。SewnInput会核对可见mesh和碰撞mesh逐值相同；新拟合凭证另核同一纸样的全部33参数。此处没有发现“显示一个人、碰撞另一个人”的来源错配。

## 原始26项的逐项映射

表内“拟合”仅指四种项目表面目标在canonical rest姿势的实际优化，不指人体扫描或全部解剖参数。五尺度路径已存在default、female及26项各正负扰动的54份真实StandardBody检查；新增四目标路径的实际尺寸成功覆盖default/female两组，尚无全部26项扰动后的新拟合矩阵。

| 原始输入 | legacy/scaledTemplate的实际人体作用 | surfaceMeasurements新增作用与缺口 |
| --- | --- | --- |
| height 身高 | 进入腰高、上下身尺度；总可见竖直范围匹配身高。其他值不变时主要把新增高度分配到下半身 | 保留基础变形；不是新增目标 |
| head_l 头顶至颈根高度 | 经腰高改变整个上/下身比例，没有独立头颈局部控制 | 仍未独立测量/拟合头颈高度 |
| neck_w 颈根宽 | 不改变实际人体 | 没有颈根表面目标；只改变纸样领口/衣身 |
| shoulder_w 肩宽 | 不改变实际人体 | 直接优化左右肩表面点的横向X间距；不是背部弧长。最终摆臂后不重设该目标 |
| shoulder_incl 肩斜角 | 不改变实际人体肩斜；其派生值改变纸样 | 尚无颈根至肩点表面坡度目标 |
| bust 胸围 | 不改变实际标准人体；兼容proxy的围度数据不等于实际皮肤变形 | 优化固定源表面胸参考路径的长度；不是自动搜索最丰满平面，也不拟合胸高/前后分配 |
| underbust 下胸围 | 不改变人体 | 当前固定上游与Swift制版亦没有consumer；保存/展示/参数SHA绑定，不应称已用于制版或拟合 |
| back_width 后胸围弧长 | 不改变实际人体 | 胸总长度目标没有约束前后弧分配；纸样前后片却使用该参数 |
| bust_points 胸点间距 | 不改变实际人体 | 没有左右胸峰点的位置目标；纸样省道使用它 |
| bust_line 贴体胸高 | 不改变实际人体 | 仅进入制版派生胸高；没有颈根到胸点贴体路径目标 |
| vert_bust_line 垂直胸高 | 不改变实际人体 | 通用参考测量可据它改变查询平面，但这不是变形；四目标拟合不据它移动胸参考路径 |
| waist 腰围 | 改变腰以上整体x/z尺度，连带胸、肩、颈、臂；不是局部自然腰拟合 | 沿用该基础场；六目标里没有腰围约束，局部拟合可有小连带变化 |
| waist_back_width 后腰围弧长 | 不改变实际人体 | 未测量或拟合前后腰弧分配；纸样前后腰线使用它 |
| waist_line 颈根至腰线垂直高度 | 与head_l共同进入腰高和整个上/下身尺度 | 仍无独立颈根到腰线地标目标 |
| waist_over_bust_line 经胸前腰节长 | 不改变实际人体 | 没有经胸前腰节表面路径目标；贴体上衣前身使用它 |
| hips 臀围 | 改变臀以下整体x/z尺度，连带腿和脚 | 沿用基础场；没有新臀形或前后弧目标 |
| hip_back_width 后臀围弧长 | 不改变实际人体 | 未拟合臀前后分配；下装和省道使用它 |
| hips_line 腰臀高 | 缩放声明腰臀带，并重分配其下长度；不是自动寻找实际臀峰平面 | 沿用基础场，没有新增表面地标拟合 |
| hip_inclination 侧臀倾角 | 不改变实际人体 | 仅派生制版倾角，没有臀部侧轮廓目标 |
| bum_points 臀峰间距 | 不改变实际人体 | 没有臀峰表面位置目标；制版省道使用它 |
| crotch_hip_diff 臀线至裆底高度 | 不改变实际人体裆底位置 | 没有裆底地标/高度目标；裤装使用它 |
| leg_circ 大腿围 | 不改变实际人体 | 没有大腿表面环目标；裤腿宽使用它 |
| arm_length 臂长 | 不改变实际人体臂长 | 优化固定肩→外肘→腕连续原三角带路径；左右分别测量，同一控制量。不等于骨长或袖片中心线 |
| armscye_depth 袖窿深 | 不改变实际人体腋下高度 | 没有肩/腋下表面深度目标；原值+2.5cm是制版余量，不应拿派生值拟合人体 |
| wrist 腕围 | 不改变实际人体 | 优化左右固定原表面腕环；不是任意腕平面最大环 |
| arm_pose_angle 手臂参考角 | legacy不使用；显式matchPatternReference才改变姿态 | 同场辅助点重算关节后摆臂；匹配骨代理XY投影约定，不单独保证皮肤路径或袖轴一致 |

因此，legacy实际只有6个raw入口驱动五尺度：height、head_l、waist_line、waist、hips、hips_line。head_l和waist_line在形变中只能通过它们的和区分：它们以同方向改变腰高，不能独立表达头颈长和躯干长。surfaceMeasurements再增加bust、shoulder_w、arm_length、wrist，matchPatternReference再增加姿态角，共11项有几何入口；这11项中也只有四种新项目量法是独立优化目标。其余15项没有独立几何通道。

## 七个派生值

| 派生值 | 实际公式 | 对人体的真实作用 |
| --- | --- | --- |
| _waist_level | height - head_l - waist_line | 五尺度直接使用；决定相对腰原点的上下身分配 |
| _leg_length | _waist_level - hips_line | 没有独立读取作人体目标；相同数值组合已内含于下半身尺度。纸样裙/裤长度使用它 |
| _base_sleeve_balance | shoulder_w - 2 | 制版/袖平衡；不是另一个人体表面量 |
| _bust_line | 2/3 vert_bust_line + 1/3 bust_line | 制版混合胸高；没有驱动实际胸点高度 |
| _hip_inclination | hip_inclination / 2 | 制版倾角；不改变人体侧臀形状 |
| _shoulder_incl | shoulder_incl | 制版肩斜；没有独立表面坡度拟合 |
| _armscye_depth | armscye_depth + 2.5 | 制版袖窿余量；不是人体测量目标 |

Fitted路径逐位重算并验证这7项依赖，篡改会拒绝。验证依赖与参数SHA只证明来源一致，不证明这些派生量都已转成人体尺寸。

## 已有实际数据与本次独立复算

原五尺度人体的固定表面量法已有独立原面附着验证：

| profile | 量 | 实际/cm | 输入/cm | 相对差 |
| --- | --- | ---: | ---: | ---: |
| default | 肩横宽 | 42.16327 | 36.4568 | +15.65% |
| default | 臂表面路径 | 61.93969 | 53.9697 | +14.77% |
| female | 肩横宽 | 40.16864 | 34.7129 | +15.72% |
| female | 臂表面路径 | 59.6639 | 51.5940 | +15.64% |

四目标拟合的两份rest最大误差为2.342e-9m/5.133e-9m，当前工厂容差是1e-5m。当前FittedBody、Fitter、Replay源码SHA均与各自最终sealed证据相同：93bbcc31…f4e339、932956d9…17bf1c、6ccb6d4b…11eaa。

工厂六目标门槛发生在摆臂前；摆臂后验证的是完整静态几何、来源与Q，不是再次满足六尺寸。用相同固定原附着、完整可见源映射和math.fsum，对已经seal的最终mesh重测：

| 最终matchPatternReference人体 | 胸路径误差/mm | 肩横宽误差/mm | 左臂路径误差/mm | 腕路径误差/mm |
| --- | ---: | ---: | ---: | ---: |
| default，45.483° | +0.12667 | -0.92825 | -0.39547 | 约0 |
| female，45.487° | +0.17645 | -1.29237 | -0.54666 | 约0 |

这不是凭证来源错误：绑定字段明确叫maximumRestGoalResidualMeters。但App不能把它描述为“摆臂后的全部尺寸仍达10微米”。最终可见竖直范围仍为输入的171.99/166.194cm。

另用既有独立截面方法，从最终Float64三角面按原边截线，Fraction绕数选择唯一严格包含声明躯干轴的环（不选最大环、不加总、不以凸包冒充胸围）：

| 最终人体 | 腰参考误差/mm | 臀参考误差/mm | y=(waist_line-vert_bust_line)/100处躯干参考周长/cm |
| --- | ---: | ---: | ---: |
| default | -0.25712 | +0.62457 | 102.05881；输入bust为99.8407 |
| female | -0.04496 | +0.48094 | 99.26553；输入bust为97.4076 |

上述胸参考平面与四目标的固定胸表面路径是两种不同量法；它不证明最丰满胸围，也不能互相替换来选一个更接近输入的结果。它具体说明胸高/胸背分配未被四目标覆盖，腰臀也没有成为新增拟合目标。

本次复算只在内存中进行，没有改写冻结数据。实际输入是FittedBodyFactorySealed-w4jwrf88/verification/default-prepared.json与female-prepared.json，SHA分别为4cbb8718…f473、b1077c4e…8650，均与原delivery-manifest相符；量法资源SHA为6658a5ed…ce610。

## 与0.93…1.07材料域的关系

尺寸不一致可能使某个款式难以穿入，也可能仅让接缝滑到错误解剖位置后仍数值合格。不能把“人体肩/臂比输入多15%”直接当作任意衣服必然不可行：真实裁片有袖山、领口、放松量、吃势、不同材料路径和自由滑移。

可核验的条件是：对实际参考网格上的某条材料路径，若rest长度为L0，所有三角形主伸长都必须小于1.07，则路径实际长度小于1.07L0。只有在实际来源绑定和款式约束确实要求该路径到达一组位置、其必要距离已大于这个上界时，才能判不可能。闭环围度还必须依据真实围住人体的几何下界，不能直接把凹凸皮肤周长当最短衣服周长。

旧401使用的实际body SHA为859d0165…acb18，正是已四目标拟合并摆臂后的default表面，不是上表偏大的legacy形状。不得用legacy偏差解释该失败，也不得把布料求解失败反过来当作人体参数不匹配的证据。

## 下一最小完整切片

1. 本轮起始代码的cube只打开旧GarmentCodeDrapeView，JointDrapeView无实例调用且未传shape。随后已接通通用Workflow、显式四目标人体选择并保留旧预览；没有修改人体或力学算法。入口、两SDK编译与实际生命周期的当前范围见[JOINT-DRAPE-VIEW.md](JOINT-DRAPE-VIEW.md)。
2. 明确四目标是rest项目量法，并展示最终姿态的独立量差；若产品要求“纸样参考姿态的四目标匹配”，应在请求姿态上测量优化再验证，而不是沿用rest的10µm结论。此项只需人体准备专项，不需整衣Newton。
3. 对正常上装，后续最小新增人体切片建议是胸背分配与肩/腋下框架：原表面颈根、胸参考高、肩点、腋点；目标明确覆盖back_width、vert_bust_line、neck_w、shoulder_incl和原始armscye_depth，并保留现有四目标及腰臀/身高的回归测量。先限定普通衣身/袖，不扩称裤装或全26项。尤其不要把制版+2.5cm余量拟合到人体上。
4. 先对修正后的完整连续吃势约束和实际纸样做上面的路径可行性检查，再判断材料域或求解策略；不继续在已知旧coarse-ease目标上叠加算法试验。

证据入口：[BODY-RIG-POSE.md](BODY-RIG-POSE.md)、[BODY-SURFACE-MEASUREMENTS.md](BODY-SURFACE-MEASUREMENTS.md)、[BODY-SURFACE-FITTER.md](BODY-SURFACE-FITTER.md)、[FITTED-BODY.md](FITTED-BODY.md)、[FITTED-BODY-INTEGRATION-DESIGN.md](FITTED-BODY-INTEGRATION-DESIGN.md)。两体完整静态验证、SDK链接和四组装配绑定各自只证明其声明范围，不是人体拟合域或整衣合身保证。
