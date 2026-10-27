# Optional fixed-body rig and arm pose

`GarmentCodeBodyRig.swift` is an opt-in native preparation module. It does not replace `StandardBody`, its resources, the inverse SDF, or the App's default assembly route. Its only pose control currently maps the two shoulder-to-elbow **bone proxies' XY projections** to an angle below the horizontal. This uses the same alpha convention as the pinned GarmentCode sleeve coordinate basis: left `(+cos(alpha), -sin(alpha), 0)`, right `(-cos(alpha), -sin(alpha), 0)`. It does not turn the sleeve basis into a measured anatomical bone axis or sleeve centerline.

```swift
let rig = try GarmentCodeBodyRig.load(resourceDirectory: resources)
let result = try rig.pose(
    visiblePositions: originalBody.positions,
    triangleIndices: originalBody.triangleIndices,
    bodyValues: body.values,
    pose: .arms(alphaDegrees: 45),
    isCancelled: { token.cancelled })

if let fixedBody = result.validatedBody {
    // Bind rendering, exact BodyMeshQueries, IPC and body CCD to THIS mesh/SHA.
    // A posed mesh is incompatible with the old inverse-warp SDF.
}
```

The default pose is `.identity`. It returns the caller's visible position array directly, after checking every Double bit against the same five-scale transform as the existing body. Triangle indices stay exactly unchanged. The caller cannot accidentally pair a different body shape with this rig by passing only a claimed geometry hash.

The loader validates template/rig/provenance SHA bindings, CC0 source commit and assets, full source-to-visible remap, the bone DAG, unique head/tail ownership, auxiliary point references and all original skin weights. The fixed resource contains 13,380 visible vertices, 26,756 triangles, 163 bones, 326 joint proxies and 40,156 visible weight pairs. Up to nine influences are retained; no four-weight approximation is used.

The current bounded shape field is applied to every visible point and **each of the 1,117 auxiliary source points separately**, then joint proxies are recomputed as their original referenced means. This respects the nonlinear waist/hip blend; applying the field to a precomputed mean would be a different transformation. The old controls are height, waist, hips, hip-line height and derived waist level. The returned report explicitly states that independent surface fitting is unimplemented and lists all 26 raw body fields as lacking an independent surface-fit contract. In particular, moving an arm does not fit arm length, shoulder breadth, chest circumference, wrist circumference or any other body measurement.

For each side, `upperarm01` is the rotation root. The shoulder-to-elbow proxy's rest XY angle defines a global Z rotation about its shoulder head. That delta is inherited by all 24 affected bones, including the root, retaining the existing elbow bend and Z components. Other bones stay unchanged. All original normalized weights participate in linear blend skinning. The identity branch does not perform a floating weighted blend.

A candidate yields a private-initializer `ValidatedBody` only after unchanged source indices, finite/nondegenerate faces, positive reference-normal dot products and positive closed volume have been checked, and `ClothContact.inspect` completes with no nonadjacent face crossings. It uses the original inspection's exclusion of triangle pairs sharing any vertex, no sewing exclusions, a 0.1mm diagnostic proximity radius and a bounded candidate budget. This is an explicit current surface diagnostic, not a proof for all adjacent folded faces or an animated body path. A detected fold or crossing returns diagnostic positions and reasons without a body capability; cancellation and exhausted budgets throw without publishing a partial result.

Linear skinning can shrink the shoulder/armpit. An independent CC0-template oracle found that the 60-degree candidate's minimum local triangle area is about 47.3% of its rest value even though its local normals do not reverse. Passing the geometric gate does not establish natural anatomy or personal fit. Dual-quaternion blending, authored surface landmarks and a real joint surface fitter remain separate work.

Run the isolated proof with:

```sh
python3 Tests/NativePattern/run-body-rig-pose.py
```

It snapshots all models/resources before strict Swift 5 Release compilation with MainActor defaults, complete concurrency checks and warnings as errors. The tests compare default and female identity meshes bit for bit, check 30/45/60-degree bilateral proxies and full surface inspections, exact-query geometry bindings, complete weights, malformed rig rejection, resource/candidate budgets and atomic cancellation. A real 90-degree default candidate reverses 12 reference face normals and produces 102 nonadjacent face crossings; it is retained only as a rejected diagnostic, with no body capability. An independent Python oracle derives rotations from projected-frame dot/cross products instead of the production angle-difference formula, compares all 13,380 points for each of six poses and all 326 joint proxies, and demonstrates a 0.696mm error in the female counterfactual that incorrectly warps a joint mean. It never modifies the old body/SDF resources or runs cloth simulation.

