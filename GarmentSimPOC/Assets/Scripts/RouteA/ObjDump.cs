using System.Collections.Generic;
using System.IO;
using System.Text;
using UnityEngine;

namespace GarmentSimPOC.RouteA
{
    /// <summary>
    /// 把装配后的裁片网格转储为 OBJ（单位 cm），供离线数值分析（扇形顶点/坍缩/退化三角形检测）。
    /// 仅 Editor 调试用。
    /// </summary>
    public static class ObjDump
    {
        public static void Dump(string path, Dictionary<string, PieceMesh> meshes)
        {
            var sb = new StringBuilder();
            int offset = 1; // OBJ 索引从 1 开始
            foreach (var kv in meshes)
            {
                var pm = kv.Value;
                sb.AppendLine("o " + pm.piece.id);
                for (int i = 0; i < pm.verts.Length; i++)
                {
                    var v = pm.verts[i];
                    sb.AppendLine(string.Format("v {0:F3} {1:F3} {2:F3}", v.x, v.y, v.z));
                }
                for (int t = 0; t < pm.tris.Count; t += 3)
                    sb.AppendLine(string.Format("f {0} {1} {2}",
                        pm.tris[t] + offset, pm.tris[t + 1] + offset, pm.tris[t + 2] + offset));
                offset += pm.verts.Length;
            }
            File.WriteAllText(path, sb.ToString());
        }
    }
}
