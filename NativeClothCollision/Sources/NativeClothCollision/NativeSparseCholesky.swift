import CNativeClothSparse

/// Serial Apple Sparse Cholesky workspace. This mutable class deliberately does
/// not conform to Sendable; create and use it within one numerical worker.
/// It neither changes a physical objective nor accepts particle positions.
public final class NativeSparseCholesky {
    public struct Limits:Sendable {
        public var maximumDegreesOfFreedom=60_000
        public var maximumLowerNonzeros=2_000_000
        public var maximumFactorBytes:UInt64=256*1_024*1_024
        public var maximumWorkspaceBytes:UInt64=256*1_024*1_024
        public init(){}
    }
    public enum Failure:Error,Sendable,Equatable {
        case invalid,cancelled,budgetExceeded,unsupportedRounding,symbolicFailure
        case notPositiveDefinite,solveFailed,staleFactor
    }
    public struct Diagnostics:Sendable {
        public let dimension:Int,numericReady:Bool
        public let generation:UInt64,numericFactorizations:UInt64,solveCount:UInt64
        /// SDK-reported minimum numeric storage, not total process RSS.
        public let factorBytesMinimum:UInt64,numericWorkspaceBytes:UInt64,solveWorkspaceBytes:UInt64,matrixCapacityBytes:UInt64
        public let relativeResidual:Double,quadraticForm:Double
        fileprivate init(_ r:NCSReport){
            dimension=Int(r.dimension);numericReady=r.numeric_ready != 0
            generation=r.numeric_generation;numericFactorizations=r.numeric_factorizations;solveCount=r.solve_count
            factorBytesMinimum=r.factor_bytes_minimum;numericWorkspaceBytes=r.numeric_workspace_bytes
            solveWorkspaceBytes=r.solve_workspace_bytes;matrixCapacityBytes=r.matrix_capacity_bytes
            relativeResidual=r.relative_residual;quadraticForm=r.quadratic_form
        }
    }
    public struct Solution:Sendable {
        public let values:[Double]
        public let diagnostics:Diagnostics
    }
    private final class CancellationBox {
        let check:@Sendable()->Bool
        init(_ check:@escaping @Sendable()->Bool){self.check=check}
    }
    private static func withCancellation<T>(_ check:@Sendable()->Bool,_ body:(NCSCancel?,UnsafeMutableRawPointer)->T)->T {
        withoutActuallyEscaping(check){escaped in
            let box=CancellationBox(escaped),context=Unmanaged.passUnretained(box).toOpaque()
            return withExtendedLifetime(box){body({context in
                guard let context else{return 0}
                return Unmanaged<CancellationBox>.fromOpaque(context).takeUnretainedValue().check() ? 1:0
            },context)}
        }
    }
    private static func failure(_ status:Int32)->Failure {
        switch status {
        case 2:return .cancelled
        case 3:return .budgetExceeded
        case 4:return .unsupportedRounding
        case 5:return .symbolicFailure
        case 6:return .notPositiveDefinite
        case 7:return .solveFailed
        case 8:return .staleFactor
        default:return .invalid
        }
    }
    private let handle:OpaquePointer
    public let dimension:Int,lowerNonzeros:Int
    public private(set) var diagnostics:Diagnostics

    /// Column starts and sorted lower row indices are copied by the native
    /// owner. Numeric values are supplied separately by refactor().
    public init(dimension:Int,columnStarts:[Int64],rowIndices:[Int32],limits:Limits=Limits(),
                isCancelled:@Sendable()->Bool={false})throws {
        guard dimension>0,dimension<=Int(Int32.max),columnStarts.count==dimension+1,
              limits.maximumDegreesOfFreedom>0,limits.maximumLowerNonzeros>0 else {throw Failure.invalid}
        self.dimension=dimension;lowerNonzeros=rowIndices.count
        var report=NCSReport()
        let nativeLimits=NCSLimits(maximum_dofs:Int64(limits.maximumDegreesOfFreedom),maximum_lower_nonzeros:Int64(limits.maximumLowerNonzeros),maximum_factor_bytes:limits.maximumFactorBytes,maximum_workspace_bytes:limits.maximumWorkspaceBytes)
        let pointer=Self.withCancellation(isCancelled){callback,context in
            columnStarts.withUnsafeBufferPointer{columns in rowIndices.withUnsafeBufferPointer{rows in
                ncs_create(Int32(dimension),Int64(rowIndices.count),columns.baseAddress,rows.baseAddress,nativeLimits,callback,context,&report)
            }}
        }
        guard report.status==0,let pointer else {throw Self.failure(report.status)}
        handle=pointer;diagnostics=Diagnostics(report)
    }
    deinit{ncs_destroy(handle)}

    /// Any failed/cancelled assembly may call this before returning. A later
    /// solve cannot silently use an earlier pose's factors.
    public func invalidate(){var report=NCSReport();ncs_invalidate(handle,&report);diagnostics=Diagnostics(report)}

    @discardableResult public func refactor(values:[Double],isCancelled:@Sendable()->Bool={false})throws->Diagnostics {
        var report=NCSReport()
        Self.withCancellation(isCancelled){callback,context in
            values.withUnsafeBufferPointer{v in _=ncs_refactor(handle,v.baseAddress,Int64(v.count),callback,context,&report)}
        }
        diagnostics=Diagnostics(report)
        guard report.status==0 else {throw Self.failure(report.status)}
        return diagnostics
    }
    /// Output is staged by the C owner; no partial solution escapes failure.
    /// Cancellation is checked around opaque SDK calls, not inside their kernel.
    public func solve(rhs:[Double],generation:UInt64,isCancelled:@Sendable()->Bool={false})throws->Solution {
        guard rhs.count<=Int(Int32.max) else {invalidate();throw Failure.budgetExceeded}
        var values=Array(repeating:0.0,count:dimension),report=NCSReport()
        Self.withCancellation(isCancelled){callback,context in
            rhs.withUnsafeBufferPointer{b in values.withUnsafeMutableBufferPointer{x in
                _=ncs_solve(handle,generation,b.baseAddress,Int32(b.count),x.baseAddress,callback,context,&report)
            }}
        }
        diagnostics=Diagnostics(report)
        guard report.status==0 else {throw Self.failure(report.status)}
        return .init(values:values,diagnostics:diagnostics)
    }
}
