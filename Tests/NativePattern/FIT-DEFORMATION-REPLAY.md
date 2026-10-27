# 可选拟合场与辅助骨点重放

`GarmentCodeFitDeformationReplay`是数据重放模块，不是人体显示／碰撞凭证，也不修改默认人体、旧Rig、旧FixedSurfaceReceipt、S/R/N或裁片参数。输入必须逐位符合相同33参数的原五尺度模板；输出始终不兼容旧逆SDF，不发body capability。

```swift
let prepared = try GarmentCodeFitDeformationReplay.Prepared(
    templateData: template, rigData: rig, contractData: measurementContract,
    auxiliaryWeightsData: auxiliaryWeights)
let context = try prepared.context(sourcePositions: original.positions,
    triangleIndices: original.triangleIndices, bodyValues: body.values)
let shape = try context.deform(controls: controls)
let pose = try context.pose(shape, pose: .arms(alphaDegrees: alpha))
```

`Context`是同一源实例的不可变工作数据；`ShapeData`私有构造、只编码，不可从JSON解码为来源凭证。`Attempt`和测量JSON仍只是诊断，后续人体工厂必须从源、参数和controls重新重放，不能相信可解码的状态或`isValidated`布尔。

四场及顺序与原拟合器完全相同：胸部X/Z径向缩放和肩横移；左臂、右臂；左腕、右腕。窗口和权重由原参考点定义，阶段中心／腕轴只取**当前可见表面附件**。1117个辅助源点与13380个可见点使用同一阶段参数和中心，不对骨锚均值再施非线性变形。先逐源点变形，再按原326组引用取均值，产生拟合参考姿态下的骨代理。

原CC0 `default_weights.mhw`覆盖全部1117点，其中135点与可见表面重合、982点不可见。新资源保留所有1668辅助权重对；135行直接保留原Rig的normalizedValues位模式，982行明确使用按boneIndex升序逐项求和归一化，记录原raw与pair offset。不会以近邻皮肤点猜权重，不裁成四个influence。资源SHA、模板／Rig／原权重／量法契约及全部参数、controls和实际几何均保留。生成器只读固定本地CC0资产，拒绝覆盖已有输出：

```sh
python3 Tests/NativePattern/PrepareBodyFitAuxiliaryWeights.py \
  --source-dir /path/to/pinned/cc0/assets \
  --rig TrailorAss/Resources/GarmentCodeStandardBodyRig/rig.json \
  --template TrailorAss/Resources/GarmentCodeStandardBody.json \
  --output /private/tmp/new-auxiliary-data
```

摆臂使用**拟合后参考骨代理**确定肩枢轴，再保留原所有可见／辅助蒙皮权重。角度仍是XY投影相对水平向下，非三维下Y轴夹角。`posedBoneJointAnchors`是原骨架所属骨的frame变换结果；它不冒充LBS后辅助点均值或解剖量体点。任意诊断角可与输入`arm_pose_angle`不同，此时`matchesInputArmPoseAngle=false`；未来`matchPatternReference`凭证必须另外要求相等。

所有cancel callback之后及发布前检查nearest rounding。Mac使用Darwin；iOS使用已验证NativeClothCollision的只读C FPU桥。没有桥的iOS独立目标明确拒绝，不退回不受支持的浮点环境。

专项：

```sh
python3 Tests/NativePattern/run-fit-deformation-replay.py --output /private/tmp/new-replay-check
```

默认使用小型固定参数／controls／完整几何SHA golden，不依赖临时拟合目录。可用`--fit-fixtures /path/to/real/optimizer/verification`额外逐位比较完整实际可见输出。当前实际默认／女性两组的13380可见点与原优化器逐位一致；135重合点在形变及30/45/60度姿态都逐位一致。测试保留原6个项目量法目标和20项来源、旧Rig／回执拒绝、取消、浮点环境等负控。

原有`ClothContact.inspect`排除共享顶点面，粗检查通过不等于完整曲面无交叉。后续新`FittedBody`工厂仍须完整几何验证和同SHA精确查询，才能交给初始化、body势、CCD及最终检查。它必须让`standardBody=nil`，不能将拟合顶点塞回`StandardBody.Snapshot`或旧FixedSurfaceReceipt；旧XPBD不得回退代理圆台／逆SDF。此模块没有衣服仿真、个体合身或全部26项独立拟合通过结论。
