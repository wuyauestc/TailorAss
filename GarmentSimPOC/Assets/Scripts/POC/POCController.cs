using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Diagnostics;
using UnityEngine;
using GarmentSimPOC.Core;
using GarmentSimPOC.Data;
using GarmentSimPOC.RouteA;

namespace GarmentSimPOC.POC
{
    /// <summary>
    /// POC 场景控制器：加载样例 JSON → 校验 → 路线 A 装配 → 展示。
    /// 按键：1=运行路线A  2=人台显隐  R=自动旋转  鼠标拖拽=环绕  滚轮=缩放
    /// </summary>
    public class POCController : MonoBehaviour
    {
        GameObject mannequin;
        GameObject garment;
        string status = "按 [1] 运行路线 A";
        bool autoRotate;
        Material clothMat, mannequinMat;
        [SerializeField] Shader litShader;
        bool cancelled;
        bool ready;
        string deferredPatternJson;

#if UNITY_IOS && !UNITY_EDITOR
        [DllImport("__Internal")] static extern void TailorAssUnityDidComplete(string resultJson);
        [DllImport("__Internal")] static extern void TailorAssUnityDidRequestClose();
#endif

        void Start()
        {
            SetupScene();
            BuildMannequin();
            ready = true;
            if (!string.IsNullOrEmpty(deferredPatternJson))
            {
                var json = deferredPatternJson;
                deferredPatternJson = null;
                GenerateFromJson(json);
            }
            // 独立 Player 仍可直接查看；嵌入 App 时 Swift 会随后传入 JSON。
#if !UNITY_IOS || UNITY_EDITOR
            RunRouteA();
#endif
        }

        void SetupScene()
        {
            // 相机
            var cam = Camera.main;
            if (cam == null)
            {
                var camGo = new GameObject("Main Camera");
                cam = camGo.AddComponent<Camera>();
                camGo.tag = "MainCamera";
            }
            cam.transform.position = new Vector3(0f, 1.25f, 2.6f);
            cam.transform.LookAt(new Vector3(0f, 1.2f, 0f));
            cam.gameObject.AddComponent<OrbitCamera>().target = new Vector3(0f, 1.2f, 0f);

            // 灯光
            if (FindFirstObjectByType<Light>() == null)
            {
                var lgo = new GameObject("Key Light");
                var l = lgo.AddComponent<Light>();
                l.type = LightType.Directional;
                l.intensity = 1.2f;
                lgo.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
                RenderSettings.ambientLight = new Color(0.55f, 0.55f, 0.58f);
            }

            // 材质（URP Lit，双面）
            var shader = litShader != null
                ? litShader
                : Shader.Find("Universal Render Pipeline/Lit");
            if (shader == null)
                throw new InvalidOperationException("URP Lit Shader 未包含在 Player 构建中");
            clothMat = new Material(shader);
            clothMat.SetFloat("_Cull", (float)UnityEngine.Rendering.CullMode.Off);
            clothMat.SetFloat("_Smoothness", 0.25f);
            mannequinMat = new Material(shader);
            mannequinMat.color = new Color(0.82f, 0.80f, 0.78f);
            mannequinMat.SetFloat("_Smoothness", 0.35f);
        }

        public void SetLitShader(Shader shader)
        {
            litShader = shader;
        }

        void BuildMannequin()
        {
            if (mannequin != null) Destroy(mannequin);
            mannequin = MannequinBuilder.Build(mannequinMat);
        }

        public void RunRouteA()
        {
            if (garment != null) Destroy(garment);
            string path = Path.Combine(Application.streamingAssetsPath, "tshirt_sample.json");
            if (!File.Exists(path)) { status = "找不到样例数据: " + path; return; }
            var pattern = JsonUtility.FromJson<GarmentPatternData>(File.ReadAllText(path));
            var res = GeometricGarmentAssembler.Assemble(pattern, clothMat);
            if (res.root != null) garment = res.root;
            status = res.report;
            UnityEngine.Debug.Log(status);
        }

        /// <summary>Swift 通过 UnitySendMessage 调用。参数必须是完整 GarmentPattern JSON。</summary>
        public void LoadPatternJson(string json)
        {
            if (!ready)
            {
                deferredPatternJson = json;
                status = "场景初始化中…";
                return;
            }
            GenerateFromJson(json);
        }

        void GenerateFromJson(string json)
        {
            cancelled = false;
            var watch = Stopwatch.StartNew();
            try
            {
                if (string.IsNullOrWhiteSpace(json))
                    throw new ArgumentException("纸样数据为空");
                var pattern = JsonUtility.FromJson<GarmentPatternData>(json);
                if (pattern == null) throw new ArgumentException("纸样 JSON 无法解析");

                if (garment != null) Destroy(garment);
                var res = GeometricGarmentAssembler.Assemble(pattern, clothMat);
                if (cancelled) return;
                if (res.root == null) throw new InvalidOperationException(res.report);
                garment = res.root;
                status = res.report;
                watch.Stop();
                SendResult(true, null, watch.ElapsedMilliseconds);
            }
            catch (Exception ex)
            {
                watch.Stop();
                status = "生成失败：" + ex.Message;
                UnityEngine.Debug.LogError(status);
                SendResult(false, ex.Message, watch.ElapsedMilliseconds);
            }
        }

        /// <summary>Swift 关闭全屏页时调用；几何路线同步执行，标志用于阻止结果回调。</summary>
        public void CancelGeneration(string unused = "")
        {
            cancelled = true;
            status = "已取消";
        }

        public void RequestClose()
        {
#if UNITY_IOS && !UNITY_EDITOR
            TailorAssUnityDidRequestClose();
#endif
        }

        void SendResult(bool success, string error, long elapsedMs)
        {
            var payload = new BridgeResult
            {
                success = success,
                error = error ?? "",
                elapsedMs = elapsedMs,
                algorithmVersion = "routeA-1"
            };
            string resultJson = JsonUtility.ToJson(payload);
#if UNITY_IOS && !UNITY_EDITOR
            TailorAssUnityDidComplete(resultJson);
#else
            UnityEngine.Debug.Log("[BridgeResult] " + resultJson);
#endif
        }

        [Serializable]
        class BridgeResult
        {
            public bool success;
            public string error;
            public long elapsedMs;
            public string algorithmVersion;
        }

        void Update()
        {
            if (Input.GetKeyDown(KeyCode.Alpha1)) RunRouteA();
            if (Input.GetKeyDown(KeyCode.Alpha2) && mannequin != null)
                mannequin.SetActive(!mannequin.activeSelf);
            if (Input.GetKeyDown(KeyCode.R)) autoRotate = !autoRotate;
            if (autoRotate && garment != null) garment.transform.Rotate(0f, 30f * Time.deltaTime, 0f);
        }

        void OnGUI()
        {
            GUILayout.BeginArea(new Rect(10, 10, 520, 480), GUI.skin.box);
            GUILayout.Label("<b>GarmentSimPOC — 路线 A（几何变形）</b>");
            GUILayout.Label("[1] 运行  [2] 人台显隐  [R] 自动旋转  鼠标拖拽环绕/滚轮缩放");
            if (GUILayout.Button("运行路线 A")) RunRouteA();
            if (GUILayout.Button("关闭预览")) RequestClose();
            GUILayout.Label(status);
            GUILayout.EndArea();
        }
    }
}
