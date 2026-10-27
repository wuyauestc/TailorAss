import NativeClothCollision
@main struct SparseLinkSmoke {
    static func main()throws {
        let p=try NativeSparseCholesky(dimension:3,columnStarts:[0,2,4,5],rowIndices:[0,1,1,2,2])
        let a=try p.refactor(values:[4,1,3,1,2]),x=try p.solve(rhs:[6,10,8],generation:a.generation)
        for (actual,expected) in zip(x.values,[1.0,2,3]){precondition(abs(actual-expected)<1e-10)}
        let b=try p.refactor(values:[8,2,6,2,4]),y=try p.solve(rhs:[6,10,8],generation:b.generation)
        for (actual,expected) in zip(y.values,[0.5,1,1.5]){precondition(abs(actual-expected)<1e-10)}
        precondition(y.diagnostics.relativeResidual<1e-10 && y.diagnostics.quadraticForm>0)
        print("SPARSE REAL SWIFT C INTEROP PASS")
    }
}
