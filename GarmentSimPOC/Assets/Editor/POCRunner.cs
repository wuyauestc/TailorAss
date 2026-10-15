using System.IO;
using System.Text;
using UnityEngine;
using UnityEditor;
using UnityEditor.SceneManagement;
using GarmentSimPOC.Core;
using GarmentSimPOC.Data;
using GarmentSimPOC.RouteA;

namespace GarmentSimPOC.EditorTools
{
    /// <summary>
    /// Batchmode POC 执行器：搭建场景 → 装配 → 多视角截图 → 写报告 → 保存场景。
    /// 命令：Unity -batchmode -projectPath ... -executeMethod GarmentSimPOC.EditorTools.POCRunner.Run
    /// 输出：POCOutput/ 下的截图 PNG + report.txt
    /// </summary>
    public static class POCRunner
    {
        static string OutDir => Path.Combine(Directory.GetCurrentDirectory(), "POCOutput");

        public static void Run()
        {
            Directory.CreateDirectory(OutDir);
            var report = new StringBuilder();
            report.AppendLine("# GarmentSimPOC 阶段 1 运行报告（自动生成）\n");

            // 1. 新场景
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            // 2. 灯光
            var lgo = new GameObject("Key Light");
            var key = lgo.AddComponent<Light>();
            key.type = LightType.Directional;
            key.intensity = 1.15f;
            lgo.transform.rotation = Quaternion.Euler(50f, -35f, 0f);
            var fgo = new GameObject("Fill Light");
            var fill = fgo.AddComponent<Light>();
            fill.type = LightType.Directional;
            fill.intensity = 0.4f;
            fgo.transform.rotation = Quaternion.Euler(20f, 150f, 0f);
            RenderSettings.ambientLight = new Color(0.5f, 0.5f, 0.53f);

            // 3. 相机
            var camGo = new GameObject("Main Camera");
            camGo.tag = "MainCamera";
            var cam = camGo.AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.18f, 0.19f, 0.22f);

            // 4. 材质
            var clothMat = new Material(Shader.Find("Universal Render Pipeline/Lit"));
            clothMat.SetFloat("_Cull", (float)UnityEngine.Rendering.CullMode.Off);
            clothMat.SetFloat("_Smoothness", 0.25f);
            var mannequinMat = new Material(Shader.Find("Universal Render Pipeline/Lit"));
            mannequinMat.color = new Color(0.82f, 0.80f, 0.78f);

            // 5. 人台
            var mannequin = MannequinBuilder.Build(mannequinMat);
            report.AppendLine("人台：程序化生成（躯干/双臂/颈/头/底座）\n");

            // 6. 平铺布局截图（2D 三角化验证）
            var pattern = LoadSample(report);
            if (pattern != null)
            {
                var flat = GeometricGarmentAssembler.Assemble(pattern, clothMat, flatLayout: true);
                mannequin.SetActive(false);
                Capture(cam, "01_flat_layout.png",
                    new Vector3(1.0f, 0.3f, 2.2f), new Vector3(1.0f, 0.3f, 0f), 60f);
                Object.DestroyImmediate(flat.root);
                mannequin.SetActive(true);

                // 7. 路线 A 装配 + 多视角截图
                var res = GeometricGarmentAssembler.Assemble(pattern, clothMat);
                report.AppendLine(res.report);

                Capture(cam, "02_front.png", new Vector3(0f, 1.25f, 2.3f), new Vector3(0f, 1.18f, 0f), 45f);
                Capture(cam, "03_back.png", new Vector3(0f, 1.25f, -2.3f), new Vector3(0f, 1.18f, 0f), 45f);
                Capture(cam, "04_side_left.png", new Vector3(2.3f, 1.25f, 0f), new Vector3(0f, 1.18f, 0f), 45f);
                Capture(cam, "05_three_quarter.png", new Vector3(1.9f, 1.5f, 2.1f), new Vector3(0f, 1.15f, 0f), 42f);
                Capture(cam, "06_neck_detail.png", new Vector3(0f, 1.55f, 1.0f), new Vector3(0f, 1.42f, 0f), 40f);
                Capture(cam, "08_sleeve_detail.png", new Vector3(1.35f, 1.35f, 0.9f), new Vector3(0.24f, 1.25f, 0f), 38f);

                // 8. 隐藏人台看内部结构
                mannequin.SetActive(false);
                Capture(cam, "07_garment_only.png", new Vector3(0f, 1.25f, 2.3f), new Vector3(0f, 1.18f, 0f), 45f);
                mannequin.SetActive(true);

                // 9. 保存场景供交互查看
                EditorSceneManager.SaveScene(scene, "Assets/Scenes/POC.unity");
                report.AppendLine("\n场景已保存: Assets/Scenes/POC.unity");
            }

            File.WriteAllText(Path.Combine(OutDir, "report.txt"), report.ToString());
            Debug.Log(report.ToString());
            EditorApplication.Exit(0);
        }

        static GarmentPatternData LoadSample(StringBuilder report)
        {
            string path = Path.Combine(Application.streamingAssetsPath, "tshirt_sample.json");
            if (!File.Exists(path)) { report.AppendLine("样例数据缺失: " + path); return null; }
            var json = File.ReadAllText(path);
            var pattern = JsonUtility.FromJson<GarmentPatternData>(json);
            report.AppendLine($"样例加载: {path}");
            report.AppendLine($"裁片 {pattern?.pieces?.Count ?? 0} 片, 缝合 {pattern?.seams?.Count ?? 0} 条\n");
            return pattern;
        }

        static void Capture(Camera cam, string fileName, Vector3 pos, Vector3 lookAt, float fov)
        {
            cam.transform.position = pos;
            cam.transform.LookAt(lookAt);
            cam.fieldOfView = fov;
            var rt = new RenderTexture(1024, 1024, 24);
            cam.targetTexture = rt;
            cam.Render();
            RenderTexture.active = rt;
            var tex = new Texture2D(1024, 1024, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, 1024, 1024), 0, 0);
            tex.Apply();
            File.WriteAllBytes(Path.Combine(OutDir, fileName), tex.EncodeToPNG());
            RenderTexture.active = null;
            cam.targetTexture = null;
            Object.DestroyImmediate(rt);
            Object.DestroyImmediate(tex);
            Debug.Log("截图: " + fileName);
        }
    }
}
