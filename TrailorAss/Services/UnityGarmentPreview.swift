import SwiftUI
import Combine

#if canImport(UnityFramework)
import UnityFramework
import MachO
import Darwin
#endif

struct UnityGarmentResult: Codable, Equatable {
    let success: Bool
    let error: String
    let elapsedMs: Int64
    let algorithmVersion: String
}

@MainActor
final class UnityGarmentPreview: NSObject, ObservableObject {
    static let shared = UnityGarmentPreview()
    @Published private(set) var state: State = .idle
    @Published var shouldDismiss = false

    enum State: Equatable {
        case idle, launching, generating
        case completed(UnityGarmentResult)
        case failed(String)
    }

    private var pendingJSON: String?
    private var observers: [NSObjectProtocol] = []
#if canImport(UnityFramework)
    private var unity: UnityFramework?
#endif

    private override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .tailorAssUnityResult, object: nil, queue: .main) { [weak self] note in
            guard let json = note.userInfo?["json"] as? String else { return }
            Task { @MainActor in self?.receiveResult(json) }
        })
        observers.append(center.addObserver(forName: .tailorAssUnityClose, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.shouldDismiss = true }
        })
    }

    func present(patternJSON: String) {
        shouldDismiss = false
        pendingJSON = patternJSON
#if canImport(UnityFramework)
        state = .launching
        launchUnityIfNeeded()
#else
        state = .failed("UnityFramework 尚未接入。请先安装 Unity iOS Build Support，导出工程并按集成说明添加 Unity-iPhone.xcodeproj。")
#endif
    }

    func cancel() {
#if canImport(UnityFramework)
        unity?.sendMessageToGO(withName: "POCController", functionName: "CancelGeneration", message: "")
        unity?.pause(true)
#endif
        shouldDismiss = true
    }

    private func receiveResult(_ json: String) {
        guard let data = json.data(using: .utf8),
              let result = try? JSONDecoder().decode(UnityGarmentResult.self, from: data) else {
            state = .failed("Unity 返回了无法解析的结果")
            return
        }
        state = result.success ? .completed(result) : .failed(result.error)
    }

#if canImport(UnityFramework)
    private func launchUnityIfNeeded() {
        if unity == nil {
            guard let path = Bundle.main.privateFrameworksPath?.appending("/UnityFramework.framework"),
                  let bundle = Bundle(path: path), bundle.load(),
                  let framework = bundle.principalClass?.getInstance() else {
                state = .failed("UnityFramework 加载失败")
                return
            }
            unity = framework
            framework.setDataBundleId("com.unity3d.framework")
            // 通过当前进程的动态符号表取主可执行文件 Mach-O header，避免 Swift
            // 对 `_mh_execute_header` 产生双下划线链接符号。
            guard let process = dlopen(nil, RTLD_NOW),
                  let symbol = dlsym(process, "_mh_execute_header") else {
                state = .failed("无法读取主程序 Mach-O header")
                return
            }
            framework.setExecuteHeader(symbol.assumingMemoryBound(to: MachHeader.self))
            framework.register(self)
            framework.runEmbedded(withArgc: CommandLine.argc, argv: CommandLine.unsafeArgv, appLaunchOpts: nil)
        } else {
            unity?.showUnityWindow()
            unity?.pause(false)
        }
        guard let json = pendingJSON else { return }
        pendingJSON = nil
        state = .generating
        unity?.sendMessageToGO(withName: "POCController", functionName: "LoadPatternJson", message: json)
    }
#endif
}

#if canImport(UnityFramework)
extension UnityGarmentPreview: UnityFrameworkListener {
    nonisolated func unityDidUnload(_ notification: Notification!) {
        Task { @MainActor in self.unity = nil; self.state = .idle }
    }
    nonisolated func unityDidQuit(_ notification: Notification!) {
        Task { @MainActor in self.shouldDismiss = true }
    }
}
#endif

extension Notification.Name {
    static let tailorAssUnityResult = Notification.Name("TailorAssUnityResultNotification")
    static let tailorAssUnityClose = Notification.Name("TailorAssUnityCloseNotification")
}

enum GarmentSamplePattern {
    // 小型四片样例专用于端到端传输；阶段 1 高精度样例仍保留在 StreamingAssets。
    static let json = #"""
    {"version":"1.0","mannequin":{"size":"M","heightCm":165,"bustCm":88,"waistCm":68,"hipCm":92},"pieces":[
    {"id":"tshirt-front","name":"前片","type":"front","vertices":[{"id":"f0","x":-22,"y":0},{"id":"f1","x":22,"y":0},{"id":"f2","x":18,"y":56},{"id":"f3","x":-18,"y":56}],"edges":[{"id":"fe0","fromVertex":"f0","toVertex":"f1","role":"hem"},{"id":"fe1","fromVertex":"f1","toVertex":"f2","role":"side"},{"id":"fe2","fromVertex":"f2","toVertex":"f3","role":"neckline"},{"id":"fe3","fromVertex":"f3","toVertex":"f0","role":"side"}],"material":{"thickness":0.02,"stiffness":0.5,"color":"#2E86AB"}},
    {"id":"tshirt-back","name":"后片","type":"back","vertices":[{"id":"b0","x":-22,"y":0},{"id":"b1","x":22,"y":0},{"id":"b2","x":18,"y":56},{"id":"b3","x":-18,"y":56}],"edges":[{"id":"be0","fromVertex":"b0","toVertex":"b1","role":"hem"},{"id":"be1","fromVertex":"b1","toVertex":"b2","role":"side"},{"id":"be2","fromVertex":"b2","toVertex":"b3","role":"neckline"},{"id":"be3","fromVertex":"b3","toVertex":"b0","role":"side"}],"material":{"thickness":0.02,"stiffness":0.5,"color":"#2E86AB"}},
    {"id":"tshirt-sleeve-left","name":"左袖","type":"sleeveLeft","vertices":[{"id":"l0","x":-15,"y":0},{"id":"l1","x":15,"y":0},{"id":"l2","x":12,"y":24},{"id":"l3","x":-12,"y":24}],"edges":[{"id":"le0","fromVertex":"l0","toVertex":"l1","role":"sleeveCuff"},{"id":"le1","fromVertex":"l1","toVertex":"l2","role":"side"},{"id":"le2","fromVertex":"l2","toVertex":"l3","role":"sleeveCap"},{"id":"le3","fromVertex":"l3","toVertex":"l0","role":"side"}],"material":{"thickness":0.02,"stiffness":0.5,"color":"#2E86AB"}},
    {"id":"tshirt-sleeve-right","name":"右袖","type":"sleeveRight","vertices":[{"id":"r0","x":-15,"y":0},{"id":"r1","x":15,"y":0},{"id":"r2","x":12,"y":24},{"id":"r3","x":-12,"y":24}],"edges":[{"id":"re0","fromVertex":"r0","toVertex":"r1","role":"sleeveCuff"},{"id":"re1","fromVertex":"r1","toVertex":"r2","role":"side"},{"id":"re2","fromVertex":"r2","toVertex":"r3","role":"sleeveCap"},{"id":"re3","fromVertex":"r3","toVertex":"r0","role":"side"}],"material":{"thickness":0.02,"stiffness":0.5,"color":"#2E86AB"}}],"seams":[]}
    """#
}
