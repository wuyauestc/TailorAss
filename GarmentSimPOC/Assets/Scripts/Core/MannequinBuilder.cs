using System.Collections.Generic;
using UnityEngine;

namespace GarmentSimPOC.Core
{
    /// <summary>
    /// 程序化生成 M 码人台网格（不依赖 Asset Store，尺寸与 BodyProfile 完全一致）。
    /// 组成：躯干车削体 + 双臂（胶囊）+ 颈部 + 头部 + 展示底座。
    /// 单位：输入 cm，输出 mesh 为米（×0.01）。
    /// </summary>
    public static class MannequinBuilder
    {
        const float S = 0.01f; // cm → m

        public static GameObject Build(Material mat)
        {
            var root = new GameObject("Mannequin");
            var meshes = new List<Mesh>();

            meshes.Add(BuildTorso());
            meshes.Add(BuildArm(+1));
            meshes.Add(BuildArm(-1));
            meshes.Add(BuildNeck());
            meshes.Add(BuildHead());
            meshes.Add(BuildStand());

            foreach (var m in meshes)
            {
                var go = new GameObject(m.name);
                go.transform.SetParent(root.transform, false);
                var mf = go.AddComponent<MeshFilter>();
                mf.sharedMesh = m;
                var mr = go.AddComponent<MeshRenderer>();
                mr.sharedMaterial = mat;
            }
            return root;
        }

        static Mesh BuildTorso()
        {
            // 车削：从 h=80 到 h=150，每 2cm 一环，每环 48 段
            var verts = new List<Vector3>();
            var tris = new List<int>();
            const int seg = 48;
            for (float h = 80f; h <= 150.01f; h += 2f)
            {
                BodyProfile.TorsoEllipse(h, false, out float a, out float b);
                for (int i = 0; i < seg; i++)
                {
                    float th = (float)i / seg * Mathf.PI * 2f;
                    verts.Add(new Vector3(a * Mathf.Sin(th) * S, h * S, b * Mathf.Cos(th) * S));
                }
            }
            int rings = verts.Count / seg;
            for (int r = 0; r < rings - 1; r++)
                for (int i = 0; i < seg; i++)
                {
                    int i2 = (i + 1) % seg;
                    int a0 = r * seg + i, a1 = r * seg + i2, b0 = (r + 1) * seg + i, b1 = (r + 1) * seg + i2;
                    tris.Add(a0); tris.Add(b0); tris.Add(b1);
                    tris.Add(a0); tris.Add(b1); tris.Add(a1);
                }
            // 底面封口
            int center = verts.Count;
            BodyProfile.TorsoEllipse(80f, false, out float ba, out float bb);
            verts.Add(new Vector3(0f, 80f * S, 0f));
            for (int i = 0; i < seg; i++)
            {
                int i2 = (i + 1) % seg;
                tris.Add(center); tris.Add(i2); tris.Add(i);
            }
            return Finish("Torso", verts, tris);
        }

        static Mesh BuildArm(int side)
        {
            // 从肩关节 (±17,140,0) 沿微外张方向下垂的胶囊
            Vector3 shoulder = new Vector3(17f * side, 140f, 0f);
            Vector3 dir = new Vector3(0.22f * side, -0.975f, 0f).normalized;
            return BuildCapsule(shoulder, dir, 55f, 4.3f, "Arm" + (side > 0 ? "L" : "R"));
        }

        static Mesh BuildNeck()
        {
            Vector3 baseP = new Vector3(0f, 146f, 0f);
            return BuildCapsule(baseP, Vector3.up, 10f, 5.2f, "Neck");
        }

