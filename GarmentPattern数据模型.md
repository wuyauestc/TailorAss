# GarmentPattern 数据模型（阶段 0 定稿）

> 本文件是 M6 阶段 0 的核心产出。定义了裁片 → 成衣仿真的统一输入格式，几何变形路线和 Obi Cloth 物理仿真路线读同一份数据。
>
> **状态**：✅ 阶段 0 定稿，阶段 1 POC 将验证可行性

---

## 一、设计原则

| # | 原则 | 说明 |
|---|---|---|
| 1 | **统一输入** | 几何变形和 Obi Cloth 两条路线读同一份 JSON |
| 2 | **分层** | LayoutDocument（排料数据，布面摆放）≠ GarmentPattern（纸样数据，裁片形状+缝合+人台） |
| 3 | **边 ID 稳定** | 每条边有唯一 ID，不靠索引（避免多边形增减边后错位） |
| 4 | **边有方向** | fromVertex → toVertex 有方向，缝合时需对齐 |
| 5 | **不自猜** | M6 不按裁片名称自动推断缝合关系，**必须显式声明** |
| 6 | **与 Obi 解耦** | GarmentPattern 不含任何 Obi 特定字段（粒子索引、constraint 参数等） |
| 7 | **自包含** | 单份 JSON 可独立运行，不依赖外部引用 |

---

## 二、完整 JSON Schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://tailorass.app/schemas/GarmentPattern.json",
  "title": "GarmentPattern",
  "version": "1.0",
  "description": "裁片→3D成衣仿真统一输入格式",
  "type": "object",
  "required": ["version", "mannequin", "pieces", "seams"],
  "properties": {
    "version": { "type": "string", "pattern": "^\\d+\\.\\d+$" },
    "mannequin": { "$ref": "#/$defs/Mannequin" },
    "pieces": {
      "type": "array",
      "minItems": 1,
      "items": { "$ref": "#/$defs/Piece" }
    },
    "seams": {
      "type": "array",
      "items": { "$ref": "#/$defs/Seam" }
    }
  },
  "$defs": {
    "Mannequin": {
      "type": "object",
      "required": ["size", "heightCm"],
      "properties": {
        "size": { "type": "string", "enum": ["XS", "S", "M", "L", "XL", "XXL"] },
        "heightCm": { "type": "number", "minimum": 100, "maximum": 220 },
        "bustCm": { "type": "number" },
        "waistCm": { "type": "number" },
        "hipCm": { "type": "number" }
      }
    },
    "Piece": {
      "type": "object",
      "required": ["id", "name", "vertices", "edges"],
      "properties": {
        "id": { "type": "string", "minLength": 1 },
        "name": { "type": "string", "minLength": 1 },
        "type": {
          "type": "string",
          "enum": ["front", "back", "sleeveLeft", "sleeveRight", "collar", "pocket", "other"],
          "default": "other"
        },
        "units": { "type": "string", "enum": ["cm"], "default": "cm" },
        "vertices": {
          "type": "array",
          "minItems": 3,
          "items": {
            "type": "object",
            "required": ["id", "x", "y"],
            "properties": {
              "id": { "type": "string" },
              "x": { "type": "number" },
              "y": { "type": "number" }
            }
          }
        },
        "edges": {
          "type": "array",
          "minItems": 3,
          "items": {
            "type": "object",
            "required": ["id", "fromVertex", "toVertex"],
            "properties": {
              "id": { "type": "string" },
              "fromVertex": { "type": "string" },
              "toVertex": { "type": "string" },
              "role": {
                "type": "string",
                "enum": ["side", "shoulder", "sleeveCuff", "sleeveCap", "hem", "neckline", "waistband", "other"],
                "default": "other"
              }
            }
          }
        },
        "material": {
          "type": "object",
          "properties": {
            "thickness": { "type": "number", "default": 0.02 },
            "stiffness": { "type": "number", "default": 0.5 },
            "color": { "type": "string", "pattern": "^#[0-9A-Fa-f]{6}$" }
          }
        }
      }
    },
    "Seam": {
      "type": "object",
      "required": ["pieceA", "edgeA", "pieceB", "edgeB"],
      "properties": {
        "pieceA": { "type": "string" },
        "edgeA": { "type": "string" },
        "pieceB": { "type": "string" },
        "edgeB": { "type": "string" },
        "type": {
          "type": "string",
          "enum": ["full", "half", "blindstitch", "lockstitch"],
          "default": "full"
        },
        "samplingDensity": { "type": "number", "default": 20 }
      }
    }
  }
}
```

---

## 三、Swift 类型定义

```swift
import Foundation
import CoreGraphics

