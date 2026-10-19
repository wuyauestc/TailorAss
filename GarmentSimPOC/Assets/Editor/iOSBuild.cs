using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.Callbacks;
using UnityEditor.SceneManagement;
using UnityEditor.iOS.Xcode;
using UnityEngine;
using GarmentSimPOC.POC;

namespace GarmentSimPOC.EditorTools
{
    /// <summary>可重复的 Unity-as-a-Library iOS 导出入口。</summary>
    public static class iOSBuild
    {
        [PostProcessBuild(100)]
        public static void ConfigureUnityAsALibrary(BuildTarget target, string path)
        {
            if (target != BuildTarget.iOS) return;

            string projectPath = PBXProject.GetPBXProjectPath(path);
            var project = new PBXProject();
            project.ReadFromFile(projectPath);

            // Unity 默认把 Data 放进 Unity-iPhone.app。宿主只嵌入 UnityFramework，
            // 因此 UaaL 必须把 Data 改为 UnityFramework 的资源，否则引擎启动会立即退出。
            string dataGuid = project.FindFileGuidByProjectPath("Data");
            if (!string.IsNullOrEmpty(dataGuid))
            {
                project.RemoveFileFromBuild(project.GetUnityMainTargetGuid(), dataGuid);
                project.AddFileToBuild(project.GetUnityFrameworkTargetGuid(), dataGuid);
            }

            project.WriteToFile(projectPath);
        }

        public static void Build()
        {
            BuildPlayer(simulator: false);
        }

        /// <summary>为 Apple Silicon Device Hub / iOS Simulator 导出独立工程。</summary>
        public static void BuildSimulator()
        {
            BuildPlayer(simulator: true);
        }

        static void BuildPlayer(bool simulator)
        {
            string folder = simulator ? "iOSSimulator" : "iOS";
            string output = Path.GetFullPath(Path.Combine(Application.dataPath, "../Builds", folder));
            Directory.CreateDirectory(output);

            PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.iOS, "com.trailorass.garmentsim");
            PlayerSettings.iOS.targetOSVersionString = "17.0";
            PlayerSettings.iOS.sdkVersion = simulator ? iOSSdkVersion.SimulatorSDK : iOSSdkVersion.DeviceSDK;
            PlayerSettings.iOS.targetDevice = iOSTargetDevice.iPhoneOnly;
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.Portrait;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.allowedAutorotateToLandscapeLeft = false;
            PlayerSettings.allowedAutorotateToLandscapeRight = false;
            PlayerSettings.SetUseDefaultGraphicsAPIs(BuildTarget.iOS, false);
            PlayerSettings.SetGraphicsAPIs(BuildTarget.iOS,
                new[] { UnityEngine.Rendering.GraphicsDeviceType.Metal });

            // 阶段 1 的 POC.unity 是截图后保存的静态验收场景。iOS 使用独立、最小的
            // 运行时场景，确保桥接消息总能命中名为 POCController 的对象。
            string scene = "Assets/Scenes/iOSPreview.unity";
            EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            var controller = new GameObject("POCController");
            var poc = controller.AddComponent<POCController>();
            var litShader = Shader.Find("Universal Render Pipeline/Lit");
            if (litShader == null)
                throw new Exception("Universal Render Pipeline/Lit shader not found");
            poc.SetLitShader(litShader);
            EditorSceneManager.SaveScene(EditorSceneManager.GetActiveScene(), scene);
            var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { scene },
                locationPathName = output,
                target = BuildTarget.iOS,
                options = BuildOptions.Development
            });

            if (report.summary.result != BuildResult.Succeeded)
                throw new Exception($"iOS build failed: {report.summary.result}, " +
                                    string.Join("\n", report.steps.SelectMany(s => s.messages)
                                        .Where(m => m.type == LogType.Error).Select(m => m.content)));

            Debug.Log($"iOS {(simulator ? "Simulator" : "Device")} export complete: " +
                      $"{output} ({report.summary.totalSize} bytes)");
        }
    }
}
