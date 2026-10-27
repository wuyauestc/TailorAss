# 主伸长障碍的 PSD 预条件器

`Membrane.Prepared.principalBarrierPreconditioner` 为现有主伸长能量提供数值代理，
`JointPreconditioner` 将其散射到既有完整源三角面9×9模式。原能量、梯度、原始
Hessian、材料、源度量、碰撞、Newton／CG／Armijo条件均不变。

设 `F=U diag(sl,sh) Vᵀ`，障碍密度为 `b(sl)+b(sh)`。在3×2形变空间的六个
正交模式及真实密度曲率为：

| 模式 | 曲率 |
| --- | --- |
| 两个主伸长 `u_i v_iᵀ` | `b''(s_i)` |
| 对称切变 `(ul vhᵀ+uh vlᵀ)/sqrt(2)` | `(b'(sh)-b'(sl))/(sh-sl)` |
| 面内转动 `(ul vhᵀ-uh vlᵀ)/sqrt(2)` | `(b'(sh)+b'(sl))/(sh+sl)` |
| 两个法向 `n v_iᵀ` | `b'(s_i)/s_i` |

只在该代理中将负密度曲率截为0，得到 `H_F⁺`，再用原形函数导数拉回：
`P_triangle = A0 Dᵀ H_F⁺ D`。它通常不等于先拉回再对9×9矩阵截正；测试
明确区分这两种操作。实际真实H仍保留压缩时可能出现的负曲率。

重复伸长的对称切变取 `b''` 极限，三个对称模式形成同一基不变子空间。近重复
伸长的同一障碍分支使用 `log1p` 和正有理项计算解析差商，避免先减去两个近等的
`b'`。这是P的稳定计算，未改动原真实Hv中的差商。

API返回完整成功的不可变块集合；无效坐标／域、取消和预算失败均无返回集合。
块数上限40,000，默认暂存计费64MiB，有显式块数及字节预算；计费包括保守的
数组元素／容量和背后存储开销，不冒充RSS实测。P更新开始即失效旧因子，失败
不能复用旧factor。Plan现精确绑定全部五个障碍参数。源CSC和scatter不扩图。

## 独立验证

```sh
python3 Tests/NativePattern/run-principal-barrier-preconditioner.py \
  --output /private/tmp/TailorAssBarrierPreconditionerNewRun \
  --package-proof /private/tmp/TailorAssIPCOrientationIdentityIntegratedFinal \
  --package-source /private/tmp/TailorAssIPCOrientationIdentityIntegratedFinal/snapshot \
  --oracle-python /path/to/python-with-numpy
```

运行器只重新编译当前App Swift，核对完整原生源集合／字节并绑定实际库和模块
SHA。`--package-source` 可明确使用与该库一致的冻结包，避免混入其它并行原生
改动。默认读取当前工作区原生包；不匹配会拒绝。

12组控制覆盖非激活、激活点、均匀拉伸／压缩、混合伸长、近重复及一ulp差距、
接近上下界。独立NumPy/LAPACK取生产真实局部H的完整6×6形变子块做特征分解，
再独立用真实D拉回完整9×9。另以90位标量计算和独立高精度主伸长检验稳定差商。
旋转协变、源重编号、几何放大10倍后的SI关系、完整源散射、原目标逐位不变、
开始／晚取消、输入／预算／foreign参数与失败后因子失效均通过。

近重复情况下，已有真实binary64 Hv差商本身有消减误差，专项如实报告它与高精度
物理密度正部的差异（最大约 `8.43e−5`），没有修改真实Hv或将它冒称高精度期待。
其余非近重复病例仍直接与完整真实H的独立特征正部核对。稳定P相对90位密度正部
最大误差约 `7.80e−12`，完整9×9拉回最大误差约 `8.25e−12`。

最终纯代理检查位于 `/private/tmp/TailorAssBarrierPreconditionerFinal`；现有完整
P源／缝合／铰链回归为 `/private/tmp/TailorAssJointPreconditionerSourceBarrierLegacy`，
完整CP回归为 `/private/tmp/TailorAssContactPreconditionerSourceBarrier`。三项均实际
通过、源与原生依赖字节保持，没有重新编译C++。

## 实际第250步的只读曲率检查

输入来自修正接触库后真实圆裙＋腰头长跑：已接受249步，第250步未提交。
冻结文件、原始参数及完整源不变。检查本身不推进Newton或物理时间。

当前195个源面激活主伸长障碍。最紧的前裙面1623（顶点968、969、1284）主伸长
为1.0699462705470582，距1.07上界约 `5.37295e−5`。其归一化高伸长方向在全局
真实H中的障碍曲率约 `12,492,698 N/m`，旧完整P仅约 `1,912 N/m`；新完整P为
`12,494,610 N/m`，该方向的障碍／P比由约6,533变为0.999847。最刚的其它七面
得到同类覆盖。source9×9模式和全部接触项均保留。

新P组装前后真实Phi、梯度、原始Hv逐位相同；实际梯度仍为
`1.2759844866053194e−6 N`，没有达到 `1e−6 N` 门槛，不能作为已收敛结果。
原始诊断保留在 `/private/tmp/TailorAssCircle250BarrierConditioning/attempt2`，
新P对照为同目录 `attempt3-newP`。这只证明刚度代理的修正和算子边界；完整
子步、收缝、重力、最终validator、App和手机验证仍由整条主流程单独完成。

首轮测试的原生集合不匹配、第二轮的“十进制边界乘法会向内舍入”测试前提错误、
第三轮独立oracle的重复根舍入问题，以及初始曲率工具遗漏回调参数的编译失败
均保留在各自独立目录。未改写任何旧失败或历史结果。