// MARK: - GarmentPattern

struct GarmentPattern: Codable, Hashable {
    let version: String
    let mannequin: Mannequin
    let pieces: [Piece]
    let seams: [Seam]
}

// MARK: - Mannequin

struct Mannequin: Codable, Hashable {
    enum Size: String, Codable { case xs, s, m, l, xl, xxl }
    let size: Size
    let heightCm: Double
    let bustCm: Double?
    let waistCm: Double?
    let hipCm: Double?
}

// MARK: - Piece

struct Piece: Codable, Hashable {
    enum PieceType: String, Codable, CaseIterable {
        case front, back, sleeveLeft, sleeveRight, collar, pocket, other
    }
    let id: String
    let name: String
    let type: PieceType
    let vertices: [Vertex]
    let edges: [Edge]
    let material: Material?

    // 边数组按 fromVertex/toVertex 对 vertices 引用，构成闭合多边形
    // edges.count == vertices.count（闭合多边形）
    // edges[i].fromVertex == vertices[i].id
    // edges[i].toVertex == vertices[(i+1) % vertices.count].id
}

struct Vertex: Codable, Hashable {
    let id: String
    let x: Double  // cm
    let y: Double  // cm
}

struct Edge: Codable, Hashable {
    enum EdgeRole: String, Codable, CaseIterable {
        case side, shoulder, sleeveCuff, sleeveCap, hem, neckline, waistband, other
    }
    let id: String
    let fromVertex: String
    let toVertex: String
    let role: EdgeRole
}

struct Material: Codable, Hashable {
    let thickness: Double    // cm
    let stiffness: Double    // 0-1
    let color: String?       // "#RRGGBB"
}

// MARK: - Seam

struct Seam: Codable, Hashable {
    enum SeamType: String, Codable, CaseIterable {
        case full, half, blindstitch, lockstitch
    }
    let pieceA: String        // Piece.id
    let edgeA: String         // Edge.id
    let pieceB: String        // Piece.id
    let edgeB: String         // Edge.id
    let type: SeamType
    let samplingDensity: Int  // 每 cm 采样点数
}
```

---

## 四、C# 类型定义（Unity 侧）

```csharp
using System;
using System.Collections.Generic;
using UnityEngine;

[Serializable]
public class GarmentPattern {
    public string version;
    public Mannequin mannequin;
    public List<Piece> pieces;
    public List<Seam> seams;
}

[Serializable]
public class Mannequin {
    public string size;       // "XS", "S", "M", "L", "XL", "XXL"
    public float heightCm;
    public float? bustCm;
    public float? waistCm;
    public float? hipCm;
}

[Serializable]
public class Piece {
    public string id;
    public string name;
    public string type;       // "front", "back", "sleeveLeft", "sleeveRight", ...
    public List<Vertex> vertices;
    public List<Edge> edges;
    public Material material;
}

[Serializable]
public class Vertex {
    public string id;
    public float x;  // cm
    public float y;  // cm
}

[Serializable]
public class Edge {
    public string id;
    public string fromVertex;
    public string toVertex;
    public string role;   // "side", "shoulder", ...
}

[Serializable]
public class Material {
    public float thickness;
    public float stiffness;
    public string color;
}

[Serializable]
public class Seam {
    public string pieceA;
    public string edgeA;
    public string pieceB;
    public string edgeB;
    public string type;           // "full", "half", ...
    public int samplingDensity;   // points per cm
}
```

---

## 五、Obi Cloth 兼容性调研结论

### 5.1 Obi Stitcher 核心 API

| API | 说明 |
|---|---|
| `AddStitch(int particleIndexA, int particleIndexB)` | 在两个粒子之间创建 stitch 约束 |
| `PushDataToSolver()` | 将 stitcher 数据推送到 solver |
| `Actor1` / `Actor2` | 设置被缝合的两个 ObiActor（两个 actor 必须在同一 solver 里） |

### 5.2 运行时创建 Cloth + Stitch 完整流程

```csharp
// 1. 为每个裁片创建 ObiCloth + Blueprint
var clothGO = new GameObject(piece.name);
clothGO.AddComponent<ObiCloth>();
clothGO.AddComponent<ObiClothRenderer>();

var blueprint = ScriptableObject.CreateInstance<ObiClothBlueprint>();
blueprint.inputMesh = pieceMesh;  // Unity Mesh，由 vertices 三角化生成
yield return StartCoroutine(blueprint.Generate());

