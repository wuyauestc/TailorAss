import Foundation
import CryptoKit

/// Restores complete original source parameters, never fills missing controls
/// from catalog defaults. Native capture must still regenerate and verify SHA.
enum GarmentCodeJointParameters {
    struct Restored {
        let body:GarmentCodeBodyParameters
        let design:GarmentCodeDesignParameters
        let panelNames:[String:String]
    }
    enum RestoreError:LocalizedError {
        case missingSource,body(String),design(String),catalogMismatch
        var errorDescription:String? {
            switch self {
            case .missingSource:return "这份纸样没有完整的人体与设计参数来源。请返回纸样设计重新生成。"
            case let .body(title):return "纸样的人体参数不完整或不一致（\(title)）。请核对原尺寸后重新生成纸样。"
            case let .design(path):return "纸样的设计参数不完整或不一致（\(path)）。请在纸样设计中确认参数后重新生成。"
            case .catalogMismatch:return "纸样的参数目录版本不一致。无法用默认值代替原参数，请重新生成纸样。"
            }
        }
    }
    static func signature(_ document:GarmentCodePatternFile)throws->String {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        return SHA256.hash(data:try encoder.encode(document)).map{String(format:"%02x",$0)}.joined()
    }
    static func restore(document:GarmentCodePatternFile,catalog:GarmentCodeParameterCatalog)throws->Restored {
        guard case let .object(rawBody)?=document.parameters?["body"],
              case let .object(rawDesign)?=document.parameters?["design"] else {throw RestoreError.missingSource}
        func bodyIssue(_ key:String)->RestoreError {.body(GarmentCodeChinese.body[key]?.title ?? "派生尺寸")}
        var values:[String:Double]=[:]
        guard rawBody.count<=512 else {throw bodyIssue("")}
        for (key,value) in rawBody {
            guard case let .number(number)=value,number.isFinite else {throw bodyIssue(key)}
            values[key]=number
        }
        let required=Set(catalog.body.keys).union(catalog.bodyDerivedFormulas?.keys.map{$0} ?? [])
        for key in required where values[key]==nil {throw bodyIssue(key)}
        let body=GarmentCodeBodyParameters(values:values)
        guard Set(body.values.keys)==Set(values.keys) else {throw bodyIssue("")}
        for (key,value) in values where body.values[key]?.bitPattern != value.bitPattern {throw bodyIssue(key)}
        guard Set(rawDesign.keys)==Set(catalog.design.keys) else {throw RestoreError.catalogMismatch}
        var design=GarmentCodeDesignParameters(catalog:catalog)
        func apply(_ node:GarmentCodeParameterNode,_ raw:JSONValue,path:[String])throws {
            guard case let .object(object)=raw,let expected=node.jsonValue.objectValue,
                  Set(object.keys)==Set(expected.keys) else {throw RestoreError.design(GarmentCodeChinese.parameter(path)?.title ?? "原始设计")}
            // A group may contain a real child parameter named `type` (for
            // example sleeve.cuff.type). Only a node with a scalar type owns
            // type metadata; the child still receives all recursive checks.
            let metadataKeys=["range","default_prob"]+(node.type == nil ? [] : ["type"])
            for metadata in metadataKeys where object[metadata] != expected[metadata] {throw RestoreError.catalogMismatch}
            if node.hasValueKey {
                guard let value=object["v"],design.setValue(value,at:path) else {throw RestoreError.design(GarmentCodeChinese.parameter(path)?.title ?? "原始设计")}
            }
            for key in node.children.keys.sorted() {try apply(node.children[key]!,object[key]!,path:path+[key])}
        }
        for key in catalog.design.keys.sorted() {try apply(catalog.design[key]!,rawDesign[key]!,path:[key])}
        guard design.validationMessages().isEmpty else {throw RestoreError.design("取值范围")}
        // This also catches metadata changes such as signed-zero values which
        // ordinary JSONValue numeric equality intentionally considers equal.
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        guard try encoder.encode(design.jsonValue)==encoder.encode(JSONValue.object(rawDesign)) else {throw RestoreError.catalogMismatch}
        return .init(body:body,design:design,panelNames:Dictionary(uniqueKeysWithValues:document.pattern.panels.keys.map{($0,GarmentCodeChinese.panel($0))}))
    }
}
