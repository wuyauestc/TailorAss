# GarmentCode 人体尺寸 → 裁片尺寸映射表

> 目标：对齐 GarmentCode 的转换逻辑，替换 Swift 生成器中的硬编码和简单比例。
> 源码基础：bodice.py、tee.py（直筒 T 恤）、sleeves.py、circle_skirt.py、pants.py、base_classes.py

> **状态说明**：本文件是早期差距分析草稿，包含当时提出的本地近似公式和过期的实现对照，不能直接当作 GarmentCode 官方计算规范。官方 body 派生公式和各款式完整计算链请以 [GarmentCode_人体尺寸至裁片逻辑.md](./GarmentCode_人体尺寸至裁片逻辑.md) 及其中固定 commit 的上游源码为准。

---

## 一、body dict 派生量定义（GarmentCode 内部）

GarmentCode 的 body dict 由 GarmentMeasurements（C++ 库）从 3D 人体网格自动测量，输出 YAML 供 pygarment 使用。以下 key 是从源码反推的完整结构：

### 1.1 直接测量（原始输入）

| key | 物理意义 | 我们有对应参数 |
|-----|---------|--------------|
| `bust` | 胸围（净围，cm） | ✅ `bustCm` |
| `waist` | 腰围（净围，cm） | ✅ `waistCm` |
| `hips` | 臀围（净围，cm） | ✅ `hipCm` |
| `back_width` | 后背宽（后肩点之间的水平距离，cm） | ❌ 缺失 |
| `waist_back_width` | 后腰宽（cm） | ❌ 缺失 |
| `hip_back_width` | 后臀宽（cm） | ❌ 缺失 |
| `shoulder_w` | 肩宽（两侧肩点距离，cm） | ✅ `shoulderWidthCm` |
| `neck_w` | 颈根宽（cm） | ❌ 缺失，我们有 `neckCircCm` |
| `height` | 身高（cm） | ✅ `heightCm` |
| `head_l` | 头长（头顶到颈根的垂直距离，cm） | ❌ 缺失 |
| `arm_length` | 臂长（肩点到腕点，cm） | ✅ `armLengthCm` |
| `wrist` | 腕围（cm） | ✅ `wristCircCm` |
| `leg_circ` | 大腿围（cm） | ✅ `thighCircCm` |
| `bust_points` | 胸距（两乳峰点水平距离，cm） | ❌ 缺失 |
| `bum_points` | 臀峰距（cm） | ❌ 缺失 |

### 1.2 关键派生量（必须计算出来，GarmentCode 广泛依赖）

| key | 物理意义 | 推导公式/值 | 我们有吗 |
|-----|---------|-----------|---------|
| **`_shoulder_incl`** | **肩倾角（度）** | `atan2(肩点高度差, 肩宽)`，典型值 ~10-20° | ❌ 缺失 |
| `waist_line` | 腰高（颈根→腰线垂直距离，cm） | 直接测量，典型值 = `height * 0.5` | ❌ 我们只有 `backLengthCm` |
| `_bust_line` | 胸高（颈根→乳峰点垂直距离，cm） | 直接测量 | ❌ 缺失 |
| `waist_over_bust_line` | 腰高 - 胸高 | `waist_line - _bust_line` | ❌ 缺失 |
| `_armscye_depth` | **袖窿深度（cm）** | `bust/2 - shoulder_w/2 - 2`（经验公式） | ❌ 我们用 `upperLength * 0.34` |
| `_base_sleeve_balance` | 袖平衡量 | `(bust/2 - armscye_depth) * 0.25` | ❌ 缺失 |
| `hips_line` | 臀高（颈根→臀峰，cm） | 直接测量 | ❌ 缺失 |
| `_leg_length` | 腿长比例系数 | 直接测量或 `height * 0.45` | ❌ 缺失 |
| `crotch_hip_diff` | 裆深 - 臀高（cm） | rise 计算 | ❌ 缺失 |
| `_hip_inclination` | 臀倾角（度） | `atan( (hip/2 - waist/2) / hips_depth )` | ❌ 缺失 |
| `arm_pose_angle` | 手臂自然下垂外展角（度） | 固定 15° | ❌ 缺失 |

