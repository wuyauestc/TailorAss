# 整衣3D实验入口

纸样预览页右上角的cube现在打开两个入口：

- **整衣3D（实验）**：进入实际GarmentCodeJointDrapeView，使用完整源裁片、JointWorkflow和最终验收。
- **裙装与腰头预览**：保留原GarmentCodeDrapeView及其原有支持范围。

这是实验功能的可达性接入，不表示全部款式已完成。通用页明确说明部分款式仍在验证；只有JointWorkflow.Result.validated才能创建预览和OBJ导出，失败状态不显示诊断网格或提供冒充验收结果的文件。3D菜单仍受原裁片轮廓检查约束。

## 人台形状与姿态

默认仍是scaledTemplate + legacyTemplate，没有改动原人体、S/R或拟合算法。

| 页面选择 | 实际形状/姿态 |
| --- | --- |
| 标准人台 + 标准模板姿态 | scaledTemplate + legacyTemplate |
| 标准人台 + 按纸样参考角摆臂 | scaledTemplate + matchPatternReference |
| 按主要尺寸拟合（实验） | surfaceMeasurements + matchPatternReference |

选择主要尺寸拟合时，页面明确切换到纸样参考摆臂，只显示这个可用姿态，不提供必然被工厂拒绝的legacy组合，也不会静默降级成scaledTemplate。调用Workflow时同时传入捕获的shape与pose。

页面说明拟合仅覆盖胸围、肩横宽、臂长和腕围的项目量法，其他尺寸仍采用模板比例，不是完整个人拟合；拟合目标属于参考姿势，摆臂后局部尺寸可能变化。没有宣称全部26项或最终摆臂仍达到10微米。完整映射审查见[BODY-PARAMETER-MAPPING-AUDIT.md](BODY-PARAMETER-MAPPING-AUDIT.md)。

形状、姿态和面料的Picker写入都通过ViewModel选择方法同步取消并作废旧发布，不依赖稍后到来的onChange再处理。姿态、形状、原纸样尺寸或面料变化都要求重新计算；旧结果、场景错误与页面拥有的导出文件失效。

## 完整来源与结果

页面用JointParameters恢复原纸样的完整body/design，拒绝缺失、非有限、派生不一致、设计范围/类型/概率元数据错误。不能用默认值替换缺少的来源。NativeAssembly随后独立重生成并核对完整源SHA。

只有最终validated结果进入场景。预览保留原接缝组ID和中文裁片名，支持旋转、缩放、人体/接缝显隐与复位。指标来自验收回执：真实源面积质量、网格边变化、接缝间隙、速度、稳定帧和实际计算时长。数值及几何通过不等于个人合体。

进度显示真实阶段、步骤和连续稳定计数，使用不确定进度指示，不估算完成百分比。

## 抽褶的准备后守门

当前完整验收没有为true gathered有限粗缝钉提供整边证明。Workflow在真实S.prepare完成来源校验后检查plan.usesFiniteCoarseTacks；为true时立即抛出：

> 这份纸样包含抽褶接缝，整衣3D的抽褶缝合仍在完善，暂时无法生成可验收结果。二维纸样可以正常使用。

守门在R.prepare、assembling进度和任何Session/Newton之前，避免用户白等2400步再得到已知不能签发的结果。它不修改S.prepare、CLI求解或核心验收门槛；完整目标仍包括抽褶。正确continuous-eased接缝不因此被归为gathered。取消继续由原detached owner等待真实后台退出，并优先传播取消。

## 生命周期与导出

取消立即禁止旧发布，但保留generationTask及owner ID，直到Workflow已等待真实detached worker结束。在此之前显示正在取消，阻止重启另一个求解。更换配置和关闭页面不能让旧进度/结果复活，旧任务完成只能释放自己的owner。

OBJ在异步MeshExport worker中创建。生成、结果和导出各有独立ID；场景错误另核结果及渲染重试ID。旧导出重试只清理其自身文件，形状/姿态变化、取消和关闭清理页面拥有的导出。

## 聚焦检查

    python3 Tests/NativePattern/check-joint-drape-view.py --package-proof /path/to/sealed-native-proof
    python3 Tests/NativePattern/run-joint-drape-lifecycle.py --package-proof /path/to/sealed-native-proof --frozen-view-check /path/to/successful-view-check
    python3 Tests/NativePattern/run-joint-workflow.py --package-proof /path/to/sealed-native-proof --gathered-only

页面检查冻结真实NativeDesign菜单、通用页、旧预览、2D/PDF分支及全部GarmentCode模型依赖，分别对arm64 iOS17和x86_64 Simulator17做严格typecheck，保留MainActor默认隔离、complete concurrency、MemberImportVisibility和warnings-as-errors。没有伪造SwiftUI目的页。SwiftUI宏只使用官方编译器的-disable-sandbox子进程选项。

生命周期检查从同一成功UI快照选择实际核心模型，抽取**逐字相同的生产ViewModel slice**，用真实Workflow验证形状/姿态切换、原尺寸来源替换、取消确认、旧owner拒绝、关闭及真实拟合准备的取消。不构造假Validated/Result，不运行成衣正向验收。

抽褶专项生成完整WB+Skirt2、ruffle=1.3真实纸样，调用实际Workflow；核对只能出现capturing/preparing、无assembling/completed、无Result返回、原纸样不变。若守门失效，测试在assembling事件同步取消并失败，不意外启动一轮布料求解。

所有检查复用完整冻结Native证明中的模块/库，按完整编译Sources集合和字节核对，绑定实际模块/header/archive并检查输入前后未变，不重编C++。SDK类型检查不是安装、启动或界面视觉验收；整App构建与实际成衣效果另行验证。

当前Native137与修正continuous-eased核心的实际结果：

- /private/tmp/TailorAssJointDrapeEntryCurrent137Second：78个真实Swift输入，arm64 iOS17及x86_64 Simulator17严格typecheck均终态0；11项入口/来源传递检查通过，源码before/copy/after与Native完整Sources绑定未变。
- /private/tmp/TailorAssJointDrapeEntryLifecycle137First：实际53个核心/页面依赖模型加原ViewModel slice，Mac编译与运行均0，9项真实生命周期控制通过。与上述UI快照共54个模型/页面输入逐SHA相同；无Mock或伪造Validated。
- /private/tmp/TailorAssJointWorkflowGathered137First：实际完整4片/6接缝WB+Skirt2、source SHA b62f56b1…96825b，真实S.prepare后提前拒绝，仅出现capturing/preparing，无assembling/completed/Result；Mac编译与运行均0。

首次扩展到实际NativeDesign/PDF分支的typecheck失败保留在/private/tmp/TailorAssJointDrapeEntryCurrent137First：测试闭包遗漏Services/GarmentCodePDFExporter，另暴露旧编辑模式Binding方法值的Sendable警告。补齐真实依赖、改用明确闭包，并完成面料同步失效后，才得到上述Second结果。未关闭并发/警告检查，也没有修改核心求解或拟合算法。

以上只证明当前入口、编译和实际后台生命周期，不宣称界面已视觉检查、App已安装或整衣已完成。完整App构建由独立集成检查负责。
