import Foundation
import CryptoKit

/// Serializes the supplied immutable Output, never a simulation candidate or a
/// substitute for the producer's physical acceptance. Original objString bytes,
/// independent source IDs, panel groups and mannequin offset are unchanged.
nonisolated enum GarmentCodeMeshExport {
    typealias K=GarmentCodeCircleDrape
    enum ExportError:LocalizedError,Sendable {
        case invalid(String),budgetExceeded,writeFailed(String)
        var errorDescription:String? {
            switch self {case let .invalid(s):return "三维导出数据无效："+s
            case .budgetExceeded:return "三维导出超过本次文件预算。"
            case let .writeFailed(s):return "三维文件创建失败："+s}
        }
    }
    struct Limits:Sendable {var maximumBytes=64*1_024*1_024}
    struct Artifact:Sendable {
        let resultID:UUID,exportID:UUID,url:URL,byteCount:Int,sha256:String
        fileprivate init(resultID:UUID,exportID:UUID,url:URL,byteCount:Int,sha256:String) {
            self.resultID=resultID;self.exportID=exportID;self.url=url;self.byteCount=byteCount;self.sha256=sha256
        }
    }
    /// Async entry always does string generation and disk IO in its own worker.
    /// The caller still compares resultID with its current run before publishing
    /// a ShareLink. Re-exporting a result creates another independent, identical
    /// file and does not require another simulation.
    static func export(output:K.Output,resultID:UUID,directory:URL?=nil,limits:Limits=Limits(),
                       isCancelled:@escaping @Sendable()->Bool={false})async throws->Artifact {
        let task=Task.detached(priority:.utility) {
            try write(output:output,resultID:resultID,directory:directory,limits:limits,
                      isCancelled:{Task.isCancelled || isCancelled()})
        }
        return try await withTaskCancellationHandler {
            let artifact=try await task.value
            if Task.isCancelled || isCancelled() {try? remove(artifact);throw CancellationError()}
            return artifact
        } onCancel: {task.cancel()}
    }
    /// Only deletes an artifact returned by this exporter. No shared result path
    /// is overwritten: concurrent retries and cancellation own distinct files.
    static func remove(_ artifact:Artifact)throws {if FileManager.default.fileExists(atPath:artifact.url.path){try FileManager.default.removeItem(at:artifact.url)}}

    private static func write(output:K.Output,resultID:UUID,directory:URL?,limits:Limits,
                              isCancelled:@Sendable()->Bool)throws->Artifact {
        try cancel(isCancelled)
        guard (1...256*1_024*1_024).contains(limits.maximumBytes) else {throw ExportError.invalid("文件预算")}
        guard !output.positions.isEmpty,output.positions.count<=20_000,output.triangleIndices.count<=120_000,
              output.mannequinPositions.count<=200_000,output.mannequinTriangleIndices.count<=1_200_000,
              output.triangleIndices.count%3==0,output.mannequinTriangleIndices.count%3==0,
              !output.triangleIndices.isEmpty else {throw ExportError.invalid("网格数量")}
        for (i,p) in (output.positions+output.mannequinPositions).enumerated() {
            if i%128==0 {try cancel(isCancelled)}
            guard p.isFinite,max(abs(p.x),abs(p.y),abs(p.z))<=1e6 else {throw ExportError.invalid("顶点坐标")}
        }
        for (i,index) in output.triangleIndices.enumerated() {
            if i%384==0 {try cancel(isCancelled)}
            guard Int(index)<output.positions.count else {throw ExportError.invalid("布片三角面索引")}
        }
        for (i,index) in output.mannequinTriangleIndices.enumerated() {
            if i%384==0 {try cancel(isCancelled)}
            guard Int(index)<output.mannequinPositions.count else {throw ExportError.invalid("人体三角面索引")}
        }
        if let groups=output.panelGroups {
            guard groups.count<=128,groups.allSatisfy({$0.panelID.utf8.count<=256}),output.validatedPanelGroups != nil else {throw ExportError.invalid("完整裁片分组")}
        }
        // Bound the uninterruptible existing String serializer before calling
        // it. The serializer itself remains byte-identical and unchanged.
        let estimated=4_096+96*(output.positions.count+output.mannequinPositions.count)+48*((output.triangleIndices.count+output.mannequinTriangleIndices.count)/3)+512*(output.panelGroups?.count ?? 0)
        guard estimated<=limits.maximumBytes else {throw ExportError.budgetExceeded}
        try cancel(isCancelled)
        let text=output.objString
        try cancel(isCancelled)
        let bytes=Data(text.utf8)
        guard bytes.count<=limits.maximumBytes else {throw ExportError.budgetExceeded}
        let exportID=UUID(),base=directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("TailorAss3DExports",isDirectory:true)
        guard base.isFileURL else {throw ExportError.invalid("本地导出目录")}
        let name="TailorAss-garment-\(resultID.uuidString)-\(exportID.uuidString).obj"
        let destination=base.appendingPathComponent(name),pending=base.appendingPathComponent(name+".pending")
        var handle:FileHandle?,committed=false
        defer {
            try? handle?.close()
            if !committed {try? FileManager.default.removeItem(at:pending);try? FileManager.default.removeItem(at:destination)}
        }
        do {
            try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
            guard FileManager.default.createFile(atPath:pending.path,contents:nil) else {throw ExportError.writeFailed("无法创建临时文件")}
            handle=try FileHandle(forWritingTo:pending)
            for offset in stride(from:0,to:bytes.count,by:64*1_024) {
                try cancel(isCancelled)
                try handle?.write(contentsOf:bytes.subdata(in:offset..<min(bytes.count,offset+64*1_024)))
            }
            try handle?.synchronize();try handle?.close();handle=nil
            try cancel(isCancelled)
            // Same directory/filesystem rename exposes the complete file in one
            // step. A failed/cancelled attempt never returns a partial artifact.
            try FileManager.default.moveItem(at:pending,to:destination)
            try cancel(isCancelled)
            let hash=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
            try cancel(isCancelled);committed=true
            return Artifact(resultID:resultID,exportID:exportID,url:destination,byteCount:bytes.count,sha256:hash)
        } catch is CancellationError {throw CancellationError()}
        catch let error as ExportError {throw error}
        catch {throw ExportError.writeFailed(error.localizedDescription)}
    }
    private static func cancel(_ f:@Sendable()->Bool)throws {if f(){throw CancellationError()}}
}
