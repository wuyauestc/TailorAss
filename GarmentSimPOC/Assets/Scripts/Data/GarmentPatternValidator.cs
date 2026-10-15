using System.Collections.Generic;
using System.Text;
using UnityEngine;

namespace GarmentSimPOC.Data
{
    /// <summary>
    /// GarmentPattern 校验器。实现数据模型文档 §九 验证清单：
    /// 1. 每个 Piece 的 edges 构成闭合多边形（边数 == 顶点数，且链式引用一致）
    /// 2. 每条 Seam 的 pieceA/edgeA/pieceB/edgeB 都能解析到
    /// 3. 缝合两边长度差 > 10% 时给警告（会影响缝合质量）
    /// 4. 禁止把一条边缝到自己（pieceA==pieceB 且 edgeA==edgeB）
    /// 5. 顶点数 >= 3
    /// </summary>
    public static class GarmentPatternValidator
    {
        public class Issue
        {
            public bool isError;
            public string message;
            public override string ToString() => (isError ? "[ERROR] " : "[WARN] ") + message;
        }

        public static List<Issue> Validate(GarmentPatternData pattern)
        {
            var issues = new List<Issue>();
            if (pattern == null)
            {
                issues.Add(new Issue { isError = true, message = "Pattern 为空（JSON 解析失败）" });
                return issues;
            }
            if (string.IsNullOrEmpty(pattern.version))
                issues.Add(new Issue { isError = true, message = "缺少 version 字段" });
            if (pattern.mannequin == null)
                issues.Add(new Issue { isError = true, message = "缺少 mannequin 字段" });
            if (pattern.pieces == null || pattern.pieces.Count == 0)
            {
                issues.Add(new Issue { isError = true, message = "pieces 为空" });
                return issues;
            }

            var pieceById = new Dictionary<string, PieceData>();
            foreach (var p in pattern.pieces)
            {
                if (string.IsNullOrEmpty(p.id))
                {
                    issues.Add(new Issue { isError = true, message = "存在无 id 的裁片" });
                    continue;
                }
                if (pieceById.ContainsKey(p.id))
                    issues.Add(new Issue { isError = true, message = $"裁片 id 重复: {p.id}" });
                pieceById[p.id] = p;
            }

            var edgeById = new Dictionary<string, (PieceData piece, EdgeData edge, float length)>();
            foreach (var p in pattern.pieces)
            {
                ValidatePiece(p, issues);
                if (p.vertices == null || p.edges == null) continue;

                var vById = new Dictionary<string, VertexData>();
                foreach (var v in p.vertices) vById[v.id] = v;
                foreach (var e in p.edges)
                {
                    if (string.IsNullOrEmpty(e.id)) continue;
                    float len = 0f;
                    if (vById.TryGetValue(e.fromVertex, out var a) && vById.TryGetValue(e.toVertex, out var b))
                        len = Vector2.Distance(new Vector2(a.x, a.y), new Vector2(b.x, b.y));
                    edgeById[$"{p.id}/{e.id}"] = (p, e, len);
                }
            }

            if (pattern.seams != null)
            {
                int idx = 0;
                foreach (var s in pattern.seams)
                {
                    idx++;
                    bool okA = edgeById.TryGetValue($"{s.pieceA}/{s.edgeA}", out var ea);
                    bool okB = edgeById.TryGetValue($"{s.pieceB}/{s.edgeB}", out var eb);
                    if (!okA)
                        issues.Add(new Issue { isError = true, message = $"Seam#{idx}: 找不到 {s.pieceA}/{s.edgeA}" });
                    if (!okB)
                        issues.Add(new Issue { isError = true, message = $"Seam#{idx}: 找不到 {s.pieceB}/{s.edgeB}" });
                    if (!okA || !okB) continue;

                    if (s.pieceA == s.pieceB && s.edgeA == s.edgeB)
                        issues.Add(new Issue { isError = true, message = $"Seam#{idx}: 边 {s.edgeA} 缝到自己（自环）" });

                    float diff = Mathf.Abs(ea.length - eb.length);
                    float maxLen = Mathf.Max(ea.length, eb.length);
                    if (maxLen > 0f && diff / maxLen > 0.10f)
                        issues.Add(new Issue
                        {
                            isError = false,
                            message = $"Seam#{idx}: 缝合边长度差 {diff:F1}cm（{ea.length:F1} vs {eb.length:F1}，{diff / maxLen:P0}），可能影响缝合质量"
                        });
                }
            }
            return issues;
        }

        static void ValidatePiece(PieceData p, List<Issue> issues)
        {
            if (p.vertices == null || p.vertices.Count < 3)
            {
                issues.Add(new Issue { isError = true, message = $"裁片 {p.id} 顶点数 < 3" });
                return;
            }
            if (p.edges == null || p.edges.Count != p.vertices.Count)
            {
                issues.Add(new Issue { isError = true, message = $"裁片 {p.id} 边数({p.edges?.Count}) != 顶点数({p.vertices.Count})，不闭合" });
                return;
            }
            // 链式一致性：edges[i].toVertex 应等于 edges[(i+1)%n].fromVertex
            var vIds = new HashSet<string>();
            foreach (var v in p.vertices) vIds.Add(v.id);
            int n = p.edges.Count;
            for (int i = 0; i < n; i++)
            {
                var cur = p.edges[i];
                var nxt = p.edges[(i + 1) % n];
                if (!vIds.Contains(cur.fromVertex) || !vIds.Contains(cur.toVertex))
                    issues.Add(new Issue { isError = true, message = $"裁片 {p.id} 边 {cur.id} 引用了不存在的顶点" });
                else if (cur.toVertex != nxt.fromVertex)
                    issues.Add(new Issue { isError = true, message = $"裁片 {p.id} 边链断裂: {cur.id}.toVertex={cur.toVertex} != {nxt.id}.fromVertex={nxt.fromVertex}" });
            }
        }

        public static string FormatReport(List<Issue> issues)
        {
            var sb = new StringBuilder();
            int errors = 0, warnings = 0;
            foreach (var i in issues) { if (i.isError) errors++; else warnings++; }
            sb.AppendLine($"校验结果: {errors} 个错误, {warnings} 个警告");
            foreach (var i in issues) sb.AppendLine(i.ToString());
            return sb.ToString();
        }

        public static bool HasError(List<Issue> issues)
        {
            foreach (var i in issues) if (i.isError) return true;
            return false;
        }
    }
}