---

## 二、tee.py（直筒 T 恤）vs 我们当前实现

GarmentCode 的直筒款用 `TorsoFrontHalfPanel` / `TorsoBackHalfPanel`，非常简洁，与我们的 pieceUpperCurved 最接近。

### 2.1 前片（TorsoFrontHalfPanel）

| 裁片量 | GarmentCode 公式 | 我们的公式 | 差距 |
|--------|-----------------|-----------|------|
| **前片宽 `self.width`** | `front_frac * m_width`，其中 `front_frac = (bust - back_width) / 2 / bust`，`m_width = design.width * bust` | `(bust + ease) / 4` | ❌ 我们没有分前/后片，直接除以 4；缺 back_width 比例分配 |
| **下摆宽 `b_width`** | `design.flare * self.width` | 同一值 | ⚠️ 我们有 bulge(-hemCurve)，但没有独立 flare 系数 |
| **肩倾角 `shoulder_incl`** | `tan(_shoulder_incl°) * self.width` | 固定 y=2.5（硬编码） | ❌ 我们完全缺肩倾角 |
| **长度 `length`** | `design.length * waist_line - tan(_shoulder_incl) * fb_diff`，其中 `fb_diff = (front_frac - (0.5 - front_frac)) * bust` | `upperLengthCm`（直接取值） | ❌ 我们没有肩倾角校正 |
| 底边 y | `length` | `length` | ✅ |
| 肩点 y | `length + shoulder_incl` | 固定 y=2.5 | ❌ |

### 2.2 后片（TorsoBackHalfPanel）

| 裁片量 | GarmentCode 公式 | 我们的公式 | 差距 |
|--------|-----------------|-----------|------|
| **后片宽** | `back_frac * m_width`，其中 `back_frac = back_width / 2 / bust` | 和前片相同 `(bust+ease)/4` | ❌ 前后片应不同宽 |
| 肩倾角 | `tan(_shoulder_incl) * self.width` | 同前片（硬编码） | ❌ |
| 长度 | `design.length * waist_line`（后片无 fb_diff 校正） | 同前片（相同值） | ❌ 后片应该比前片略短 |

### 2.3 关键差异总结

GarmentCode 用**4 个量**决定身片形状，我们只用了**2 个**：
- ✅ 我们有：bust、shoulder_w
- ❌ 我们缺：back_width、_shoulder_incl（肩倾角）

加上：
- ❌ 我们缺长度校正（前片比后片短一点）
- ❌ 我们缺 flare 系数（下摆可以比胸围宽）

---

## 三、sleeves.py 袖片对比

**最关键发现：GarmentCode 的袖山不是独立定义的！**

GarmentCode 袖山曲线由以下流程生成：
1. 袖窿形状由 `ArmholeCurve`（cubic Bezier，控制点固定 `[[0.5, 0.2], [0.8, 0.35]]`）从 bodice shoulder_corner 投影出来
2. 袖山形状是袖窿的反形状，用 `pyg.ops.curve_match_tangents` 做逆变换
3. 袖山高 = `opening_length`（投影出来的深度，不是独立参数）
4. 袖山宽 = `front_w - sleeve_balance` 和 `back_w - sleeve_balance`（由 bodice 的前后肩线宽度决定）

### 3.1 袖片尺寸对比

| 裁片量 | GarmentCode 公式 | 我们的公式 | 差距 |
|--------|-----------------|-----------|------|
| **袖山宽** | `front_w - sleeve_balance` / `back_w - sleeve_balance` | `max(12, (bicepCirc + sleeveEase) * 0.72)` | ❌ 我们和 bodice 无关，独立定义 |
| **袖山高** | `opening_length`（从 bodice 投影） | `capHeightCm * 0.375` | ❌ 独立定义，和袖窿不匹配 |
| **袖山曲线** | ArmholeCurve cubic Bezier `[[0.5,0.2],[0.8,0.35]]` + curve_match 逆变换 | 两段 quadratic `.bulge(4.5)` | ❌ 形状和匹配逻辑都不同 |
| **袖长** | `design.length * (arm_length - opening_length)` | `sleeveLengthCm` 直接取值 | ❌ 没有减去袖山投影长度 |
| **袖口宽** | `max(end_width * arm_width, wrist/2)` | `sleeveOpeningCm / 2` | ⚠️ 基本对，但我们没设最小值 |
| **袖口曲线** | 无（直边） | `.bulge(1.5 * (1 + cuffWidth*0.05))` | ⚠️ 我们加了额外弧度 |

