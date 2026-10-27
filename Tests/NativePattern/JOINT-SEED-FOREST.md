# 真实物理子步种子专项

本专项只验证已提交时间分区的复用、真实物理推进和失败原子性。它没有从初态重新生成整衣，不授予旧检查点历史轨迹资格，不产生 `R.Validated`、OBJ 或 App 可用成衣。

测试固定 S `d81b850a…61d7`、R `3359e3f3…41e9`、N `2609fe9f…99e2` 和 Native129。模型取自 root 已封存的 `TailorAssJointSeedForestControls` 的45文件；使用其资源和 Native129 已编静态库。严格 Swift5 / MainActor / complete concurrency / warnings-as-errors，未重编 C++。

## 真实起点与通过范围

长期夹具 `Fixtures/3d-joint-circle922-seed` 保留原从0运行的 accepted922 完整位置、真实速度、旧 last-accepted-frame 两个实际半步，以及 source/rest/mass/0pins/body/plan、材料和时间调度。文件逐项绑定原运行 seal。922只有 `[0,1],[1,2]/2` 两个旧半步被映射成 `/8` 的 `[0,4],[4,8]` 种子；后来923的五叶分区不是输入。

测试加载器仅追加到临时 S 文件，不修改生产函数。它导入 State922 和同一新 Session 绑定的 control，`lastAcceptedFrame=nil`。origin tag 为完整旧 archive SHA 前16原始字节的 UUID，明确不是历史新版本 frame UUID。加载不能制造 accepted-frame 或 final-result 能力。

本轮实际证据在 `/private/tmp/TailorAssJointSeedForestActualThird`：

| 控制 | 实际结果 |
| --- | --- |
| 923，历史922两半步种子 | 5叶、2种子、8尝试，满足 `2L−K`；fresh最大力 `1.2308483e−7 N` |
| 924，只继承真923提交分区 | 同5叶、5种子、5尝试，无失败父尝试；fresh最大力 `4.2389241e−8 N` |
| depth2 同历史半步种子 | 6尝试，3个 provisional 前缀叶成功，最后 quarter 拒绝；State/control/journal/quiet 全部不提交 |
| depth3 真 `[6,7]/8` 接受后取消 | 抛 `CancellationError`，所有公共状态与控制逐位保持922，最后叶未运行 |

923、924每个实际叶均经过 R fresh current-force/current-P/Pz、完整 source/body/self 连续路径复核，同可见 mesh 精确内外与面交检查通过。924 的 previous control 精确等于实际923发布 control，origin ID 指向实际923记录，不能借用另一 Session、未来分区或诊断候选。诊断结束的 final validator 因不具备真实24静稳帧而拒绝，未输出成衣。

取消证据在 `/private/tmp/TailorAssJointSeedForestAtomicCancellationSecond`。它只在临时 S 的真实 leaf append 后增加一个同步 observer；无算术、材料、N 或验收修改。observer保存的 `[6,7]/8` provisional 叶最大力 `1.2307865e−7 N`，触发后不提交已成功前缀。

## 时间与资源边界

923测得 wall 331.30s，其中接受尝试8.55s、失败父尝试320.85s；924测得 wall11.42s，接受尝试9.58s、失败父尝试0。旧 root-only923生产诊断 wall286.06s使用旧 Nbc/S137/R794，且本轮机器同时有其他计算；两者不能当作同设置性能 A/B，也不能宣称本轮923 wall更快。可确认的是924真正复用了已提交分区，实际没有再求失败父节点。工作量始终有界，depth3最多8叶，实际森林完整满足 `2L−K`。

## 481逐位控制的真实失败

两个 policy 从原真实480最终静态端点和零速度开始，且逐位核对原481首 physical leaf 的 previous x/v。两 policy 同一 Prepared，初始 x/v、predictor、dt/τ、sewing/gravity load、第一root和初始最大力逐位相同，均3次 Newton、1根/1叶，全部原 fresh KKT / 连续 source/body/self / 可见人体检查通过。

原“输出位置速度必须逐位相同”断言实际失败，保留原进程 exit−5。policy间最大位置差 `1.0269563e−15 m`、速度差 `2.4646951e−13 m/s`。同一已编 binary 再起进程重复同 policy，root-only 本身也有最大位置差 `1.1310397e−15 m`，所以不能把末位差异归为种子策略造成的物理错误。四个实际481 fresh最大力约 `1.1–1.33e−8 N`，current-P修正约 `1.7e−15 m`，所有原路径全通过。

最早可观察差异已在第0轮 CG 真残差及首接受端点；完整初始 force 向量、P数值系数和具体底层运算未导出，不能据此声称已定位到某个字典或 Accelerate 操作。生产 source/contact P 的 CSC key 明确排序，代码阅读本身不证明其底层逐位确定性。本轮没有放宽物理门槛，也没有把原 bitwise 断言改成通过。该精确重现性限制单列为后续工作，不阻止923/924已获得的实际能力证据。

## 复现与证明范围

`run-joint-seed-forest.py --output <新目录>` 冻结源并依次执行923→924、481和depth2。严格481断言若失败，默认会停止后续 mode；可复用生成的同一个 binary 单独执行depth2，不必重新求923。`--mode cancel` 制作另一个只有 observer 补丁的临时 binary。不得把这些控制用于初态整衣或导出能力。

`audit-joint-seed-forest.py <输出目录>` 独立核对文件/source/native SHA、数据位、旧 archive tag、种子谱系、时间分区、τ/load和记录链。它不是另一份 native 几何 oracle；实际几何与fresh力证明来自明确保存的生产 R 调用。当前综合交付保留481断言失败和同policy重现性分析，不将整个专项虚报为全部通过。
