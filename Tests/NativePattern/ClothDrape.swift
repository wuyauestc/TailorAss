import Foundation

@main
struct ClothDrapeRegression {
    enum Failure: Error { case check(String) }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure.check(message) }
    }
    static func main() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let body=GarmentCodeBodyParameters(values:catalog.body)
        var design=GarmentCodeDesignParameters(catalog:catalog)
        _=design.setValue(.null,at:["meta","upper"])
        _=design.setValue(.null,at:["meta","wb"])
        _=design.setValue(.string("SkirtCircle"),at:["meta","bottom"])
        _=design.setValue(.bool(false),at:["flare-skirt","cut","add"])
        var baseline:GarmentCodeCircleDrape.Output?
        var last:GarmentCodeCircleDrape.Output?
        var lastLengthRatio:Double?
        let cases: [(Double,Double)] = ProcessInfo.processInfo.environment["GARMENTCODE_CLOTH_SINGLE_CASE"] == "1" ? [(0.75,0.2)] : [(0.5,0.2),(0.75,0.2),(1.0,0.2),(0.75,0.35)]
        for (suns,lengthRatio) in cases {
            _=design.setValue(.number(suns),at:["flare-skirt","suns"])
            _=design.setValue(.number(lengthRatio),at:["flare-skirt","length"])
            let document=try GarmentCodeNativeGenerator.generate(body:body,design:design)
            let snapshotEncoder=JSONEncoder()
            snapshotEncoder.outputFormatting=[.sortedKeys]
            let before=try snapshotEncoder.encode(document)
            let input=try GarmentCodeCircleDrape.prepare(document:document,body:body)
            try require(input.referencePositions.count > input.positions.count,"Seams must share simulation degrees of freedom but keep separate rest coordinates")
            try require(input.seamPaths.count == 2,"Both actual side seams must be mapped")
            try require(abs(input.waistCircumferenceMeters-(body["waist"] ?? 0)/100)<1e-6,"Waist must be measured from original pattern arcs")
            for spring in input.springs {
                try require(spring.length>0 && spring.a != spring.b,"Degenerate metric")
            }
            let output=try GarmentCodeCircleDrape.simulate(input:input)
            let d=output.diagnostics
            let line="suns=\(suns) vertices=\(d.vertexCount) seconds=\(d.computationSeconds) strain=\(d.maxEdgeStrain) meanStrain=\(d.meanEdgeStrain) speed=\(d.maxSpeedMetersPerSecond) converged=\(d.converged)\n"
            FileHandle.standardError.write(Data(line.utf8))
            let worst=input.springs.sorted {
                abs((output.positions[$0.a]-output.positions[$0.b]).length/$0.length-1) > abs((output.positions[$1.a]-output.positions[$1.b]).length/$1.length-1)
            }.prefix(3)
            for spring in worst {
                let first=input.referenceToSimulation.firstIndex(of:spring.a)!
                let second=input.referenceToSimulation.firstIndex(of:spring.b)!
                let rowA=(first%((input.panelColumns+1)*(input.radialSegments+1)))/(input.panelColumns+1)
                let rowB=(second%((input.panelColumns+1)*(input.radialSegments+1)))/(input.panelColumns+1)
                let info="  worst \(spring.a)-\(spring.b) rows \(rowA)-\(rowB) rest=\(spring.length) actual=\((output.positions[spring.a]-output.positions[spring.b]).length) pinned=\(input.pinned[spring.a])-\(input.pinned[spring.b])\n"
                FileHandle.standardError.write(Data(info.utf8))
            }
            try require(output.positions.allSatisfy(\.isFinite),"Non-finite cloth")
            try require(d.converged,"Representative source case did not reach sustained convergence")
            try require(d.maxSeamGapMeters == 0,"Shared seam particles must coincide exactly")
            try require(d.maxBodyPenetrationMeters<0.003,"Proxy penetration")
            let after=try snapshotEncoder.encode(document)
            try require(after==before,"Simulation changed source paper pattern")
            if let last, lastLengthRatio == lengthRatio { try require(output.diagnostics.hemCircumferenceMeters>last.diagnostics.hemCircumferenceMeters,"More suns must increase real source hem") }
            if suns == 0.75 && lengthRatio == 0.2 { baseline=output }
            if lengthRatio == 0.35, let baseline {
                try require(d.radialLengthMeters>baseline.diagnostics.radialLengthMeters+0.10,"Length parameter must change real source radius")
                try require((output.positions.map(\.y).min() ?? 0)<(baseline.positions.map(\.y).min() ?? 0)-0.03,"Longer source skirt must alter draped geometry")
            }
            if let directory=ProcessInfo.processInfo.environment["GARMENTCODE_CLOTH_OUTPUT_DIR"] {
                let url=URL(fileURLWithPath:directory)
                try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
                let tag=lengthRatio == 0.2 ? "circle-\(suns)" : "circle-\(suns)-length-\(lengthRatio)"
                try output.objString.write(to:url.appendingPathComponent("\(tag).obj"),atomically:true,encoding:.utf8)
                let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
                try encoder.encode(d).write(to:url.appendingPathComponent("\(tag)-diagnostics.json"))
                try encoder.encode(document).write(to:url.appendingPathComponent("\(tag)-pattern.json"))
                try encoder.encode(output).write(to:url.appendingPathComponent("\(tag)-mesh.json"))
            }
            last=output
            lastLengthRatio=lengthRatio
            try require(d.maxEdgeStrain<0.08,"Cloth cannot preserve source sizes closely enough")
            var cancelled=false
            do { _=try GarmentCodeCircleDrape.simulate(input:input,isCancelled:{true}) }
            catch is CancellationError { cancelled=true }
            try require(cancelled,"Cancelled generation must not return a result")
        }
        _=design.setValue(.string("StraightWB"),at:["meta","wb"])
        let unsupported=try GarmentCodeNativeGenerator.generate(body:body,design:design)
        var rejected=false
        do { _=try GarmentCodeCircleDrape.prepare(document:unsupported,body:body) }
        catch { rejected=true }
        try require(rejected,"Unsupported waistbands must not disappear silently")
        _=design.setValue(.null,at:["meta","wb"])
        _=design.setValue(.number(1.5),at:["flare-skirt","suns"])
        let overFullCircle=try GarmentCodeNativeGenerator.generate(body:body,design:design)
        rejected=false
        do { _=try GarmentCodeCircleDrape.prepare(document:overFullCircle,body:body) }
        catch { rejected=true }
        try require(rejected,"Unverified over-full-circle gathers must be rejected explicitly")
        _=design.setValue(.number(0.75),at:["flare-skirt","suns"])
        _=design.setValue(.bool(true),at:["flare-skirt","cut","add"])
        let cut=try GarmentCodeNativeGenerator.generate(body:body,design:design)
        rejected=false
        do { _=try GarmentCodeCircleDrape.prepare(document:cut,body:body) }
        catch { rejected=true }
        try require(rejected,"Cut/slit geometry must not be replaced by an uncut template")
        print("PASS: circle drape metrics, seams, finite state, source immutability, cancellation and unsupported scope")
    }
}
