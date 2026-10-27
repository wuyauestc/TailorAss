import Foundation

/// Independent source/mesh checks and real drape regressions for Skirt2.
/// This compares the 2D oracle, not a matched external 3D simulation.
@main
struct ClothSkirt2Regression {
    typealias Drape = GarmentCodeCircleDrape
    typealias V = Drape.Vector3
    enum Failure: Error { case check(String) }
    struct Case {
        let tag: String
        let length: Double
        let flare: Double
        let ruffle: Double
        let material: GarmentCodeClothMaterial.Preset
    }
    struct EdgeKey: Hashable {
        let a: Int, b: Int
        init(_ x: Int, _ y: Int) { a = min(x,y); b = max(x,y) }
    }
    struct SourceMetrics {
        let waist: Double, hem: Double, height: Double, area: Double
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure.check(message) }
    }
    static func near(_ a: Double, _ b: Double, _ message: String, tolerance: Double = 1e-9) throws {
        try require(abs(a-b) <= tolerance, "\(message): \(a) != \(b)")
    }
    static func log(_ text: String) { FileHandle.standardError.write(Data((text+"\n").utf8)) }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        return try encoder.encode(value)
    }
    static func save(_ output: Drape.Output, pattern: GarmentCodePatternFile, tag: String, directory: URL) throws {
        try encode(output).write(to: directory.appendingPathComponent(tag+"-mesh.json"), options: .atomic)
        try encode(output.diagnostics).write(to: directory.appendingPathComponent(tag+"-diagnostics.json"), options: .atomic)
        try encode(pattern).write(to: directory.appendingPathComponent(tag+"-pattern.json"), options: .atomic)
        try output.objString.write(to: directory.appendingPathComponent(tag+".obj"), atomically: true, encoding: .utf8)
    }

    static func compareDefaultOracle(_ actual: GarmentCodePatternFile, root: URL) throws {
        let oracle = try GarmentCodePatternFile.validatedImport(from: Data(contentsOf: root.appendingPathComponent("Tests/NativePattern/Fixtures/skirt-two-panel.json")))
        try require(Set(actual.pattern.panels.keys) == Set(oracle.pattern.panels.keys), "Official panel identities changed")
        try require(actual.pattern.stitches == oracle.pattern.stitches, "Official seam identity/direction changed")
        var maximum = 0.0
        for name in oracle.pattern.panels.keys.sorted() {
            let a = actual.pattern.panels[name]!, b = oracle.pattern.panels[name]!
            try require(a.vertices.count == b.vertices.count && a.edges.count == b.edges.count, "Official boundary topology changed")
            for (p,q) in zip(a.vertices,b.vertices) {
                try require(p.count == 2 && q.count == 2, "Non-2D source coordinate")
                maximum = max(maximum,abs(p[0]-q[0]),abs(p[1]-q[1]))
            }
            for (p,q) in zip(a.edges,b.edges) {
                try require(p.endpoints == q.endpoints && p.label == q.label && p.curvature == q.curvature, "Official straight-edge semantics changed")
            }
        }
        log("official-default maximum_source_coordinate_delta_cm=\(maximum)")
        try require(maximum < 1e-7, "Native source differs from pinned official default")
    }

    /// Polygon shoelace and straight-edge metrics read directly from the source
    /// JSON. They do not use the new mesher's own diagnostic implementation.
    static func metrics(_ document: GarmentCodePatternFile) throws -> SourceMetrics {
        var waist = 0.0, hem = 0.0, area = 0.0, heights: [Double] = []
        for panel in document.pattern.panels.values {
            try require(panel.vertices.count == 4 && panel.edges.count == 4, "Expected uncut four-edge Skirt2 source")
            try require(panel.edges.allSatisfy { $0.curvature == nil }, "Curved panel is not this test program")
            guard let top = panel.edges.first(where: { $0.label == "lower_interface" }) else { throw Failure.check("Missing actual waist interface") }
            let a = panel.vertices[top.endpoints[0]], b = panel.vertices[top.endpoints[1]]
            waist += hypot(a[0]-b[0],a[1]-b[1])/100
            let lowY = panel.vertices.map { $0[1] }.min()!, highY = panel.vertices.map { $0[1] }.max()!
            heights.append((highY-lowY)/100)
            guard let lower = panel.edges.first(where: { edge in
                let a = panel.vertices[edge.endpoints[0]], b = panel.vertices[edge.endpoints[1]]
                return abs(a[1]-lowY) < 1e-8 && abs(b[1]-lowY) < 1e-8
            }) else { throw Failure.check("Missing actual hem") }
            let ha = panel.vertices[lower.endpoints[0]], hb = panel.vertices[lower.endpoints[1]]
            hem += hypot(ha[0]-hb[0],ha[1]-hb[1])/100
            var twiceArea = 0.0
            for i in panel.vertices.indices {
                let a = panel.vertices[i], b = panel.vertices[(i+1)%panel.vertices.count]
                twiceArea += a[0]*b[1]-b[0]*a[1]
            }
            area += abs(twiceArea)/20000
        }
        try near(heights[0],heights[1],"Source front/back heights differ")
        return .init(waist:waist,hem:hem,height:heights[0],area:area)
    }

    static func meshChecks(_ input: Drape.Input, source: GarmentCodePatternFile, metrics: SourceMetrics) throws {
        try require(input.referenceToSimulation.count == input.referencePositions.count, "Reference mapping absent")
        try require(input.referencePositions.count > input.positions.count, "Seams must keep separate rest coordinates")
        try require(input.seamPaths.count == 2, "Both actual side seams must be represented")
        try near(input.waistCircumferenceMeters,metrics.waist,"Source waist metric")
        try near(input.hemCircumferenceMeters,metrics.hem,"Source hem metric")
        try near(input.radialLengthMeters,metrics.height,"Skirt2 diagnostic must retain vertical source height")
        try near(input.referenceAreaSquareMeters,metrics.area,"Straight panel area must survive tessellation",tolerance:1e-8)
        let polygons = source.pattern.panels.values.map { $0.vertices.map { V(x:$0[0]/100,y:$0[1]/100,z:0) } }
        for p in input.referencePositions {
            try require(p.isFinite && abs(p.z) < 1e-10,"Rest geometry is not original flat source")
            let inside = polygons.contains { polygon in
                var signs: [Double] = []
                for i in polygon.indices {
                    let a=polygon[i],b=polygon[(i+1)%polygon.count]
                    signs.append((b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x))
                }
                return signs.allSatisfy { $0 >= -1e-9 } || signs.allSatisfy { $0 <= 1e-9 }
            }
            try require(inside,"A reference mesh vertex escaped the original flat panel")
        }
        var originals = Array(repeating:[Int](),count:input.positions.count)
        for (i,j) in input.referenceToSimulation.enumerated() {
            try require(originals.indices.contains(j),"Invalid weld mapping")
            originals[j].append(i)
        }
        for spring in input.springs + input.bendingSprings {
            let candidates = originals[spring.a].flatMap { a in originals[spring.b].map { b in
                abs((input.referencePositions[a]-input.referencePositions[b]).length-spring.length)
            } }
            try require((candidates.min() ?? .infinity) < 1e-9,"A solver rest length was taken from the draped template instead of flat panels")
        }
        var edges: [EdgeKey:[(Int,Int)]] = [:]
        var outwardScore=0.0
        for index in stride(from:0,to:input.triangleIndices.count,by:3) {
            let ids = input.triangleIndices[index..<index+3].map(Int.init)
            try require(Set(ids).count == 3,"Collapsed triangle")
            let a=input.positions[ids[0]],b=input.positions[ids[1]],c=input.positions[ids[2]]
            let normal=(b-a).cross(c-a),center=(a+b+c)/3
            outwardScore += normal.x*center.x+normal.z*center.z
            for (a,b) in [(ids[0],ids[1]),(ids[1],ids[2]),(ids[2],ids[0])] { edges[.init(a,b),default:[]].append((a,b)) }
        }
        try require(outwardScore > 0,"Consistent triangle winding must face out from the body")
        let stretchEdges=Set(input.springs.map { EdgeKey($0.a,$0.b) })
        try require(stretchEdges == Set(edges.keys),"Stretch constraints must cover actual triangle edges only; an extra opposite diagonal rigidifies each cloth quad")
        for uses in edges.values {
            try require(uses.count <= 2,"Non-manifold welded side seam")
            if uses.count == 2 { try require(uses[0].0 == uses[1].1 && uses[0].1 == uses[1].0,"Inconsistent triangle orientation") }
        }
        for path in input.seamPaths {
            for (a,b) in zip(path,path.dropFirst()) { try require(edges[.init(a,b)]?.count == 2,"Side seam remains an open boundary") }
        }
        try require(input.positions.count-edges.count+input.triangleIndices.count/3 == 0,"Two-panel skirt must form annular topology")
        var boundary: [Int:Set<Int>] = [:]
        for (key,uses) in edges where uses.count == 1 {
            boundary[key.a,default:[]].insert(key.b); boundary[key.b,default:[]].insert(key.a)
        }
        try require(boundary.values.allSatisfy { $0.count == 2 },"Boundary is not a collection of closed loops")
        var pending=Set(boundary.keys),loops=0
        while let first=pending.first {
            loops += 1; var stack=[first]
            while let i=stack.popLast() {
                if pending.remove(i) != nil { stack += Array(boundary[i] ?? []) }
            }
        }
        try require(loops == 2,"Waist and hem must be the only boundary loops")
        let pinnedLength = edges.reduce(0.0) { sum,item in
            let (edge,uses)=item
            return uses.count == 1 && input.pinned[edge.a] && input.pinned[edge.b]
                ? sum+(input.positions[edge.a]-input.positions[edge.b]).length : sum
        }
        log("  source_waist_m=\(metrics.waist) support_polyline_m=\(pinnedLength) flat_area_m2=\(metrics.area)")
        try near(pinnedLength,metrics.waist,"Waist support must retain actual source excess",tolerance:1e-4)
        let pinStrain = input.springs.filter { input.pinned[$0.a] && input.pinned[$0.b] }
            .map { abs((input.positions[$0.a]-input.positions[$0.b]).length/$0.length-1) }.max() ?? .infinity
        try require(pinStrain < 0.001,"A pinned waist segment changed the original flat rest length")
        if let body=input.standardBody {
            let penetration=input.positions.indices.filter { input.pinned[$0] }.map { body.penetration(input.positions[$0]) }.max() ?? .infinity
            try require(penetration < 0.003,"Fixed waist pins begin inside the human collision surface")
        }
        try require(input.garmentStyle == "Skirt2" && input.patternLengthLabel == "垂直裙长","Skirt2 must not use circle-only diagnostic labels")
    }

    static func main() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog=try GarmentCodeParameterCatalog.load(from:root.appendingPathComponent("TrailorAss/Resources/GarmentCodeParameterCatalog.json"))
        let body=GarmentCodeBodyParameters(values:catalog.body)
        let originalBody=try encode(body)
        let environment=ProcessInfo.processInfo.environment
        let directory=URL(fileURLWithPath:environment["GARMENTCODE_CLOTH_OUTPUT_DIR"] ?? "/private/tmp/TailorAssClothSkirt2")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let filter=environment["GARMENTCODE_CLOTH_SKIRT2_CASE_FILTER"]
        var failures:[String]=[],executed:[String]=[]
        var results:[String:Drape.Output]=[:]
        func design(style:String="Skirt2",length:Double=0.2,flare:Double=0,ruffle:Double=1.3) -> GarmentCodeDesignParameters {
            var value=GarmentCodeDesignParameters(catalog:catalog)
            _=value.setValue(.null,at:["meta","upper"]); _=value.setValue(.null,at:["meta","wb"])
            _=value.setValue(.string(style),at:["meta","bottom"])
            _=value.setValue(.number(length),at:["skirt","length"])
            _=value.setValue(.number(flare),at:["skirt","flare"])
            _=value.setValue(.number(ruffle),at:["skirt","ruffle"])
            _=value.setValue(.number(0),at:["skirt","bottom_cut"])
            return value
        }
        if filter == nil || filter == "circle-reference" {
            executed.append("circle-reference")
            do {
                let document=try GarmentCodeNativeGenerator.generate(body:body,design:design(style:"SkirtCircle"))
                let input=try GarmentCodeSkirtDrape.prepare(document:document,body:body)
                let output=try Drape.simulate(input:input)
                let baseline=try JSONDecoder().decode(Drape.Output.self,from:Data(contentsOf:root.appendingPathComponent("Tests/NativePattern/Reports/2026-10-25-3d/generated/circle-0.75-mesh.json")))
                try require(output.positions == baseline.positions,"Circle legacy positions changed")
                try require(output.triangleIndices == baseline.triangleIndices && output.seamPaths == baseline.seamPaths,"Circle topology changed")
                log("circle-reference maximum_position_delta_m=0")
            } catch {failures.append("circle-reference: \(error)");log("FAIL circle-reference: \(error)")}
        }
        let cases:[Case]=[
            .init(tag:"skirt2-default",length:0.2,flare:0,ruffle:1.3,material:.medium),
            .init(tag:"skirt2-longer",length:0.35,flare:0,ruffle:1.3,material:.medium),
            .init(tag:"skirt2-flare10",length:0.2,flare:10,ruffle:1.3,material:.medium),
            .init(tag:"skirt2-soft",length:0.2,flare:0,ruffle:1.3,material:.soft),
            .init(tag:"skirt2-firm",length:0.2,flare:0,ruffle:1.3,material:.firm)
        ]
        for item in cases where filter == nil || filter == item.tag {
            executed.append(item.tag)
            do {
                let document=try GarmentCodeNativeGenerator.generate(body:body,design:design(length:item.length,flare:item.flare,ruffle:item.ruffle))
                let before=try encode(document)
                if item.tag == "skirt2-default" {try compareDefaultOracle(document,root:root)}
                let measured=try metrics(document)
                try near(measured.waist,(body["waist"] ?? 0)*item.ruffle/100,"Ruffle must remain real source excess")
                var settings=Drape.Settings();settings.bodyMode = .standardMannequin;settings.material=item.material
                settings.useSurfaceCollision=true;settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
                settings.solverIterations=32
                let input=try GarmentCodeSkirtDrape.prepare(document:document,body:body,settings:settings)
                try meshChecks(input,source:document,metrics:measured)
                let initialStrain=input.springs.map { abs((input.positions[$0.a]-input.positions[$0.b]).length/$0.length-1) }.max() ?? .infinity
                log("  grid_columns_per_panel=\(input.panelColumns) rows=\(input.radialSegments) initial_max_strain=\(initialStrain)")
                if let spring=input.springs.max(by:{abs((input.positions[$0.a]-input.positions[$0.b]).length/$0.length-1)<abs((input.positions[$1.a]-input.positions[$1.b]).length/$1.length-1)}) {
                    let width=input.panelColumns+1,stride=width*(input.radialSegments+1)
                    let sources=input.referenceToSimulation.indices.filter {input.referenceToSimulation[$0] == spring.a || input.referenceToSimulation[$0] == spring.b}
                    let locations=sources.map { "panel\($0/stride) row\(($0%stride)/width) col\(($0%stride)%width)" }.joined(separator:", ")
                    log("  initial_worst \(spring.a)-\(spring.b) rest=\(spring.length) actual=\((input.positions[spring.a]-input.positions[spring.b]).length) source=\(locations)")
                }
                try require(initialStrain < 1,"Initial assembly stretched an actual source edge by more than 100%; check for inside-leg projection jumps")
                let output=try Drape.simulate(input:input)
                try save(output,pattern:document,tag:item.tag,directory:directory)
                results[item.tag]=output
                let d=output.diagnostics
                log("\(item.tag) seconds=\(d.computationSeconds) strain=\(d.maxEdgeStrain) speed=\(d.maxSpeedMetersPerSecond) bodyPenetration=\(d.maxBodyPenetrationMeters) intersections=\(d.surfaceIntersectionCount.map(String.init) ?? "missing") converged=\(d.converged)")
                if !d.converged || d.maxEdgeStrain >= 0.08 {
                    let worst=input.springs.sorted {abs((output.positions[$0.a]-output.positions[$0.b]).length/$0.length-1)>abs((output.positions[$1.a]-output.positions[$1.b]).length/$1.length-1)}.prefix(4)
                    for spring in worst {
                        let stride=(input.panelColumns+1)*(input.radialSegments+1)
                        let sourceIndices=input.referenceToSimulation.indices.filter { input.referenceToSimulation[$0] == spring.a || input.referenceToSimulation[$0] == spring.b }
                        let locations=sourceIndices.map { "panel\($0/stride) row\(($0%stride)/(input.panelColumns+1)) col\(($0%stride)%(input.panelColumns+1))" }.joined(separator:", ")
                        log("  worst \(spring.a)-\(spring.b) rest=\(spring.length) actual=\((output.positions[spring.a]-output.positions[spring.b]).length) pinned=\(input.pinned[spring.a])-\(input.pinned[spring.b]) shear=\(spring.isShear) source=\(locations)")
                    }
                }
                let after=try encode(document)
                let afterBody=try encode(body)
                try require(after == before,"Drape modified original source pattern")
                try require(afterBody == originalBody,"Drape modified original body measurements")
                try require(output.positions.allSatisfy(\.isFinite),"Non-finite cloth")
                try require(output.triangleIndices == input.triangleIndices,"Solver changed topology")
                try near(d.referenceAreaSquareMeters,measured.area,"Reference area diagnostic")
                try near(d.waistCircumferenceMeters,measured.waist,"Ruffled source waist was replaced by body waist")
                try near(d.hemCircumferenceMeters,measured.hem,"Source hem changed")
                try near(d.totalFabricMassKg ?? -1,measured.area*item.material.parameters.arealDensityKgPerSquareMeter,"Areal mass must use original paper area")
                try require(d.maxSeamGapMeters == 0,"Side seam gap")
                try require(d.maxEdgeStrain < 0.08,"Original 8% strain gate")
                try require(d.maxSpeedMetersPerSecond < 0.025,"Original .025m/s motion gate")
                try require(d.maxBodyPenetrationMeters < 0.003,"Original 3mm body gate")
                try require(d.surfaceIntersectionCount == 0,"Final non-adjacent surface intersection")
                try require(d.converged,"Original sustained convergence gate")
                var cancelled=false
                do {_=try Drape.simulate(input:input,isCancelled:{true})} catch is CancellationError {cancelled=true}
                try require(cancelled,"Cancelled Skirt2 must not return a mesh")
            } catch {failures.append("\(item.tag): \(error)");log("FAIL \(item.tag): \(error)")}
        }
        do { if let base=results["skirt2-default"] {
            if let long=results["skirt2-longer"] {
                try require(long.diagnostics.radialLengthMeters > base.diagnostics.radialLengthMeters+0.1,"Length parameter did not change source height")
                try require((long.positions.map(\.y).min() ?? 0)<(base.positions.map(\.y).min() ?? 0)-0.03,"Length did not change actual 3D extent")
            }
            if let flare=results["skirt2-flare10"] {
                try require(flare.diagnostics.hemCircumferenceMeters > base.diagnostics.hemCircumferenceMeters+0.3,"Flare did not change actual source hem")
                let radius: (Drape.Output)->Double = { $0.positions.map { hypot($0.x,$0.z) }.max() ?? 0 }
                try require(radius(flare) > radius(base)+0.01,"Flare did not change actual 3D horizontal extent")
            }
            for name in ["soft","firm"] {
                guard let output=results["skirt2-"+name] else {continue}
                try require(base.triangleIndices == output.triangleIndices && base.positions.count == output.positions.count,"Material changed meshing")
                let rms=sqrt(zip(base.positions,output.positions).reduce(0){$0+($1.0-$1.1).lengthSquared}/Double(base.positions.count))
                log("material-\(name) actual_final_position_rms_delta_m=\(rms)")
                try require(rms > 1e-5,"Material only changed metadata")
            }
        }} catch { failures.append("parameter-response: \(error)");log("FAIL parameter-response: \(error)") }
        if filter == nil || filter == "prepare-boundaries" {
            executed.append("prepare-boundaries")
            for ratio in [1.0,1.5] {
                do {
                    // A waist-sized unflared tube cannot clear this body's
                    // hips. Test the lower gather bound with real hem flare.
                    let flare=ratio == 1 ? 20.0 : 0.0
                    let document=try GarmentCodeNativeGenerator.generate(body:body,design:design(flare:flare,ruffle:ratio))
                    let before=try encode(document),measured=try metrics(document)
                    var settings=Drape.Settings();settings.bodyMode = .standardMannequin;settings.material = .medium
                    settings.useSurfaceCollision=true;settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
                    settings.solverIterations=32
                    let input=try GarmentCodeSkirtDrape.prepare(document:document,body:body,settings:settings)
                    try meshChecks(input,source:document,metrics:measured)
                    let after=try encode(document)
                    try require(before == after,"Boundary preparation modified source")
                    log("prepare-only gather=\(ratio) flare_cm=\(flare) PASS source/pins/manifold")
                } catch {failures.append("prepare-gather-\(ratio): \(error)");log("FAIL prepare-gather-\(ratio): \(error)")}
            }
            for name in ["cut","waistband","gather-out-of-range"] {
                do {
                    var value=design()
                    if name == "cut" {_=value.setValue(.number(0.5),at:["skirt","bottom_cut"])}
                    else if name == "waistband" {_=value.setValue(.string("StraightWB"),at:["meta","wb"])}
                    else {_=value.setValue(.number(1.6),at:["skirt","ruffle"])}
                    let document=try GarmentCodeNativeGenerator.generate(body:body,design:value)
                    var rejected=false
                    do {_=try GarmentCodeSkirtDrape.prepare(document:document,body:body)} catch {rejected=true}
                    try require(rejected,"Unsupported \(name) disappeared silently")
                } catch {failures.append("reject-\(name): \(error)")}
            }
            do {
                let document=try GarmentCodeNativeGenerator.generate(body:body,design:design(ruffle:1))
                let before=try encode(document)
                var settings=Drape.Settings();settings.bodyMode = .standardMannequin
                settings.bodyResourceDirectory=root.appendingPathComponent("TrailorAss/Resources")
                var fitRejected=false
                do {_=try GarmentCodeSkirtDrape.prepare(document:document,body:body,settings:settings)}
                catch Drape.DrapeError.unsupported(let reason) {fitRejected=reason.contains("围度不足")}
                let after=try encode(document)
                try require(fitRejected,"An unflared waist-sized tube must report insufficient body clearance explicitly")
                try require(before == after,"Fit rejection modified source dimensions")
                log("prepare-only insufficient-fit ruffle1/flare0 PASS explicit rejection")
            } catch {failures.append("reject-insufficient-fit: \(error)")}
        }
        try require(!executed.isEmpty,"Unknown Skirt2 filter")
        let summary:[String:Any]=["executed":executed,"passed":failures.isEmpty,"failures":failures,"sourceFixture":"skirt-two-panel.json","gates":"Existing sustained convergence, .025m/s motion, 8% strain, 3mm body estimate and zero final cloth surface crossings; not real material calibration."]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("skirt2-summary.json"),options:.atomic)
        if !failures.isEmpty {throw Failure.check(failures.joined(separator:"\n"))}
        print("PASS: Skirt2 regression checks (\(executed.joined(separator:", ")))")
    }
}