### 3.2 核心差异

GarmentCode 的袖片和身片**强耦合**——袖山形状由身片的 shoulder_corner 决定。我们的是**独立定义**的矩形 + 圆弧。

要对齐，需要：
1. 先算 bodice 的 shoulder_corner 接口（肩线端点的位置）
2. 袖山从 shoulder_corner 通过 ArmholeCurve 投影得到
3. 袖山高 = 投影深度，不是独立参数

---

## 四、circle_skirt.py 圆裙对比

### 4.1 GarmentCode 公式

```python
# 腰头半径
top_rad = top_width / arc   # arc = sun_fraction * 2π

# 单片圆心角 = sun_fraction / 2（前/后各一半）
halfarc = arc / 2

# 弦长（腰头/裙摆在裁片平面上的水平投影）
dist_w = 2 * top_rad * sin(halfarc)
dist_out = 2 * (top_rad + length) * sin(halfarc)

# 裁片高度方向的垂直距离
vert_len = length * cos(halfarc)

# 腰头弧（上边界）：radius=top_rad，从 (-dist_w/2, 0) 到 (dist_w/2, 0)
# 侧边：从腰头端点 到 裙摆端点（直线）
# 裙摆弧（下边界）：radius=top_rad+length，从 (dist_out/2, -vert_len) 到 (-dist_out/2, -vert_len)
```

### 4.2 我们的公式（sector）

```swift
let waistRadius = (waistCm + easeCm) / (2 * .pi)  // 半径
let arcAngle = fullnessRatio * 2 * .pi            // 圆心角
let halfAngle = arcAngle / 2
// 锚点直接用极坐标转直角
// 圆弧用 sagitta 表示
```

### 4.3 差异

| 项目 | GarmentCode | 我们 |
|------|------------|------|
| 腰头半径 | `waist / arc` | `(waist + ease) / arc` |
| 前后分片 | 前片+后片，各 `arc/2` | 单整片 |
| 腰头弧方向 | 向下凹（凹向裁片中心） | 相同 |
| 侧边 | 直线 | 直线 |
| 裙摆弧 | 向下凸（凸向裁片外侧） | 相同 |

**基本一致**，主要差异是我们加了 ease 和不分前后片。这部分改动不大。

---

## 五、pants.py 裤子对比

### 5.1 GarmentCode 关键公式

```python
# rise 参数决定高腰/中腰/低腰
self.rise = design['rise']['v']  # 0-1，高腰=1.0，低腰=0.5
waist = lin_interpolation(hips, waist, rise)
hips_depth = rise * hips_level

# 裆部宽度分配
min_ext = leg_circ - hips/2 + 5      # 裤腿最小底部宽度 + 2 inch ease
front_hip = (hips - hip_back_width) / 2
front_extention = front_hip / 4      # 前裤片裆部外展
back_extention = min_ext * width - front_extention  # 后裤片裆部外展

# 裤长
length = design['length']['v'] * leg_length

# 裤脚外展（flare）
flare = leg_circ * (design['flare']['v'] - 1) / 4

# 裆部点
crotch_top = [hips, length + 0.45 * hips_depth]  # 裆顶比臀线高 0.45*hips_depth
crotch_bottom = [hips + crotch_extention, length - crotch_depth_diff]
```

### 5.2 差异

| 项目 | GarmentCode | 我们 | 差距 |
|------|------------|------|------|
| rise 参数 | 0-1 比例 | 直接裆深 cm | ⚠️ 表示法不同 |
| 前/后裤片分配 | 前 `front_hip/4`，后 `min_ext*width - front` | 前 `crotchDepth`，后 `crotchDepth + 1.0` | ⚠️ 我们用硬编码差值 |
| 裤裆曲线 | curve_from_tangents（Cubic Bezier） | `.bulge(back ? 3.2 : 2.2)` | ⚠️ 形状差异 |
| 裤长 | `design.length * leg_length` | 直接 pantsLengthCm | ⚠️ |
| 裤脚 flare | `leg_circ * (flare - 1) / 4` | 无 | ❌ |