var cloth = clothGO.GetComponent<ObiCloth>();
cloth.clothBlueprint = blueprint;

// 2. 创建 ObiStitcher 并设置两个 actor
var stitcher = new GameObject("Stitcher").AddComponent<ObiStitcher>();
stitcher.Actor1 = clothA;
stitcher.Actor2 = clothB;

// 3. 从 seam 边采样点 → 找最近粒子索引 → AddStitch
foreach (var (particleA, particleB) in seamParticlePairs) {
    stitcher.AddStitch(particleA, particleB);
}

// 4. 推送到 solver
stitcher.PushDataToSolver();
```

### 5.3 GarmentPattern → Obi Cloth 数据映射

```
GarmentPattern                          →  Unity / Obi
─────────────────────────────────────────────────────────
Piece.vertices (2D cm)                  →  Unity Mesh 顶点（三角化 + 坐标变换）
Piece.edges (fromVertex → toVertex)     →  Mesh 边索引（Unity 内部）
Seam (pieceA.edgeA ↔ pieceB.edgeB)      →  ObiStitcher.AddStitch(particleIdxA, particleIdxB)
Seam.samplingDensity                     →  每条 seam 边的采样点数量
Seam.type                               →  暂不区分（M6 统一 full stitch）
Mannequin                               →  人台 GameObject + Collider
```

### 5.4 关键设计决策：Seam.samplingDensity

GarmentPattern 不直接指定"哪两个粒子对"，而是指定**缝合边对 + 采样密度**。Unity 侧负责：

1. 从 Seam.pieceA + Seam.edgeA 找到裁片 A 的边顶点
2. 沿这条边按 samplingDensity 均匀采样 → 得到 2D 采样点坐标
3. 同样处理 pieceB.edgeB → 得到 2D 采样点坐标
4. ObiClothBlueprint.Generate() 后，blueprint.topology.clusters 存储了每个粒子对应的原始 mesh 顶点
5. 对每个采样点，找距离最近的 cluster → 得到粒子索引
6. 成对调用 stitcher.AddStitch(particleA, particleB)

**这样 GarmentPattern 完全不依赖 Obi 内部结构**，几何变形路线也能直接用 seam 数据（几何变形只需要边对对应，不需要粒子索引）。

### 5.5 Obi 暂不需要购买

POC 阶段（阶段 1）先在独立 Unity Editor 里，不需要 iOS 构建也不需要购买 License（Unity Editor 内开发免费）。等对照实验确认 Obi 路线值得走再买。

---

## 六、固定 T 恤样例数据

> M6 阶段 1 算法 POC 使用的固定 T 恤样例（4 片裁片）
>
> - 尺码：M（165cm 标准女人台）
> - 前片 + 后片 + 左袖 + 右袖
> - 所有缝合边显式声明

```json
{
  "version": "1.0",
  "mannequin": {
    "size": "M",
    "heightCm": 165,
    "bustCm": 88,
    "waistCm": 68,
    "hipCm": 92
  },
  "pieces": [
    {
      "id": "tshirt-front",
      "name": "前片",
      "type": "front",
      "vertices": [
        {"id": "fv0", "x": 0, "y": 0},
        {"id": "fv1", "x": 22, "y": 0},
        {"id": "fv2", "x": 24, "y": 3},
        {"id": "fv3", "x": 22, "y": 8},
        {"id": "fv4", "x": 30, "y": 30},
        {"id": "fv5", "x": 30, "y": 60},
        {"id": "fv6", "x": 0, "y": 60},
        {"id": "fv7", "x": 0, "y": 30},
        {"id": "fv8", "x": 8, "y": 8},
        {"id": "fv9", "x": 6, "y": 3}
      ],
      "edges": [
        {"id": "fe0", "fromVertex": "fv0", "toVertex": "fv1", "role": "hem"},
        {"id": "fe1", "fromVertex": "fv1", "toVertex": "fv2", "role": "neckline"},
        {"id": "fe2", "fromVertex": "fv2", "toVertex": "fv3", "role": "shoulder"},
        {"id": "fe3", "fromVertex": "fv3", "toVertex": "fv4", "role": "sleeveCap"},
        {"id": "fe4", "fromVertex": "fv4", "toVertex": "fv5", "role": "side"},
        {"id": "fe5", "fromVertex": "fv5", "toVertex": "fv6", "role": "hem"},
        {"id": "fe6", "fromVertex": "fv6", "toVertex": "fv7", "role": "side"},
        {"id": "fe7", "fromVertex": "fv7", "toVertex": "fv8", "role": "sleeveCap"},
        {"id": "fe8", "fromVertex": "fv8", "toVertex": "fv9", "role": "shoulder"},
        {"id": "fe9", "fromVertex": "fv9", "toVertex": "fv0", "role": "neckline"}
      ],
      "material": {"thickness": 0.02, "stiffness": 0.5, "color": "#2E86AB"}
    },
    {
      "id": "tshirt-back",
      "name": "后片",
      "type": "back",
      "vertices": [
        {"id": "bv0", "x": 0, "y": 0},
        {"id": "bv1", "x": 22, "y": 0},
        {"id": "bv2", "x": 22, "y": 2},
        {"id": "bv3", "x": 24, "y": 8},
        {"id": "bv4", "x": 30, "y": 30},
        {"id": "bv5", "x": 30, "y": 60},
        {"id": "bv6", "x": 0, "y": 60},
        {"id": "bv7", "x": 0, "y": 30},
        {"id": "bv8", "x": 6, "y": 8},
        {"id": "bv9", "x": 8, "y": 2}
      ],
      "edges": [
        {"id": "be0", "fromVertex": "bv0", "toVertex": "bv1", "role": "hem"},
        {"id": "be1", "fromVertex": "bv1", "toVertex": "bv2", "role": "neckline"},
        {"id": "be2", "fromVertex": "bv2", "toVertex": "bv3", "role": "shoulder"},
        {"id": "be3", "fromVertex": "bv3", "toVertex": "bv4", "role": "sleeveCap"},
        {"id": "be4", "fromVertex": "bv4", "toVertex": "bv5", "role": "side"},
        {"id": "be5", "fromVertex": "bv5", "toVertex": "bv6", "role": "hem"},
        {"id": "be6", "fromVertex": "bv6", "toVertex": "bv7", "role": "side"},
        {"id": "be7", "fromVertex": "bv7", "toVertex": "bv8", "role": "sleeveCap"},
        {"id": "be8", "fromVertex": "bv8", "toVertex": "bv9", "role": "shoulder"},
        {"id": "be9", "fromVertex": "bv9", "toVertex": "bv0", "role": "neckline"}
      ],
      "material": {"thickness": 0.02, "stiffness": 0.5, "color": "#2E86AB"}
    },
    {
      "id": "tshirt-sleeve-left",
      "name": "左袖",
      "type": "sleeveLeft",
      "vertices": [
        {"id": "lv0", "x": 0, "y": 0},
        {"id": "lv1", "x": 5, "y": -4},
        {"id": "lv2", "x": 8, "y": 3},
        {"id": "lv3", "x": 4, "y": 35},
        {"id": "lv4", "x": 0, "y": 35}
      ],
      "edges": [
        {"id": "le0", "fromVertex": "lv0", "toVertex": "lv1", "role": "sleeveCap"},
        {"id": "le1", "fromVertex": "lv1", "toVertex": "lv2", "role": "sleeveCap"},
        {"id": "le2", "fromVertex": "lv2", "toVertex": "lv3", "role": "side"},
        {"id": "le3", "fromVertex": "lv3", "toVertex": "lv4", "role": "sleeveCuff"},
        {"id": "le4", "fromVertex": "lv4", "toVertex": "lv0", "role": "side"}
      ],
      "material": {"thickness": 0.02, "stiffness": 0.5, "color": "#2E86AB"}
    },
    {
      "id": "tshirt-sleeve-right",
      "name": "右袖",
      "type": "sleeveRight",
      "vertices": [
        {"id": "rv0", "x": 0, "y": 0},
        {"id": "rv1", "x": -5, "y": -4},
        {"id": "rv2", "x": -8, "y": 3},
        {"id": "rv3", "x": -4, "y": 35},
        {"id": "rv4", "x": 0, "y": 35}
      ],
      "edges": [
        {"id": "re0", "fromVertex": "rv0", "toVertex": "rv1", "role": "sleeveCap"},
        {"id": "re1", "fromVertex": "rv1", "toVertex": "rv2", "role": "sleeveCap"},
        {"id": "re2", "fromVertex": "rv2", "toVertex": "rv3", "role": "side"},
        {"id": "re3", "fromVertex": "rv3", "toVertex": "rv4", "role": "sleeveCuff"},
        {"id": "re4", "fromVertex": "rv4", "toVertex": "rv0", "role": "side"}
      ],
      "material": {"thickness": 0.02, "stiffness": 0.5, "color": "#2E86AB"}
    }
  ],
  "seams": [
    {"pieceA": "tshirt-front", "edgeA": "fe6", "pieceB": "tshirt-back", "edgeB": "be6", "type": "full", "samplingDensity": 20},
    {"pieceA": "tshirt-front", "edgeA": "fe4", "pieceB": "tshirt-back", "edgeB": "be4", "type": "full", "samplingDensity": 20},
    {"pieceA": "tshirt-front", "edgeA": "fe2", "pieceB": "tshirt-back", "edgeB": "be2", "type": "full", "samplingDensity": 15},
    {"pieceA": "tshirt-front", "edgeA": "fe8", "pieceB": "tshirt-back", "edgeB": "be8", "type": "full", "samplingDensity": 15},
    {"pieceA": "tshirt-front", "edgeA": "fe3", "pieceB": "tshirt-sleeve-left", "edgeB": "le0", "type": "full", "samplingDensity": 25},
    {"pieceA": "tshirt-front", "edgeA": "fe3", "pieceB": "tshirt-sleeve-left", "edgeB": "le1", "type": "full", "samplingDensity": 25},
    {"pieceA": "tshirt-back", "edgeA": "be3", "pieceB": "tshirt-sleeve-right", "edgeB": "re0", "type": "full", "samplingDensity": 25},
    {"pieceA": "tshirt-back", "edgeA": "be3", "pieceB": "tshirt-sleeve-right", "edgeB": "re1", "type": "full", "samplingDensity": 25}
  ]
}
```

---

## 七、与 LayoutDocument 的关系

### 7.1 为什么不直接用 LayoutDocument

| 维度 | LayoutDocument | GarmentPattern |
|---|---|---|
| 用途 | 布料排料（布面摆放坐标） | 纸样数据（裁片形状 + 缝合关系 + 人台） |
| 坐标系 | 布料平面（cm，原点在布料左上角） | 纸样自身坐标系（cm，每个裁片独立） |
| 缝合关系 | ❌ 没有 | ✅ 核心字段 |
| 人台参数 | ❌ 没有 | ✅ 核心字段 |
| 语义信息 | 只有 name | 有 type（front/back/sleeve）和 edge role |

### 7.2 转换流程（Swift 侧）

```
用户在 M5b 排料画板设计 LayoutDocument
   ↓ 用户点击"生成成衣"
