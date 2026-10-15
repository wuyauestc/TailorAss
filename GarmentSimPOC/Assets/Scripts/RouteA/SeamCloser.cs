using System.Collections.Generic;
using UnityEngine;
using GarmentSimPOC.Data;
using GarmentSimPOC.Core;

namespace GarmentSimPOC.RouteA
{
    /// <summary>
    /// 缝合闭合器：把每条 Seam 的两条边在 3D 中拉拢。
    /// 流程：2D 边采样 → 3D 映射 → 端点距离判定方向（正/反）→ 配对求中点 →
    /// 吸附到各边最近的边界网格顶点 → 平均写入 → 内部顶点 Laplacian 平滑。
    /// </summary>
    public class PieceMesh
    {
        public PieceData piece;
        public Vector3[] verts;                    // cm
        public List<PolygonTriangulator.PointInfo> infos;
        public List<int> tris;
        public Dictionary<int, List<int>> edgeToVertIdx = new Dictionary<int, List<int>>(); // edgeIdx → 顶点索引（有序）
    }

    public static class SeamCloser
    {
        public class Stats
        {
            public float avgGapBefore, maxGapBefore;
            public int seamPairs;
        }

        public static Stats Close(GarmentPatternData pattern, Dictionary<string, PieceMesh> meshes)
        {
            var stats = new Stats();
            if (pattern.seams == null) return stats;

            // 目标位置累积：pieceId → (vertIdx → (sum, count))
            var targets = new Dictionary<string, Dictionary<int, (Vector3 sum, int count)>>();
            float gapSum = 0f, gapMax = 0f; int gapCount = 0;

            foreach (var seam in pattern.seams)
            {
                if (!meshes.TryGetValue(seam.pieceA, out var ma) || !meshes.TryGetValue(seam.pieceB, out var mb)) continue;
                int ea = EdgeIndex(ma.piece, seam.edgeA);
                int eb = EdgeIndex(mb.piece, seam.edgeB);
                if (ea < 0 || eb < 0) continue;

                // 采样数：samplingDensity 为 Obi 粒子密度（点/cm），几何路线夹紧到每条边 ≤32 对
                float lenA = EdgeLength(ma.piece, ea);
                int n = Mathf.Clamp(Mathf.RoundToInt(lenA * Mathf.Min(seam.samplingDensity, 4)), 8, 32);

                var samplesA = SampleEdge3D(ma.piece, ea, n);
                var samplesB = SampleEdge3D(mb.piece, eb, n);

                // 方向判定：端点距离小的配对方式获胜
                float fwd = Vector3.Distance(samplesA[0], samplesB[0]) + Vector3.Distance(samplesA[n - 1], samplesB[n - 1]);
                float rev = Vector3.Distance(samplesA[0], samplesB[n - 1]) + Vector3.Distance(samplesA[n - 1], samplesB[n - 1]);
                if (rev < fwd) samplesB.Reverse();

                for (int i = 0; i < n; i++)
                {
                    float gap = Vector3.Distance(samplesA[i], samplesB[i]);
                    gapSum += gap; gapMax = Mathf.Max(gapMax, gap); gapCount++;
                    Vector3 mid = (samplesA[i] + samplesB[i]) * 0.5f;
                    float t = (float)i / (n - 1);
                    Accumulate(targets, seam.pieceA, NearestOnEdge(ma, ea, t), mid);
                    Accumulate(targets, seam.pieceB, NearestOnEdge(mb, eb, rev < fwd ? 1f - t : t), mid);
                }
                stats.seamPairs += n;
            }

            stats.avgGapBefore = gapCount > 0 ? gapSum / gapCount : 0f;
            stats.maxGapBefore = gapMax;

            // 写入目标位置
            foreach (var kv in targets)
            {
                var m = meshes[kv.Key];
                foreach (var tv in kv.Value)
                    m.verts[tv.Key] = tv.Value.sum / tv.Value.count;
            }

            // 内部顶点 Laplacian 平滑（边界固定）
            foreach (var m in meshes.Values) SmoothInterior(m, 8);
            return stats;
        }