---

## 六、必须新增的中间量（按优先级）

### P0 — 最高优先级（影响身片/袖片核心形状）

| 中间量 | 来源公式 | 依赖 |
|--------|---------|------|
| **肩倾角 `_shoulder_incl`** | `atan2(肩点高度差, shoulder_w)` | 需要肩点高度（从身高比例推） |
| **后背宽 `back_width`** | 默认 `shoulder_w * 0.75`（经验值，GarmentMeasurements 精确测量） | shoulder_w |
| **袖窿深 `_armscye_depth`** | `bust/2 - shoulder_w/2 - 2` | bust, shoulder_w |
| **腰高 `waist_line`** | `height * 0.5`（默认）或 `frontLengthCm` | height |

### P1 — 中优先级（影响长度校正、袖口匹配）

| 中间量 | 来源公式 | 依赖 |
|--------|---------|------|
| **胸高 `_bust_line`** | `height * 0.55 - waist_line`（乳峰在腰线上 ~10cm） | height, waist_line |
| **臀高 `hips_line`** | `height * 0.65` | height |
| **袖平衡量 `_base_sleeve_balance`** | `max(2, (bust/2 - armscye_depth) * 0.25)` | bust, armscye_depth |
| **腿长比例 `_leg_length`** | `height * 0.45` | height |
| **腰后宽 `waist_back_width`** | `back_width * 0.85` | back_width |
| **臀后宽 `hip_back_width`** | `back_width * 0.9` | back_width |

### P2 — 低优先级（省道、喇叭等高级特性）

| 中间量 | 来源公式 | 依赖 |
|--------|---------|------|
| 胸距 `bust_points` | `bust * 0.18` | bust |
| 臀峰距 `bum_points` | `hips * 0.18` | hips |
| 颈根宽 `neck_w` | `neckCircCm / π` | neck_circ |
| 头长 `head_l` | `height * 0.13` | height |
| 裆深差 `crotch_hip_diff` | 由 rise 决定 | rise, hips_line |
| 臀倾角 `_hip_inclination` | `atan((hips-waist)/2 / hips_depth)` | hips, waist, hips_depth |

---

## 七、实施路线

**Step 1**：在 `GarmentDesignSpec` 或新建 `GarmentBodyMeasurements` 里计算所有 P0 中间量

**Step 2**：重写 `addUpper` + `pieceUpperCurved`（身片）
- 用 back_width 比例分配前/后片宽度
- 用肩倾角校正长度和肩线
- 腰高 = `height * 0.5` 而不是 `upperLengthCm`

**Step 3**：重写 `pieceSleeveCurved`（袖片）
- 袖山从肩线位置通过 ArmholeCurve 投影
- 袖山宽依赖 bodice 宽度 + sleeve_balance
- 袖长减去袖山投影深度

**Step 4**：更新 `addBottom`（下装）
- 裤子 rise 比例化
- flare 接入 leg_circ 计算

**Step 5**：参数校验对齐（用真实物理意义的范围）

---

## 八、对现有架构的影响

**不需要重构**，当前架构（GarmentDesignSpec → addUpper/addBottom → pieceUpperCurved/sector → polygonCurved → PatternPiece）完全可以复用。

只需替换：
1. `addUpper` 里的派生公式（P0 中间量）
2. `pieceUpperCurved` 里的硬编码常量（肩线 y=2.5、neckDepth=7/9）
3. `pieceSleeveCurved` 的袖山逻辑（从独立定义改为从肩线投影）

**可以保留的**：
- EdgeSpec + polygonCurved 框架 ✅
- EdgeGeometry 采样/弧长 ✅
- 接缝校验 ✅
- 所有 UI 代码 ✅

---

**文档版本**：v1.0

**创建日期**：2026-10-20
**基于源码**：bodice.py, tee.py, sleeves.py, circle_skirt.py, pants.py, base_classes.py