Cross-SDK final-link smoke (no installation or launch):

```sh
python3 Tests/NativePattern/run-body-rig-pose-platforms.py --package-proof /path/to/frozen/native/package/proof
```

The smoke links the real optional rig, exact final-mesh query and native package for arm64 iOS17 and x86_64 iOS17 Simulator. It is a compile/link check, not a phone performance measurement.

## 当前26项输入的真实影响（2026-10-26核对）

当前默认 `legacyTemplate` 仍是有限五尺度模板变形，不是26项共同拟合。
`StandardBody.swift:28–61`实际只读取 `height / waist / hips / hips_line / _waist_level`；
`PatternDesignModels.swift:524–528`定义 `_waist_level=height-head_l-waist_line`。
因此实际改变可见人体的原始字段只有下表六项。既有54份真实Swift输出
（默认、女性、26项各正负扰动）也给出完全相同的响应集合。

| 26项原始输入 | 默认可见人体响应 | 当前裁片／构造使用 |
|---|---|---|
| height 身高 | 有；经腰线高度重分配下半身长度，单改身高不独立拉长头颈 | 派生腿长与构造高度 |
| head_l 头顶至颈根高度 | 有；经腰线高度改变整个上／下身比例，未独立拟合头颈 | 头罩、构造高度、派生腿长 |
| waist_line 颈根至腰线垂直高度 | 有；同样影响整个上身及下身，未独立拟合腰节 | 衣身长度与派生腿长 |
| waist 腰围 | 有；腰以上也整体横向缩放，胸、颈、肩和手臂被连带改变 | 腰部及上下装接口 |
| hips 臀围 | 有；臀以下腿和脚也被横向缩放 | 下装与腰臀接口 |
| hips_line 腰臀高 | 有；规定腰臀平面间距，同时重分配腿长 | 下装腰臀深、派生腿长 |
| bust 胸围 | **无独立人体响应** | 衣身宽／前后分配 |
| back_width 后胸围弧长 | 无 | 衣身前后宽分配 |
| neck_w 颈根宽 | 无 | 领口／衣身 |
| shoulder_w 肩宽 | 无 | 肩线、袖平衡和构造锚点 |
| shoulder_incl 肩斜角 | 无 | 派生 `_shoulder_incl`，肩／袖计算 |
| armscye_depth 袖窿深 | 无 | 派生 `_armscye_depth=raw+2.5cm`；这2.5cm不是测得的人体深度 |
| bust_line 贴体胸高 | 无 | 与垂直胸高合成 `_bust_line` |
| vert_bust_line 垂直胸高 | 无 | 合成 `_bust_line`，未拟合胸点 |
| bust_points 胸点间距 | 无 | 省道位置 |
| waist_back_width 后腰围弧长 | 无 | 衣身／下装前后分配 |
| waist_over_bust_line 经胸前腰节长 | 无 | 贴体前衣身长度 |
| hip_back_width 后臀围弧长 | 无 | 下装前后分配 |
| hip_inclination 侧臀倾角 | 无 | 派生 `_hip_inclination=raw/2`，下装计算 |
| bum_points 臀峰间距 | 无 | 省道位置 |
| crotch_hip_diff 臀线至裆底高度 | 无 | 裤装裆深 |
| leg_circ 大腿围 | 无 | 裤腿宽度 |
| arm_length 臂长 | 无 | 袖长 |
| wrist 腕围 | 无 | 袖口／袖口组件宽度 |
| arm_pose_angle 手臂角 | 默认无；可选 `matchPatternReference` 才改变真实人台姿态 | 不改变二维裁片轮廓；改变整组袖片／袖口的原生旋转与装配间隙 |
| underbust 下胸围 | 无 | 当前固定上游及Swift都未消费；仅保存／展示，不能称已用于裁片或人体拟合 |