GarmentDataAdapter（阶段 3 实现）
   ├─ 从 LayoutDocument.pieces 提取 shape.points → Piece.vertices
   ├─ 生成 edges（按顶点顺序自动构建 + role 推断）
   ├─ 构造 seams（从用户显式缝合标注 → Seam 数组）
   └─ 附 mannequin 参数（默认 M 码）
   ↓
GarmentPattern JSON
   ↓ UnityBridge 发送到 Unity
Unity GarmentAssembler 解析 → 两条路线各自处理
```

**关键**：M6 阶段 1（算法 POC）**不从 LayoutDocument 转换**，直接用固定 T 恤 GarmentPattern JSON 作为输入。阶段 3（最小产品版）才做转换。

---

## 八、版本兼容性

| GarmentPattern 版本 | 说明 | 兼容 |
|---|---|---|
| 1.0 | M6 阶段 0 定稿 | Swift & C# 类型同步 |

未来版本演进规则：
- 新增字段 → 加可选字段，旧版本忽略
- 字段重命名 / 删除 → 升级 major 版本

---

## 九、验证清单（阶段 1 POC 前）

- [ ] GarmentPattern JSON Schema 在 http://json-schema.org/ 验证通过
- [ ] Swift 类型 Codable 序列化/反序列化正确
- [ ] C# 类型 Newtonsoft.Json 或 JsonUtility 序列化正确
- [ ] 固定 T 恤样例数据：
  - [ ] 每个 Piece 的 edges 构成闭合多边形（边数 == 顶点数）
  - [ ] 每条 Seam 的 pieceA/edgeA/pieceB/edgeB 都能在 pieces 数组中找到
  - [ ] 每条 Seam 的 edgeA 和 edgeB 长度相近（缝合匹配）
  - [ ] 自环检查：Seam 不会把一条边缝到自己
- [ ] Obi Stitcher 兼容性确认：
  - [ ] GarmentPattern.seams 的数据结构能否映射到 ObiStitcher.AddStitch 的输入
  - [ ] GarmentPattern.pieces 的 vertices 能否被 Unity Mesh 三角化