        static Mesh BuildHead()
        {
            // 简单椭球头
            var verts = new List<Vector3>();
            var tris = new List<int>();
            const int lat = 12, lon = 16;
            Vector3 c = new Vector3(0f, 158f, 0f);
            for (int i = 0; i <= lat; i++)
            {
                float phi = (float)i / lat * Mathf.PI;
                for (int j = 0; j < lon; j++)
                {
                    float th = (float)j / lon * Mathf.PI * 2f;
                    verts.Add((c + new Vector3(8.5f * Mathf.Sin(phi) * Mathf.Sin(th),
                                               10.5f * Mathf.Cos(phi),
                                               8.0f * Mathf.Sin(phi) * Mathf.Cos(th))) * S);
                }
            }
            for (int i = 0; i < lat; i++)
                for (int j = 0; j < lon; j++)
                {
                    int j2 = (j + 1) % lon;
                    int a0 = i * lon + j, a1 = i * lon + j2, b0 = (i + 1) * lon + j, b1 = (i + 1) * lon + j2;
                    tris.Add(a0); tris.Add(b1); tris.Add(b0);
                    tris.Add(a0); tris.Add(a1); tris.Add(b1);
                }
            return Finish("Head", verts, tris);
        }

        static Mesh BuildStand()
        {
            var verts = new List<Vector3>();
            var tris = new List<int>();
            // 立柱 + 底盘
            AppendCylinder(verts, tris, new Vector3(0, 0, 0), new Vector3(0, 80f, 0), 1.2f, 10);
            AppendCylinder(verts, tris, new Vector3(0, 0, 0), new Vector3(0, 2f, 0), 22f, 24);
            return Finish("Stand", verts, tris);
        }

        static Mesh BuildCapsule(Vector3 start, Vector3 dir, float len, float r, string name)
        {
            var verts = new List<Vector3>();
            var tris = new List<int>();
            Vector3 axis = dir.normalized;
            Vector3 u = Vector3.Cross(axis, Mathf.Abs(axis.y) > 0.9f ? Vector3.right : Vector3.up).normalized;
            Vector3 v = Vector3.Cross(axis, u);
            const int seg = 16, rings = 6;
            Vector3 end = start + axis * len;
            for (int k = 0; k <= rings; k++)
            {
                Vector3 c = Vector3.Lerp(start, end, (float)k / rings);
                float rr = r * Mathf.Lerp(1f, 0.75f, (float)k / rings); // 向手腕渐细
                for (int i = 0; i < seg; i++)
                {
                    float th = (float)i / seg * Mathf.PI * 2f;
                    verts.Add((c + (u * Mathf.Cos(th) + v * Mathf.Sin(th)) * rr) * S);
                }
            }
            for (int k = 0; k < rings; k++)
                for (int i = 0; i < seg; i++)
                {
                    int i2 = (i + 1) % seg;
                    int a0 = k * seg + i, a1 = k * seg + i2, b0 = (k + 1) * seg + i, b1 = (k + 1) * seg + i2;
                    tris.Add(a0); tris.Add(b0); tris.Add(b1);
                    tris.Add(a0); tris.Add(b1); tris.Add(a1);
                }
            return Finish(name, verts, tris);
        }

        static void AppendCylinder(List<Vector3> verts, List<int> tris, Vector3 from, Vector3 to, float r, int seg)
        {
            Vector3 axis = (to - from).normalized;
            Vector3 u = Vector3.Cross(axis, Vector3.right);
            if (u.sqrMagnitude < 0.01f) u = Vector3.Cross(axis, Vector3.forward);
            u.Normalize();
            Vector3 v = Vector3.Cross(axis, u);
            int baseIdx = verts.Count;
            foreach (var c in new[] { from, to })
                for (int i = 0; i < seg; i++)
                {
                    float th = (float)i / seg * Mathf.PI * 2f;
                    verts.Add((c + (u * Mathf.Cos(th) + v * Mathf.Sin(th)) * r) * S);
                }
            for (int i = 0; i < seg; i++)
            {
                int i2 = (i + 1) % seg;
                tris.Add(baseIdx + i); tris.Add(baseIdx + seg + i); tris.Add(baseIdx + seg + i2);
                tris.Add(baseIdx + i); tris.Add(baseIdx + seg + i2); tris.Add(baseIdx + i2);
            }
        }

        static Mesh Finish(string name, List<Vector3> verts, List<int> tris)
        {
            var m = new Mesh { name = name };
            m.SetVertices(verts);
            m.SetTriangles(tris, 0);
            m.RecalculateNormals();
            m.RecalculateBounds();
            return m;
        }
    }
}