证据入口：`GarmentCodePrograms.swift:107–111,364–371,1035–1037,1520–1524`、
`GarmentCodeUpperPlacement.swift:244,257`。`underbust`在固定MIT上游
`d449629979028123a5c4dc9e732a2ec19b7fce31`的完整`assets/garment_programs/*.py`
中没有consumer，仅出现在`assets/bodies/mean_all.yaml:21`；不能据此声称Swift漏译。
CC0骨锚仍是代理，不能当作已定义的肩端、胸点、臀峰或贴体量体路径。

`BodySections.slice`只返回同一实际网格的全部截面闭环、来源边／面和不确定状态。
它不会自动识别胸围／臀围最丰满平面，也不会在胸区把双臂环与躯干环相加后
称为胸围。下一轮胸／肩／臂长拟合仍需要许可明确的表面测量契约及误差报告。

## legacyTemplate 与 matchPatternReference 的区别

`legacyTemplate`是明确的旧形状／旧逆SDF兼容模式，保留已有默认网格和已有
完整源初始化字节，不声称它的真实手臂已经对齐原始`arm_pose_angle`。

默认原始角是45.483°，但旧模板经五尺度变形后的肩→肘骨轴XY投影为
**46.5913161782°向下偏离水平线**；女性原始45.487°，旧轴为47.0904935255°。
所以按照原始参数绝对摆臂，默认人体也会旋转约1.1083°／女性约1.6035°，产生
新的网格SHA。不能把默认数值偷偷重解释为identity来保持旧网格。
现Rig保留原骨轴Z分量；上述一致性是XY投影契约，不宣称三维骨轴、袖中心线、
真实肩端和臂长已完全重合。上游30–60°袖片装配间隙也明确是经验构造启发式。

可选接入的准备流程是：实际`Rig.ValidatedBody` → 独立精确查询的同一SHA →
同源fixed-surface回执 → 同一摆姿网格的刚体避让／完整裁片绑定 → body势与CCD →
最终精确网格检查。旧`StandardBody.Snapshot`不换顶点、不假扮新姿态的SDF。
摆姿输入的`standardBody`必须为空；旧XPBD／投影入口必须拒绝它，不得退回
参考圆台、旧逆SDF或把不确定查询当无穿透。新入口保持opt-in，完整成衣是否
通过仍由后续联合求解和最终validator决定。

## 可选装配入口及验证

```swift
// Keep legacyTemplate for existing default behavior. Opt in explicitly:
sourceSettings.bodyPoseSelection = .matchPatternReference
let recipe = try GarmentCodeNativeAssembly.capture(
    document: document, body: body, design: design, settings: sourceSettings,
    initialization: .rigidBodyAndClothPositiveClearance)
// Run build(recipe:) on the existing serial numerical worker, not on MainActor.
let prepared = try GarmentCodeNativeAssembly.build(recipe: recipe)
```

`GarmentCodeFixedBody.Prepared`只在真实`Rig.ValidatedBody`和独立精确查询的实际
SHA一致后产生。跨文件轻量回执不依赖`isValidated`布尔值或调用者声称的SHA：
它自己验证固定CC0 rig／模板字节，重放五尺度原表面及全部40,156权重，逐个
Double核对最终位置，另做法向和有界表面检查。即使给任意改动网格重新计算一份
正确SHA，也不能取得姿态回执。`StandardBody`资源和旧逆SDF字节均不改写。

严格Swift准备专项（复用已冻结原生库，不重新编译C++）：

```sh
python3 Tests/NativePattern/run-fixed-body-assembly.py \
  --package-proof /path/to/frozen/native/package/proof
```

已验证默认／女性两人体的完整腰头+圆裙、完整有袖Shirt，分别取30°、45°、60°
及各自原始默认45.483°／45.487°，共16组。每组保留全部源裁片、原始质量与
自由度，完成正间隙初始化、同SHA精确查询、完整body+self力场及静止路径CCD。
另有12组旧模式完整状态SHA对照原211样例中的三种旧初始化模式，逐字保持。
伪造SHA的网格、异源纸样、异源人体尺度、挂接旧SDF、遗失回执、无效姿态、
取消和旧投影入口共134项负控均拒绝。已有共享Builder专项也继续保持原源／初态／
rest／质量／人体／接缝状态及旧OBJ字节。

这些结果是完整输入与接触消费者的准备验证，未执行新姿态的布料动力学；
不等于全部款式或成衣已通过。原Rig对共享顶点面组的诊断边界、线性蒙皮腋下
收缩以及全部未完成的人体量体契约仍按前文明确保留。
