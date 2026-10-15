using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using UnityEngine;
using GarmentSimPOC.Data;
using GarmentSimPOC.Core;

namespace GarmentSimPOC.RouteA
{
    /// <summary>
    /// 路线 A 装配器：GarmentPattern → 校验 → 三角化 → 3D 映射 → 缝合闭合 → Unity Mesh。
    /// </summary>
    public static class GeometricGarmentAssembler
    {
        public class Result
        {
            public GameObject root;
            public List<GarmentPatternValidator.Issue> issues;
            public int totalVerts, totalTris;
            public long elapsedMs;
            public SeamCloser.Stats seamStats;
            public string report;
        }

        const float CmToM = 0.01f;

        public static Result Assemble(GarmentPatternData pattern, Material clothMaterial, bool flatLayout = false)
        {
            var sw = Stopwatch.StartNew();
            var result = new Result { issues = GarmentPatternValidator.Validate(pattern) };
            if (GarmentPatternValidator.HasError(result.issues))
            {
                result.report = "校验失败，未生成网格。\n" + GarmentPatternValidator.FormatReport(result.issues);
                return result;
            }

            var root = new GameObject(flatLayout ? "GarmentFlat" : "Garment3D");
            var meshes = new Dictionary<string, PieceMesh>();

            foreach (var piece in pattern.pieces)
            {
                var poly = OrderedPolygon(piece);
                var tri = new PolygonTriangulator();
                tri.Triangulate(poly, 1.5f, 2.0f);

                var pm = new PieceMesh { piece = piece, infos = tri.points, tris = tri.triangles };
                pm.verts = GarmentMapper.MapPiece(piece, tri.points);

                // 记录每条边的有序边界顶点索引（缝合吸附用）
                for (int i = 0; i < tri.points.Count; i++)
                {
                    int e = tri.points[i].edgeIndex;
                    if (e < 0) continue;
                    if (!pm.edgeToVertIdx.TryGetValue(e, out var list)) { list = new List<int>(); pm.edgeToVertIdx[e] = list; }
                    list.Add(i);
                }
                meshes[piece.id] = pm;
            }

            SeamCloser.Stats seamStats = null;
            if (!flatLayout)
                seamStats = SeamCloser.Close(pattern, meshes);
            result.seamStats = seamStats;

#if UNITY_EDITOR
            var diagSb = new StringBuilder();
            if (!flatLayout)
            {
                // OBJ 转储 + 逐裁片包围盒诊断（定位扇形坍缩/袖子形状问题）
                string outDir = Path.Combine(Directory.GetCurrentDirectory(), "POCOutput");
                Directory.CreateDirectory(outDir);
                ObjDump.Dump(Path.Combine(outDir, "garment_routeA.obj"), meshes);
                foreach (var kv in meshes)
                {
                    var pm = kv.Value;
                    var mn = new Vector3(float.MaxValue, float.MaxValue, float.MaxValue);
                    var mx = new Vector3(float.MinValue, float.MinValue, float.MinValue);
                    foreach (var v in pm.verts) { mn = Vector3.Min(mn, v); mx = Vector3.Max(mx, v); }
                    diagSb.AppendLine($"[{pm.piece.id}] verts={pm.verts.Length} tris={pm.tris.Count / 3} " +
                        $"bbox=({mn.x:F1},{mn.y:F1},{mn.z:F1})~({mx.x:F1},{mx.y:F1},{mx.z:F1})");
                }
            }
#endif

            // 生成 Unity Mesh
            float flatX = 0f;
            foreach (var kv in meshes)
            {
                var pm = kv.Value;
                var mesh = new Mesh { name = pm.piece.name };
                var v3 = new Vector3[pm.verts.Length];
                var uv = new Vector2[pm.verts.Length];
                for (int i = 0; i < pm.verts.Length; i++)
                {
                    if (flatLayout)
                    {
                        var p2 = pm.infos[i].p;
                        v3[i] = new Vector3((p2.x + flatX) * CmToM, p2.y * CmToM, 0f);
                    }
                    else v3[i] = pm.verts[i] * CmToM;
                    uv[i] = new Vector2(pm.infos[i].p.x * 0.01f, pm.infos[i].p.y * 0.01f);
                }
                if (flatLayout) flatX += 55f;
                mesh.SetVertices(v3);
                mesh.SetUVs(0, uv);
                mesh.SetTriangles(pm.tris, 0);
                mesh.RecalculateNormals();
                mesh.RecalculateBounds();

                var go = new GameObject(pm.piece.name + $" ({pm.piece.id})");
                go.transform.SetParent(root.transform, false);
                go.AddComponent<MeshFilter>().sharedMesh = mesh;
                var mr = go.AddComponent<MeshRenderer>();
                mr.sharedMaterial = MakePieceMaterial(clothMaterial, pm.piece.material);
                result.totalVerts += pm.verts.Length;
                result.totalTris += pm.tris.Count / 3;
            }

            sw.Stop();
            result.elapsedMs = sw.ElapsedMilliseconds;
            result.root = root;
            result.report = BuildReport(result, pattern);
#if UNITY_EDITOR
            result.report += diagSb.ToString();
#endif
            return result;
        }

        static Material MakePieceMaterial(Material baseMat, MaterialData md)
        {
            var mat = new Material(baseMat);
            if (md != null && !string.IsNullOrEmpty(md.color) && ColorUtility.TryParseHtmlString(md.color, out var c))
                mat.color = c;
            return mat;
        }

        /// <summary>按边链顺序重建多边形顶点序列。</summary>
        static List<Vector2> OrderedPolygon(PieceData piece)
        {
            var vById = new Dictionary<string, VertexData>();
            foreach (var v in piece.vertices) vById[v.id] = v;
            var list = new List<Vector2>();
            foreach (var e in piece.edges)
                if (vById.TryGetValue(e.fromVertex, out var v)) list.Add(new Vector2(v.x, v.y));
            return list;
        }

        static string BuildReport(Result r, GarmentPatternData pattern)
        {
            var sb = new StringBuilder();
            sb.AppendLine("=== 路线 A 装配报告 ===");
            sb.Append(GarmentPatternValidator.FormatReport(r.issues));
            sb.AppendLine($"裁片数: {pattern.pieces.Count}, 缝合关系: {pattern.seams?.Count ?? 0}");
            sb.AppendLine($"总顶点: {r.totalVerts}, 总三角形: {r.totalTris}");
            sb.AppendLine($"装配耗时: {r.elapsedMs} ms");
            if (r.seamStats != null)
            {
                sb.AppendLine($"缝合采样对: {r.seamStats.seamPairs}");
                sb.AppendLine($"闭合前缝隙: 平均 {r.seamStats.avgGapBefore:F2}cm, 最大 {r.seamStats.maxGapBefore:F2}cm");
            }
            return sb.ToString();
        }
    }
}
