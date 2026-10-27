import Foundation
import NativeClothCollision

/// Adds complete current IPC PSD blocks to the source/sewing/hinge numerical
/// preconditioner. The true objective and raw Hessian remain separate.
nonisolated enum GarmentCodeJointContactPreconditioner {
    typealias P = GarmentCodeJointPreconditioner
    typealias J = GarmentCodeJointObjective
    typealias V = J.V
    enum Kind: String, Codable, Sendable { case body, cloth }
    struct Block: Sendable {
        let kind: Kind
        let vertexIDs: [Int]
        let hessian: [Double]
    }
    enum Failure: Error, Sendable { case invalid, budgetExceeded, staleFactor }
    struct Report: Codable, Sendable {
        let generation: UInt64
        let bodyBlocks: Int, clothBlocks: Int
        let lowerNonzeros: Int, additionalLowerNonzeros: Int
        let rebuiltSymbolicPattern: Bool
        let maximumRelativeBlockAsymmetry: Double
        let baseAssemblySeconds: Double, baseRefactorSeconds: Double
        let contactAssemblySeconds: Double, contactSymbolicSeconds: Double, contactRefactorSeconds: Double
    }
    static func blocks(body: BodyContactPotential.Evaluation) throws -> [Block] {
        guard body.hessianMode == .clampPositiveSemidefinite else { throw Failure.invalid }
        return body.localBlocks.map { .init(kind: .body, vertexIDs: $0.clothVertexIDs.map(Int.init), hessian: $0.clothHessianRowMajorNewtonsPerMeter) }
    }
    static func blocks(cloth: ClothContactPotential.Evaluation) throws -> [Block] {
        guard cloth.hessianMode == .clampPositiveSemidefinite else { throw Failure.invalid }
        return cloth.localBlocks.map { .init(kind: .cloth, vertexIDs: $0.vertexIDs.map(Int.init), hessian: $0.hessianRowMajorNewtonsPerMeter) }
    }

    /// One worker owns the base and optional extended factors. A separate
    /// monotonic generation prevents old tokens matching a newly built native
    /// matrix whose internal generation starts again at one.
    final class Workspace {
        let base: P.Workspace
        private var extended: NativeSparseCholesky?
        private var columns: [Int64] = [], rows: [Int32] = [], values: [Double] = []
        private var useExtended = false, ready = false
        private var nativeGeneration: UInt64 = 0
        private(set) var generation: UInt64 = 0
        private(set) var report: Report?
        private(set) var latestSolveRelativeResidual: Double?
        init(base: P.Workspace) { self.base = base }
        @discardableResult func update(frame: J.Frame, positions: [V], blocks: [Block],
            isCancelled: @Sendable () -> Bool = { false }) throws -> UInt64 {
            ready = false; report = nil; latestSolveRelativeResidual = nil; values = []; extended?.invalidate()
            guard generation < UInt64.max else { throw Failure.budgetExceeded }
            generation += 1
            if isCancelled() { throw CancellationError() }
            let b: P.UpdateReport
            do { b = try base.update(frame: frame, positions: positions, isCancelled: isCancelled) }
            catch NativeSparseCholesky.Failure.cancelled { throw CancellationError() }
            if blocks.isEmpty {
                useExtended = false; nativeGeneration = b.linear.generation
                report = .init(generation: generation, bodyBlocks: 0, clothBlocks: 0,
                    lowerNonzeros: base.plan.rowIndices.count, additionalLowerNonzeros: 0, rebuiltSymbolicPattern: false,
                    maximumRelativeBlockAsymmetry: 0, baseAssemblySeconds: b.assemblySeconds, baseRefactorSeconds: b.refactorSeconds,
                    contactAssemblySeconds: 0, contactSymbolicSeconds: 0, contactRefactorSeconds: 0)
                if isCancelled() { throw CancellationError() }
                ready = true; return generation
            }
            let stamp = Date(), plan = base.plan, dofs = plan.dimension, n = dofs/3
            guard blocks.count <= 400_000 else { throw Failure.budgetExceeded }
            var keys = Set<Int64>(), bodyCount = 0, clothCount = 0, asymmetry = 0.0, chargedBlockBytes = 0
            for col in 0..<dofs {
                if col % 128 == 0 && isCancelled() { throw CancellationError() }
                for i in Int(plan.columnStarts[col])..<Int(plan.columnStarts[col+1]) {
                    keys.insert(Int64(plan.rowIndices[i])*Int64(dofs)+Int64(col))
                }
            }
            func checkPatternBudget() throws {
                // Conservative staged key/lookup estimate, not process RSS.
                guard keys.count <= plan.limits.linear.maximumLowerNonzeros,
                      keys.count <= plan.limits.maximumScatterBytes/32 else { throw Failure.budgetExceeded }
            }
            try checkPatternBudget()
            for (index, block) in blocks.enumerated() {
                if index % 32 == 0 && isCancelled() { throw CancellationError() }
                let ids = block.vertexIDs, d = 3*ids.count
                guard (1...4).contains(ids.count), Set(ids).count == ids.count,
                      ids.allSatisfy({ (0..<n).contains($0) }), block.hessian.count == d*d,
                      block.hessian.allSatisfy(\.isFinite) else { throw Failure.invalid }
                let more = block.hessian.count*MemoryLayout<Double>.stride
                guard chargedBlockBytes <= 128*1_024*1_024-more else { throw Failure.budgetExceeded }
                chargedBlockBytes += more
                let scale = max(1, block.hessian.reduce(0) { max($0, abs($1)) })
                for a in 0..<d { for c in 0..<d {
                    asymmetry = max(asymmetry, abs(block.hessian[a*d+c]-block.hessian[c*d+a])/scale)
                    let row = 3*ids[a/3]+a%3, col = 3*ids[c/3]+c%3
                    if row >= col { keys.insert(Int64(row)*Int64(dofs)+Int64(col)) }
                } }
                if block.kind == .body { bodyCount += 1 } else { clothCount += 1 }
                try checkPatternBudget()
            }
            guard asymmetry <= 1e-10 else { throw Failure.invalid }
            let ordered = keys.sorted { a,b in
                a%Int64(dofs) == b%Int64(dofs) ? a/Int64(dofs) < b/Int64(dofs) : a%Int64(dofs) < b%Int64(dofs)
            }
            var csc = Array(repeating: Int64(0), count: dofs+1), rowIDs: [Int32] = [], lookup: [Int64:Int] = [:]
            rowIDs.reserveCapacity(ordered.count); lookup.reserveCapacity(ordered.count)
            for (i,key) in ordered.enumerated() {
                if i % 2048 == 0 && isCancelled() { throw CancellationError() }
                csc[Int(key%Int64(dofs))+1] += 1; rowIDs.append(Int32(key/Int64(dofs))); lookup[key] = i
            }
            for i in 0..<dofs { csc[i+1] += csc[i] }
            var v = Array(repeating: 0.0, count: ordered.count)
            for col in 0..<dofs {
                if col % 128 == 0 && isCancelled() { throw CancellationError() }
                for i in Int(plan.columnStarts[col])..<Int(plan.columnStarts[col+1]) {
                    let key = Int64(plan.rowIndices[i])*Int64(dofs)+Int64(col)
                    guard let offset = lookup[key] else { throw Failure.invalid }; v[offset] = base.lowerValues[i]
                }
            }
            for (index, block) in blocks.enumerated() {
                if index % 32 == 0 && isCancelled() { throw CancellationError() }
                let d = 3*block.vertexIDs.count
                for a in 0..<d { for b in 0..<d {
                    let row = 3*block.vertexIDs[a/3]+a%3, col = 3*block.vertexIDs[b/3]+b%3
                    if row >= col {
                        guard let offset = lookup[Int64(row)*Int64(dofs)+Int64(col)] else { throw Failure.invalid }
                        v[offset] += block.hessian[a*d+b]
                    }
                } }
            }
            guard v.allSatisfy(\.isFinite) else { throw Failure.invalid }
            if isCancelled() { throw CancellationError() }
            let assembly = Date().timeIntervalSince(stamp), symbolicStamp = Date()
            let rebuild = extended == nil || columns != csc || rows != rowIDs
            do {
                if rebuild {
                    extended = try NativeSparseCholesky(dimension: dofs, columnStarts: csc, rowIndices: rowIDs,
                        limits: plan.limits.linear, isCancelled: isCancelled)
                    columns = csc; rows = rowIDs
                }
                let symbolic = Date().timeIntervalSince(symbolicStamp), factorStamp = Date()
                guard let extended else { throw Failure.invalid }
                let native = try extended.refactor(values: v, isCancelled: isCancelled)
                if isCancelled() { throw CancellationError() }
                values = v; nativeGeneration = native.generation; useExtended = true
                report = .init(generation: generation, bodyBlocks: bodyCount, clothBlocks: clothCount,
                    lowerNonzeros: rowIDs.count, additionalLowerNonzeros: rowIDs.count-plan.rowIndices.count, rebuiltSymbolicPattern: rebuild,
                    maximumRelativeBlockAsymmetry: asymmetry, baseAssemblySeconds: b.assemblySeconds, baseRefactorSeconds: b.refactorSeconds,
                    contactAssemblySeconds: assembly, contactSymbolicSeconds: symbolic, contactRefactorSeconds: Date().timeIntervalSince(factorStamp))
                ready = true; return generation
            } catch NativeSparseCholesky.Failure.cancelled { throw CancellationError() }
        }
        func solve(rhs: [V], generation token: UInt64, isCancelled: @Sendable () -> Bool = { false }) throws -> [V] {
            guard ready, token == generation else { throw Failure.staleFactor }
            latestSolveRelativeResidual = nil
            do {
                if !useExtended {
                    let result = try base.solve(rhs: rhs, generation: nativeGeneration, isCancelled: isCancelled)
                    latestSolveRelativeResidual = result.linear.relativeResidual; return result.vector
                }
                guard let extended, rhs.count*3 == base.plan.dimension else { throw Failure.invalid }
                let result = try extended.solve(rhs: rhs.flatMap { [$0.x,$0.y,$0.z] }, generation: nativeGeneration, isCancelled: isCancelled)
                latestSolveRelativeResidual = result.diagnostics.relativeResidual
                return stride(from: 0, to: result.values.count, by: 3).map { V(x: result.values[$0],y: result.values[$0+1],z: result.values[$0+2]) }
            } catch NativeSparseCholesky.Failure.cancelled { ready = false; throw CancellationError() }
            catch { ready = false; throw error }
        }
        func product(_ x: [V]) throws -> [V] {
            guard ready else { throw Failure.staleFactor }
            if !useExtended { return try base.product(x) }
            guard x.count*3 == base.plan.dimension else { throw Failure.invalid }
            let flat = x.flatMap { [$0.x,$0.y,$0.z] }; var y = Array(repeating: 0.0, count: flat.count)
            for col in flat.indices { for i in Int(columns[col])..<Int(columns[col+1]) {
                let row = Int(rows[i]), v = values[i]; y[row] += v*flat[col]
                if row != col { y[col] += v*flat[row] }
            } }
            return stride(from: 0, to: y.count, by: 3).map { V(x:y[$0],y:y[$0+1],z:y[$0+2]) }
        }
        /// Read the assembled current-P diagonal without multiplying a basis
        /// vector through the complete sparse matrix. This is a proposal score,
        /// not an objective derivative or an acceptance certificate.
        func diagonal(at dof: Int, generation token: UInt64) throws -> Double {
            guard ready, token == generation else { throw Failure.staleFactor }
            guard (0..<base.plan.dimension).contains(dof) else { throw Failure.invalid }
            let value: Double
            if useExtended {
                let offset = Int(columns[dof])
                guard offset < Int(columns[dof+1]), Int(rows[offset]) == dof else { throw Failure.invalid }
                value = values[offset]
            } else {
                let offset = Int(base.plan.columnStarts[dof])
                guard offset < Int(base.plan.columnStarts[dof+1]), Int(base.plan.rowIndices[offset]) == dof else { throw Failure.invalid }
                value = base.lowerValues[offset]
            }
            guard value.isFinite, value > 0 else { throw Failure.invalid }
            return value
        }
    }
}
