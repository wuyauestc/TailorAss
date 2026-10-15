using System.Collections.Generic;
using UnityEngine;

namespace GarmentSimPOC.Core
{
    /// <summary>
    /// 2D 多边形三角化（耳切法）+ 边界细分 + 内心加密。
    /// 输出点带有来源信息（属于哪条边界边、参数 t，或内部点），供 3D 映射使用。
    /// </summary>
    public class PolygonTriangulator
    {
        public class PointInfo
        {
            public Vector2 p;
            public int edgeIndex = -1;   // -1 = 内部点
            public float edgeT;          // 在边上的参数 0..1
        }

        public List<PointInfo> points = new List<PointInfo>();
        public List<int> triangles = new List<int>();

        /// <summary>
        /// poly: 闭合多边形顶点（按边链顺序）。maxEdge: 边界细分最大边长(cm)。
        /// refineEdge: 内部加密触发边长(cm)，超过则在重心分裂（最多 2 轮）。
        /// </summary>
        public void Triangulate(List<Vector2> poly, float maxEdge, float refineEdge)
        {
            points.Clear();
            triangles.Clear();

            // 1. 边界细分：把每条边细分为 <= maxEdge 的段
            int n = poly.Count;
            for (int e = 0; e < n; e++)
            {
                Vector2 a = poly[e];
                Vector2 b = poly[(e + 1) % n];
                float len = Vector2.Distance(a, b);
                int segs = Mathf.Max(1, Mathf.CeilToInt(len / maxEdge));
                for (int s = 0; s < segs; s++)
                {
                    float t = (float)s / segs;
                    points.Add(new PointInfo { p = Vector2.Lerp(a, b, t), edgeIndex = e, edgeT = t });
                }
            }

            // 2. 耳切三角化（基于细分后的边界点索引环）
            var ring = new List<int>();
            for (int i = 0; i < points.Count; i++) ring.Add(i);
            EarClip(ring);

            // 3. 内部加密：对大三角形在重心分裂（简单实现，两轮）
            for (int pass = 0; pass < 2; pass++)
            {
                if (!RefineByCentroid(refineEdge)) break;
            }

            // 4. 2D Laplacian 平滑内部点，改善三角形形状（避免耳切产生的狭长片）
            Smooth2D(4);
        }

        void EarClip(List<int> ring)
        {
            // 按质量选耳：score = 4√3·A / Σe²，接近 1 表示等边，越小表示越瘦长。
            // 不再从 i=0 取第一个合法耳，否则整片退化成扇形（最大度数可到 400+）。
            int guard = 0;
            while (ring.Count > 3 && guard++ < 10000)
            {
                float bestScore = -1f;
                int bestIdx = -1;
                for (int i = 0; i < ring.Count; i++)
                {
                    int i0 = ring[(i - 1 + ring.Count) % ring.Count];
                    int i1 = ring[i];
                    int i2 = ring[(i + 1) % ring.Count];
                    Vector2 a = points[i0].p, b = points[i1].p, c = points[i2].p;
                    float cr = Cross(b - a, c - b);
                    if (cr <= 0f) continue; // 凹角或非凸耳
                    bool contains = false;
                    for (int j = 0; j < ring.Count; j++)
                    {
                        int ij = ring[j];
                        if (ij == i0 || ij == i1 || ij == i2) continue;
                        if (PointInTriangle(points[ij].p, a, b, c)) { contains = true; break; }
                    }
                    if (contains) continue;
                    float e2 = (b - a).sqrMagnitude + (c - b).sqrMagnitude + (a - c).sqrMagnitude;
                    float score = 4f * Mathf.Sqrt(3f) * (cr * 0.5f) / e2;
                    if (score > bestScore) { bestScore = score; bestIdx = i; }
                }
                if (bestIdx < 0) break; // 数值退化时放弃，剩余扇形处理
                int bi0 = ring[(bestIdx - 1 + ring.Count) % ring.Count];
                int bi1 = ring[bestIdx];
                int bi2 = ring[(bestIdx + 1) % ring.Count];
                triangles.Add(bi0); triangles.Add(bi1); triangles.Add(bi2);
                ring.RemoveAt(bestIdx);
            }
            if (ring.Count == 3)
            {
                triangles.Add(ring[0]); triangles.Add(ring[1]); triangles.Add(ring[2]);
            }
            else if (ring.Count > 3)
            {
                for (int i = 1; i < ring.Count - 1; i++)
                {
                    triangles.Add(ring[0]); triangles.Add(ring[i]); triangles.Add(ring[i + 1]);
                }
            }
        }

        bool RefineByCentroid(float maxEdge)
        {
            var newTris = new List<int>();
            bool any = false;
            for (int t = 0; t < triangles.Count; t += 3)
            {
                int i0 = triangles[t], i1 = triangles[t + 1], i2 = triangles[t + 2];
                float d01 = Vector2.Distance(points[i0].p, points[i1].p);
                float d12 = Vector2.Distance(points[i1].p, points[i2].p);
                float d20 = Vector2.Distance(points[i2].p, points[i0].p);
                if (Mathf.Max(d01, Mathf.Max(d12, d20)) > maxEdge)
                {
                    var c = (points[i0].p + points[i1].p + points[i2].p) / 3f;
                    int ic = points.Count;
                    points.Add(new PointInfo { p = c, edgeIndex = -1 });
                    newTris.Add(i0); newTris.Add(i1); newTris.Add(ic);
                    newTris.Add(i1); newTris.Add(i2); newTris.Add(ic);
                    newTris.Add(i2); newTris.Add(i0); newTris.Add(ic);
                    any = true;
                }
                else
                {
                    newTris.Add(i0); newTris.Add(i1); newTris.Add(i2);
                }
            }
            triangles = newTris;
            return any;
        }

        void Smooth2D(int iterations)
        {
            var neighbors = new HashSet<int>[points.Count];
            for (int i = 0; i < neighbors.Length; i++) neighbors[i] = new HashSet<int>();
            for (int t = 0; t < triangles.Count; t += 3)
            {
                int a = triangles[t], b = triangles[t + 1], c = triangles[t + 2];
                neighbors[a].Add(b); neighbors[a].Add(c);
                neighbors[b].Add(a); neighbors[b].Add(c);
                neighbors[c].Add(a); neighbors[c].Add(b);
            }
            for (int it = 0; it < iterations; it++)
            {
                var moved = new Vector2[points.Count];
                for (int i = 0; i < points.Count; i++)
                {
                    if (points[i].edgeIndex >= 0 || neighbors[i].Count == 0)
                    {
                        moved[i] = points[i].p;
                        continue;
                    }
                    Vector2 sum = Vector2.zero;
                    foreach (var nb in neighbors[i]) sum += points[nb].p;
                    moved[i] = Vector2.Lerp(points[i].p, sum / neighbors[i].Count, 0.5f);
                }
                for (int i = 0; i < points.Count; i++) points[i].p = moved[i];
            }
        }

        static float Cross(Vector2 u, Vector2 v) => u.x * v.y - u.y * v.x;

        static bool PointInTriangle(Vector2 p, Vector2 a, Vector2 b, Vector2 c)
        {
            float d1 = Cross(b - a, p - a);
            float d2 = Cross(c - b, p - b);
            float d3 = Cross(a - c, p - c);
            bool hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0);
            bool hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0);
            return !(hasNeg && hasPos);
        }
    }
}