        static void Accumulate(Dictionary<string, Dictionary<int, (Vector3, int)>> targets, string pieceId, int vertIdx, Vector3 pos)
        {
            if (vertIdx < 0) return;
            if (!targets.TryGetValue(pieceId, out var dict)) { dict = new Dictionary<int, (Vector3, int)>(); targets[pieceId] = dict; }
            if (dict.TryGetValue(vertIdx, out var sc)) dict[vertIdx] = (sc.Item1 + pos, sc.Item2 + 1);
            else dict[vertIdx] = (pos, 1);
        }

        static int NearestOnEdge(PieceMesh m, int edgeIdx, float t)
        {
            if (!m.edgeToVertIdx.TryGetValue(edgeIdx, out var list) || list.Count == 0) return -1;
            // 列表按细分顺序（t 递增）排列
            int i = Mathf.Clamp(Mathf.RoundToInt(t * (list.Count - 1)), 0, list.Count - 1);
            return list[i];
        }

        static List<Vector3> SampleEdge3D(PieceData piece, int edgeIdx, int n)
        {
            var vById = new Dictionary<string, VertexData>();
            foreach (var v in piece.vertices) vById[v.id] = v;
            var e = piece.edges[edgeIdx];
            Vector2 a = new Vector2(vById[e.fromVertex].x, vById[e.fromVertex].y);
            Vector2 b = new Vector2(vById[e.toVertex].x, vById[e.toVertex].y);
            var list = new List<Vector3>(n);
            for (int i = 0; i < n; i++)
            {
                float t = (float)i / (n - 1);
                Vector2 p = Vector2.Lerp(a, b, t); // 必须带 2D 坐标：hem/side 等 role 的映射依赖它
                var info = new PolygonTriangulator.PointInfo { p = p, edgeIndex = edgeIdx, edgeT = t };
                list.Add(GarmentMapper.MapSingle(piece, info));
            }
            return list;
        }

        static int EdgeIndex(PieceData p, string edgeId)
        {
            for (int i = 0; i < p.edges.Count; i++) if (p.edges[i].id == edgeId) return i;
            return -1;
        }

        static float EdgeLength(PieceData p, int edgeIdx)
        {
            var v = new Dictionary<string, VertexData>();
            foreach (var x in p.vertices) v[x.id] = x;
            var e = p.edges[edgeIdx];
            if (v.TryGetValue(e.fromVertex, out var a) && v.TryGetValue(e.toVertex, out var b))
                return Vector2.Distance(new Vector2(a.x, a.y), new Vector2(b.x, b.y));
            return 10f;
        }

        /// <summary>Laplacian 平滑：只动内部点（edgeIndex==-1），边界保持映射/缝合结果。</summary>
        static void SmoothInterior(PieceMesh m, int iterations)
        {
            var neighbors = new HashSet<int>[m.verts.Length];
            for (int i = 0; i < neighbors.Length; i++) neighbors[i] = new HashSet<int>();
            for (int t = 0; t < m.tris.Count; t += 3)
            {
                int a = m.tris[t], b = m.tris[t + 1], c = m.tris[t + 2];
                neighbors[a].Add(b); neighbors[a].Add(c);
                neighbors[b].Add(a); neighbors[b].Add(c);
                neighbors[c].Add(a); neighbors[c].Add(b);
            }
            for (int it = 0; it < iterations; it++)
            {
                var next = (Vector3[])m.verts.Clone();
                for (int i = 0; i < m.verts.Length; i++)
                {
                    if (m.infos[i].edgeIndex >= 0) continue; // 边界固定
                    if (neighbors[i].Count == 0) continue;
                    Vector3 sum = Vector3.zero;
                    foreach (var nb in neighbors[i]) sum += m.verts[nb];
                    next[i] = Vector3.Lerp(m.verts[i], sum / neighbors[i].Count, 0.5f);
                }
                m.verts = next;
            }
        }
    }
}
