using System;
using System.Collections.Generic;
using UnityEngine;

namespace GarmentSimPOC.Data
{
    // GarmentPattern 数据模型（阶段 0 定稿 v1.0）
    // 注意：为兼容 JsonUtility，可空数值字段退化为 float（缺省 0），枚举退化为 string。
    // 与 Swift 侧 Codable 类型的差异已记录在数据模型文档 §三/§四。

    [Serializable]
    public class GarmentPatternData
    {
        public string version;
        public MannequinData mannequin;
        public List<PieceData> pieces;
        public List<SeamData> seams;
    }

    [Serializable]
    public class MannequinData
    {
        public string size;       // "XS","S","M","L","XL","XXL"
        public float heightCm;
        public float bustCm;      // JsonUtility 不支持 nullable，缺省为 0 表示未提供
        public float waistCm;
        public float hipCm;
    }

    [Serializable]
    public class PieceData
    {
        public string id;
        public string name;
        public string type;       // front/back/sleeveLeft/sleeveRight/collar/pocket/other
        public List<VertexData> vertices;
        public List<EdgeData> edges;
        public MaterialData material;
    }

    [Serializable]
    public class VertexData
    {
        public string id;
        public float x;           // cm，裁片自身坐标系
        public float y;           // cm
    }

    [Serializable]
    public class EdgeData
    {
        public string id;
        public string fromVertex;
        public string toVertex;
        public string role;       // side/shoulder/sleeveCuff/sleeveCap/hem/neckline/waistband/other
    }

    [Serializable]
    public class MaterialData
    {
        public float thickness;   // cm
        public float stiffness;   // 0-1
        public string color;      // "#RRGGBB"
    }

    [Serializable]
    public class SeamData
    {
        public string pieceA;
        public string edgeA;
        public string pieceB;
        public string edgeB;
        public string type;           // full/half/blindstitch/lockstitch
        public int samplingDensity;   // 每 cm 采样点数
    }
}
