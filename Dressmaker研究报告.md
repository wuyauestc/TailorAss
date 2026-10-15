# Dressmaker 限时研究报告（公开资料）

> 研究时间：2026-10-14，限时 2-3 天，只看公开资料和可观察行为。
> **不做逆向分析**，靠对照实验间接验证。

---

## 一、基本信息

| 项 | 值 |
|---|---|
| 开发者 | Cozy Lives（Free Lives 内部小团队，3 人全职） |
| 发行方 | Free Lives（南非开普敦，GORN/Broforce/Terra Nil 开发商） |
| 发行日期 | 2026-09-21 |
| 团队规模 | 3 人全职（Ruan Rothman, Sara Laubscher, Jonathan Hau-Yoon）+ 外包 |
| 原型时间 | 2025 年 7 月第一个 playable prototype → itch.io |
| 类型 | Cozy / 模拟 / 创意 |
| 游戏平台 | Steam（PC/Mac） |
| 游戏引擎 | **Unity 6**（IGDB 确认） |

---

## 二、核心技术发现（来自 Engadget 官方采访）

### 2.1 确认：不是真实布料仿真

**Jonathan Hau-Yoon（Terra Nil 联合创始人）原话**：

> "There's the 3D version of a dress that lives on the mannequin, and the 2D version of each of its pieces that is used for cutting out fabric. This is similar to doing UV unwrapping in traditional 3D software: **Wherever you place the pattern on the fabric is exactly what appears on the dress**. But where UV unwraps are usually done to minimize distortion or for easy packing, these UVs have to be done to look plausibly equivalent to real-world dress patterns."

### 2.2 关键技术：晶格变形 + UV 映射

> "We use a **lattice** to change the mannequin and dress sizes, but doing this naively without also adjusting the 2D patterns would cause the fabrics to appear stretched. We had to figure out how to make the 2D patterns be able to adapt to the sized dresses to minimize stretching."

### 2.3 Mesh 精度要求

> "The meshes also have to be quite precise, since the game needs to be able to figure out where the **seams between panels** are for sewing, where **seam allowance** should be, and where to draw the markings for **seam allowance and grain alignment**."

---

## 三、推断的完整技术链路

基于公开访谈，Dressmaker 的内部实现大概率是：

```
预建 3D 成衣 mesh（每件款式一个，精确 UV + seam 标记）
   ↓
用户在 2D 布料平面摆放 pattern pieces（裁片）
   ↓
系统根据 pattern piece 位置 → 2D UV 坐标映射到 3D mesh
   ↓
用户拖拽 pattern 到 mannequin 上（3D 视角）
   ↓
系统用 lattice deformer 调整 mannequin 尺寸 → 2D pattern 同步缩放
   ↓
seam 位置由 3D mesh 上的 seam marker 预定义（不是用户手动标注）
   ↓
最终 3D 成衣展示
```

### 关键推断

1. **3D mesh 是预建的**：每件款式（T 恤/裙子/外套）都有一个精确建模的 3D mesh，带正确的 UV、seam 标记、grain line
2. **seam 关系预定义在 3D mesh 上**：不需要用户在 2D 裁片上标注缝合边——3D mesh 上哪些边该缝好就是固定的
3. **Lattice deformer 做尺寸变化**：改变 mannequin 三围 → 3D mesh 变形 → 2D pattern 同步缩放
4. **2D → 3D 通过 UV 映射**：用户在 2D 布料上摆 pattern，pattern 的 UV 位置决定 3D 成衣上的外观
5. **没有实时布料仿真**：衣服是刚性 mesh，不垂坠，不响应物理

---

## 四、对 TailorAss M6 的启示

### 4.1 路线 A（几何变形）可行

Dressmaker 用 Unity 6 + lattice deformer 做到了"3D 成衣外观"，**不用任何布料物理引擎**。这证明：
- **M6 路线 A 完全可行**，不需要买 Obi Cloth
- 核心工作量在**预建 3D 成衣模板**（精确 mesh + seam 标记）
- 用户的 2D 裁片映射到预建模板上即可

### 4.2 路线 A 的前提条件

| # | 前提 | Dressmaker 怎么解决 |
|---|---|---|
| 1 | 预建 3D 成衣模板 | 每件款式（T 恤/裙子）一个精确 mesh |
| 2 | 精确 UV 映射 | Sara Laubscher 手动 unwrapping 以匹配真实纸样 |
| 3 | 预定义 seam 位置 | 3D mesh 上有 seam marker |
| 4 | 尺寸变化 | Lattice deformer + 2D pattern 同步缩放 |
| 5 | 2D 裁片 → 3D mesh 映射 | UV 坐标对应 |

### 4.3 TailorAss M6 与 Dressmaker 的关键差异

