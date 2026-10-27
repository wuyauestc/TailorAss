# 私有整衣终态报告

`render-joint-report.py` 只读取已经结束的真实 `JointResult` 运行。使用 Python 3.9 或更新版本及标准库，复用 `render-cloth-report.py` 的离线 WebGL／CPU 查看器与样式，不启动求解器、不安装应用、不上传数据。

```sh
python3 Tests/NativePattern/render-joint-report.py \
  --run-root /private/tmp/实际已结束的运行目录 \
  --output /private/tmp/新的私有报告目录
```

打开输出中的 `index.html`，可直接通过 `file://` 使用；数据、样式、着色器均内嵌。旧版本开发对照应额外传 `--historical`，页面会持续显示历史版本标记。已有输出目录不会覆盖。

`--run-root` 支持完整运行目录与单个已终止 case 目录。完整目录必须有终态 `summary.json`，并且全部预期 case 均有 `case-summary.json`；支持当前 `requested2400/<case>/<case>` 和直接 `<case>` 目录结构。单个 case 也必须有合法的终止原因与完整实际保存数据。运行中的目录、缺失的 case、非有限数值或不一致的源／人体／状态身份会拒绝生成。

左侧从 `complete-paper-source.json` 的全部原 panel 和原边直接构造 SVG：直线使用 `L`、二次／三次贝塞尔使用 `Q`／`C`、圆弧保留原半径、large-arc 与 sweep 使用 `A`；支持相对和绝对控制点。没有用三角网格替代原纸样轮廓。各片独立缩放，不能比较图上的相对大小，也不能用于 1:1 打印。

右侧只切换 `initial-state.json` 与真实 `last-accepted-state.json`，使用完整原始三角面索引和人体。失败候选、未提交 Newton 位置、补洞和平滑都不参与展示。可以旋转、缩放、切换正背侧面，并显示／隐藏人体、缝合边和线框。

报告只有在 case 的 `resultAccepted == true`、`outputProduced == true`、`stopReason == stableValidated`，且全部五份真实验收产物一致时，才显示正式验收标签与原 OBJ 下载。它检查源／人体／线性化身份、原网格和末态、24 帧窗口、完整 panel，以及实际 OBJ 顶点和所有面；终态包装记录若明确拒绝该 case，同样不能显示为通过。缺失或不一致时保留清晰警告并降为诊断，绝不从诊断位置生成 R.Output 或 OBJ。产物检查是保存记录一致性检查，不是重新执行 R 验收。

最大／RMS 缝合间距重新遍历全部保存的重心坐标约束；最大边相对长度变化遍历全部源三角网格边；面积按参考三角形计算，质量来自完整实际 mass 数组。它们使用 Python Float64，仅供报告，不代替独立碰撞或成衣检查。已接受步、失败阶段、动力学时间、已接受帧的重力比例与计时来自实际终态记录；速率按该帧 `trajectoryMode` 区分物理速度和装配配置变化率。静态装配不冒充经过的物理时间。

`report-manifest.json` 记录每份实际读取输入、已有冻结清单与 Native 绑定记录（存在时）、生成器及复用查看器的 SHA-256，并给出每款状态和重算指标。全部输入在写报告前后重新核对。嵌入 JSON 转义 `<` 和 Unicode 行分隔符，原 panel 名称转义为 HTML，其余界面文本通过 `textContent` 更新；没有外部 CDN、遥测、网络请求或公共发布。

初次开发使用封存的 111 版历史失败运行：`/private/tmp/TailorAssJointFSC111PGradientFull`。圆裙只完成 689 步、衬衫只完成 404 步，两款都未通过最终成衣验收。该历史报告不能代表后续求解器效果；真实正向验收分支必须等待正式运行产出，不使用伪造成功样本填补。

## 首批通用正向结果（2026-10-27）

默认独立直条腰头与贴体弧形腰头均通过通用流程最终验收，报告分别位于`Reports/2026-10-27-generic-3d/straight-waistband/`和`fitted-waistband/`。报告完整核对OBJ中的布料、人体顶点以及人体面索引偏移；此前仅核对布料会误拒绝含人台的正常导出。`JointReport.py --case <实际终态目录>`用真实产物检查正常导出，并确认缺人体、错误人体偏移、缺面、改人体坐标四类损坏被拒绝。参数来源中的款式选择用于中文标题；预算耗尽属于可展示的失败终态，不会转成验收通过。

`render-cloth-preview.py --focus-cloth`可将相机聚焦实际布料，保留全部原几何及深度遮挡。静态图只是离线数值网格图；内置浏览器的file协议被策略拒绝，本轮没有网页交互或App界面通过记录。
