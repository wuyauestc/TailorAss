import Foundation
#if canImport(NativeClothCollision)
import NativeClothCollision
#endif

/// App value-type adapter for the native, exact-triangle body motion guard.
/// It does not fit the body, change source metrics or claim cloth self-CCD.
nonisolated enum GarmentCodeContinuousBodyContact {
    typealias V=GarmentCodeCircleDrape.Vector3
    enum MotionError:LocalizedError,Sendable {
        case unavailable,invalidBody,pathNotCertified(String)
        var errorDescription:String? {
            switch self {
            case .unavailable:return "当前构建未包含原生连续碰撞模块，请重新构建应用。"
            case .invalidBody:return "人体网格未通过连续碰撞准备检查，不能开始安全生成。"
            case let .pathNotCertified(status):
                switch status {
                case "blockedInitialContact":return "裁片已接触人体，本步未能确认安全推进；本次没有输出收敛成衣。"
                case "budgetExceeded":return "当前款式的连续碰撞运算超过预算，本次已停止生成。"
                default:return "本步未能确认运动不会穿过人体，本次已停止生成。"
                }
            }
        }
    }
    struct Metrics:Codable,Sendable {
        let status:String
        let safeTimeFraction:Double
        let conservativeTimeOfImpact:Double?
        let candidateTrianglePairs:Int
        let evaluatedFeatures:Int
        let nativeQueries:Int
        let estimatedWorkingBytes:Int
        let completedAllFeatures:Bool
        let computationSeconds:Double
    }
    struct Motion:Sendable {
        let positions:[V]
        let metrics:Metrics
        var permitsWholeCandidate:Bool {metrics.status=="clear" && metrics.safeTimeFraction==1}
    }
    static var isAvailable:Bool {
        #if canImport(NativeClothCollision)
        true
        #else
        false
        #endif
    }
    struct Prepared:Sendable {
        #if canImport(NativeClothCollision)
        private let body:ContinuousBodyContact.Prepared
        #endif

        init(bodyPositions:[V],bodyTriangleIndices:[UInt32],
            isCancelled:@Sendable()->Bool={false})throws {
            if isCancelled(){throw CancellationError()}
            #if canImport(NativeClothCollision)
            var limits=ContinuousBodyContact.Limits()
            limits.maximumBodyVertices=20_000;limits.maximumBodyTriangles=40_000
            do {
                // Package callbacks are optional function values, but this
                // synchronous constructor stores no callback in its result.
                body=try withoutActuallyEscaping(isCancelled) {callback in
                    try ContinuousBodyContact.Prepared(bodyPositions:bodyPositions.map{SIMD3($0.x,$0.y,$0.z)},
                        triangleIndices:bodyTriangleIndices,limits:limits,isCancelled:callback)
                }
            } catch ContinuousBodyContact.Failure.cancelled {throw CancellationError()}
            catch {throw MotionError.invalidBody}
            #else
            throw MotionError.unavailable
            #endif
        }

        func guardMotion(previous:[V],candidate:[V],clothTriangleIndices:[UInt32],
            isCancelled:@Sendable()->Bool={false})throws->Motion {
            if isCancelled(){throw CancellationError()}
            #if canImport(NativeClothCollision)
            let started=Date()
            var limits=ContinuousBodyContact.Limits()
            limits.maximumBodyVertices=20_000;limits.maximumBodyTriangles=40_000
            limits.maximumClothVertices=20_000;limits.maximumClothTriangles=40_000
            // This extra path guard prevents actual triangle penetration.
            // The established 2.5mm SDF and .5mm face targets are unchanged.
            let options=ContinuousBodyContact.Options(minimumSeparation:0,distanceTolerance:1e-8,
                maximumIterationsPerFeature:10_000,safetyFactor:0.9,limits:limits)
            let report=withoutActuallyEscaping(isCancelled) {callback in
                body.guardMotion(previous:previous.map{SIMD3($0.x,$0.y,$0.z)},
                    candidate:candidate.map{SIMD3($0.x,$0.y,$0.z)},clothTriangleIndices:clothTriangleIndices,
                    options:options,isCancelled:callback)
            }
            if report.status == .cancelled || isCancelled(){throw CancellationError()}
            guard report.status == .clear || report.status == .limited,
                  report.statistics.completedAllFeatures,
                  report.safeTime.isFinite,report.safeTime>0,report.safeTime<=1 else {
                throw MotionError.pathNotCertified(report.status.rawValue)
            }
            let positions:[V]
            if report.permitsWholeCandidate {positions=candidate}
            else {positions=zip(previous,candidate).map{$0+($1-$0)*report.safeTime}}
            guard positions.count==candidate.count,positions.allSatisfy(\.isFinite) else {
                throw MotionError.pathNotCertified("nonfinite")
            }
            return .init(positions:positions,metrics:.init(status:report.status.rawValue,
                safeTimeFraction:report.safeTime,conservativeTimeOfImpact:report.conservativeTimeOfImpact,
                candidateTrianglePairs:report.statistics.trianglePairs,evaluatedFeatures:report.statistics.evaluatedFeatures,
                nativeQueries:report.statistics.nativeQueries,estimatedWorkingBytes:report.statistics.estimatedWorkingBytes,
                completedAllFeatures:report.statistics.completedAllFeatures,computationSeconds:Date().timeIntervalSince(started)))
            #else
            throw MotionError.unavailable
            #endif
        }
    }
}