| 维度 | Dressmaker | TailorAss M6 |
|---|---|---|
| 3D 成衣来源 | **预建模板**（每件款式一个） | **用户自绘裁片** → 动态生成 |
| 2D 裁片 | 也是预设计的 pattern | 用户在排料画板自由绘制 |
| 缝合关系 | 预定义在 3D mesh 上 | 用户显式声明（GarmentPattern.seams） |
| 尺寸变化 | lattice deformer 预设尺寸 | M6 固定 M 码人台 |

**这个差异是 M6 的核心挑战**：Dressmaker 的 3D mesh 是预建好的，TailorAss M6 需要**从用户的 2D 裁片动态生成 3D mesh**。

### 4.4 M6 路线 A 怎么对应 Dressmaker 的方法

```
Dressmaker                          TailorAss M6 路线 A
────────────────────────────────────────────────────────────
预建 3D T 恤 mesh                  预建 3D T 恤模板 mesh
（精确 UV + seam marker）          （精确 UV + seam marker）
                                          ↓
用户放 2D pattern on fabric        用户在排料画板画 2D 裁片
（位置 → UV → 3D 外观）            （GarmentPattern JSON）
                                          ↓
                                    GarmentPattern 对照预建模板
                                    → 把用户裁片映射到模板 mesh 上
                                    → 应用 seam 关系
                                          ↓
                                    3D 成衣展示
```

**但这里有个问题**：TailorAss 用户的裁片是自由绘制的，尺寸可能和模板不一样。这意味着路线 A 需要：
- 方案 A1：**只支持和模板尺寸匹配的裁片**（M6 最简单）
- 方案 A2：**自动把用户裁片变形/缩放到模板尺寸**（复杂）
- 方案 A3：**不用模板，直接用用户裁片的 2D 形状 + seam 关系做几何变形**（最灵活但最难）

### 4.5 对照实验聚焦

对照实验（阶段 1）应该聚焦：

| 路线 | 核心思路 | 验证重点 |
|---|---|---|
| A. 几何变形 | 预建 3D T 恤模板 + 用户裁片变形到模板 | 从用户 2D 裁片 → 3D mesh 的几何变形链路是否可用 |
| B. Obi Cloth | 用户裁片 → Mesh → Obi Cloth + Stitcher → 仿真 | 物理仿真在移动端的稳定性和耗时 |

**路线 A 不需要 Obi**，路线 B 才需要。对照实验结果决定是否购买 Obi。

---

## 五、Dressmaker 未回答的问题

以下公开资料未覆盖，需要后续研究或等 POC 验证：

| # | 问题 | 影响 |
|---|---|---|
| 1 | Dressmaker 的 3D mesh 是否支持**任意尺寸的用户裁片**？ | 如果只支持预设计 pattern，则 TailorAss 需要额外的映射层 |
| 2 | 用户能否**自由绘制 pattern** 还是只能从预设中选？ | 访谈未明确，可能是预设 pattern |
| 3 | lattice deformer 只是改尺寸还是改**形状**？ | 影响 M6 对非标准裁片的支持 |
| 4 | 3D mesh 上的 seam marker 数据格式？ | 如果能拿到格式，可能直接复用 |
| 5 | 是否用了 Unity 的 Deformer 包还是自研？ | 影响路线 A 的技术选型 |

---

## 六、研究结论

| # | 结论 |
|---|---|
| 1 | Dressmaker 用 Unity 6 + lattice deformer，**不用物理布料仿真** ✅ |
| 2 | 路线 A（几何变形）对 TailorAss M6 **完全可行** ✅ |
| 3 | 路线 A 的核心工作量在**预建 3D 成衣模板 + 裁片到模板的映射** |
| 4 | **路线 B（Obi Cloth）仍然需要** — 路线 A 对非模板款（用户自由裁片变形）可能不够用 |
| 5 | 两条路线对照实验**必须做** — 路线 A 可能够用但泛化有限，路线 B 更通用但成本高 |
| 6 | **不需要买 Obi Cloth** 直到对照实验证明路线 A 不足 |

---

## 七、参考来源

- [Engadget Indie Pitch: Dressmaker（2026-09-21 官方技术访谈）](https://www.engadget.com/2264203/engadget-indie-pitch-dressmaker/)
- [Free Lives 官网](https://freelives.net/games/dressmaker/)
- [Dressmaker Steam 页面](https://store.steampowered.com/app/4019220/Dressmaker/)
- [IGDB Dressmaker 条目（确认 Unity 6 引擎）](https://www.igdb.com/games/dressmaker--1)
- [RepackLab Dressmaker 条目（提到 custom engine，可能不准确）](https://repacklab.com/dressmaker-free-download/)

---

**研究结论**：Dressmaker 研究时间 1 天，公开资料已足够确认其技术路线（lattice deformer，非物理仿真）。限时研究到期，**不做逆向分析**，转入阶段 1 对照实验。
