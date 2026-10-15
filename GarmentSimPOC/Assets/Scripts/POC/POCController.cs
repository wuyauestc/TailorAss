using System.IO;
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

        void Start()
        {
            SetupScene();
            BuildMannequin();
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
            clothMat = new Material(Shader.Find("Universal Render Pipeline/Lit"));
            clothMat.SetFloat("_Cull", (float)UnityEngine.Rendering.CullMode.Off);
            clothMat.SetFloat("_Smoothness", 0.25f);
            mannequinMat = new Material(Shader.Find("Universal Render Pipeline/Lit"));
            mannequinMat.color = new Color(0.82f, 0.80f, 0.78f);
            mannequinMat.SetFloat("_Smoothness", 0.35f);
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
            GUILayout.Label(status);
            GUILayout.EndArea();
        }
    }
}
