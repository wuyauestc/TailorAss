#!/usr/bin/env python3
"""Independent exact full-polyline seam audit of a saved terminal output.

Uses every stored Float64 source-arc knot, with exact Fraction interpolation.
Between union knots the paired position difference is affine, so its squared
norm is convex and its maximum is attained at a knot. No simulation, geometry
repair, new acceptance capability, or fixed-density sampling is performed.
Gathered seams are explicitly excluded from the continuous correspondence
claim until their physical folding correspondence is implemented.
"""
from pathlib import Path
from fractions import Fraction as F
from bisect import bisect_right
import argparse, hashlib, json, math


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def vector(p):
    a = [p[k] for k in ('x', 'y', 'z')] if isinstance(p, dict) else p
    assert len(a) == 3 and all(math.isfinite(x) for x in a)
    return tuple(F(x) for x in a)


def curve(path, positions, direction):
    assert direction in ('forward', 'reverse')
    knots = [F(x) for x in path['sourceArcFractions']]
    points = [positions[i] for i in path['vertexIDs']]
    assert len(knots) == len(points) >= 2 and knots[0] == 0 and knots[-1] == 1
    assert all(a < b for a, b in zip(knots, knots[1:]))
    if direction == 'reverse':
        knots, points = [1-x for x in reversed(knots)], list(reversed(points))
    return knots, points


def at(c, t):
    knots, points = c
    if t == 1:
        return points[-1]
    i = bisect_right(knots, t)-1
    assert 0 <= i < len(knots)-1
    w = (t-knots[i])/(knots[i+1]-knots[i])
    return tuple(a+(b-a)*w for a, b in zip(points[i], points[i+1]))


def maximum_squared_gap(a, b):
    knots = sorted(set(a[0]+b[0]))
    pairs = [(sum((x-y)**2 for x, y in zip(at(a, t), at(b, t))), t) for t in knots]
    value, t = max(pairs, key=lambda x: (x[0], -x[1]))
    return value, t, len(knots)


def self_test():
    # End anchors coincide while an interior source knot opens by 8 mm.
    a = ([F(0), F(1)], [(F(0), F(0), F(0)), (F(1), F(0), F(0))])
    b = ([F(0), F(1, 3), F(1)], [a[1][0], (F(1, 3), F(1, 125), F(0)), a[1][-1]])
    gap, t, n = maximum_squared_gap(a, b)
    assert gap == F(1, 125)**2 and t == F(1, 3) and n == 3
    assert at(a, F(0)) == at(b, F(0)) and at(a, F(1)) == at(b, F(1))
    c = ([F(0), F(1, 7), F(1)], [a[1][0], (F(1, 7), F(0), F(0)), a[1][-1]])
    assert maximum_squared_gap(a, c)[0] == 0
    assert maximum_squared_gap(b, a)[0] == gap
    # A reversed Float64 knot is the exact rational 1-f, not rounded Double
    # subtraction. The two differ even when the actual coordinates are tiny.
    f = float.fromhex('0x1.0000000000001p-2')
    reversed_curve = curve({'sourceArcFractions': [0.0, f, 1.0],
                            'vertexIDs': [0, 1, 2]},
                           [a[1][0], (F(f), F(1, 125), F(0)), a[1][-1]], 'reverse')
    assert reversed_curve[0][1] == 1-F(f)
    assert reversed_curve[0][1] != F(1-f)
    return {'passed': True, 'exactInteriorBulgeRejectedDespiteClosedEndAnchors': True,
            'distinctKnotsWithIdenticalPolylineHaveZeroGap': True,
            'reversalPreservesExactStoredKnot': True}


def audit(case):
    paths = [case/n for n in ['case-summary.json', 'complete-initial-input.json',
             'complete-sewing-plan.json', 'validated-output.json', 'validated-proof.json']]
    summary, source, plan, output, proof = [json.loads(p.read_text()) for p in paths]
    paper_path = case/'complete-paper-source.json'
    paper = json.loads(paper_path.read_text())
    paths.append(paper_path)
    assert summary['resultAccepted'] and summary['stopReason'] == 'stableValidated'
    assert summary['sourceSHA256'] == source['sourceSHA256'] == plan['sourceSHA256'] == proof['sourceSHA256']
    assert output['triangleIndices'] == source['triangleIndices']
    assert len(output['positions']) == len(source['positions']) and not any(source['pinMask'])
    points = list(map(vector, output['positions']))
    edge = lambda x: (x['panelID'], x['edgeIndex'])
    boundary = {edge(p['edge']): p for p in plan['allBoundaryPaths']}
    assert len(boundary) == len(plan['allBoundaryPaths'])
    origins = {}
    for c in plan['constraints']:
        for o in c['origins']:
            identity = (o['seamID'], edge(o['a']['edge']), edge(o['b']['edge']),
                        o['aDirection'], o['bDirection'], json.dumps(o['intent'], sort_keys=True), o['rightWrong'])
            key = o['stitchIndex']
            assert key not in origins or origins[key] == identity
            origins[key] = identity
    anchors = {}
    for a in plan['anchors']:
        anchors.setdefault(a['stitchIndex'], []).append(a)
    assert set(origins) == set(anchors), 'Missing original seam identity; cannot infer it from geometry'
    assert set(anchors) == set(range(len(paper['pattern']['stitches']))), 'The plan must include every original source seam'
    seams, excluded = [], []
    limit2 = F(0.0005)**2
    for key in sorted(anchors):
        seam_id, ae, be, ad, bd, intent_json, right_wrong = origins[key]
        stitch = paper['pattern']['stitches'][key]
        assert len(stitch) >= 2
        assert ae == (stitch[0]['panel'], stitch[0]['edge'])
        assert be == (stitch[1]['panel'], stitch[1]['edge'])
        intent = json.loads(intent_json)
        assert len(intent) == 1
        kind = next(iter(intent))
        assert kind in ('ordinary', 'eased', 'gathered')
        if kind == 'gathered':
            excluded.append({'seamID': seam_id, 'stitchIndex': key, 'reason': 'Physical gathered correspondence is not certified by normalized arc matching'})
            continue
        a, b = curve(boundary[ae], points, ad), curve(boundary[be], points, bd)
        value, t, count = maximum_squared_gap(a, b)
        seams.append({'seamID': seam_id, 'stitchIndex': key, 'intent': kind, 'rightWrong': right_wrong,
                      'aEdge': list(ae), 'bEdge': list(be), 'unionKnots': count,
                      'maximumGapMetersApprox': math.sqrt(float(value)),
                      'exactMaximumGapSquared': [str(value.numerator), str(value.denominator)],
                      'maximizingSeamFraction': [str(t.numerator), str(t.denominator)],
                      'belowOriginalHalfMillimeter': value < limit2})
    return {'auditCompleted': True, 'scope': 'Exact full-polyline ordinary/eased saved output audit; no physical solver or Native validator reexecution',
            'sourceSHA256': source['sourceSHA256'], 'originalNumericalRAccepted': True,
            'everySourceSeamHasContinuousClosureEvidence': not excluded and all(x['belowOriginalHalfMillimeter'] for x in seams),
            'continuousSeams': seams, 'gatheredExcluded': excluded, 'gatheredExcludedCount': len(excluded),
            'maximumMeasuredContinuousGapMetersApprox': max((s['maximumGapMetersApprox'] for s in seams), default=None),
            'inputSHA256': {str(p): sha(p) for p in paths}, 'auditorSHA256': sha(Path(__file__)),
            'bodyFitOrVisualEquivalenceVerified': False, 'simulationReexecuted': False}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--case', type=Path)
    p.add_argument('--output', type=Path)
    p.add_argument('--self-test', action='store_true')
    a = p.parse_args()
    if a.self_test:
        print(json.dumps(self_test()))
    if a.case:
        if not a.output:
            p.error('--case requires --output')
        data = audit(a.case.resolve())
        a.output.parent.mkdir(parents=True, exist_ok=True)
        with a.output.open('x') as f:
            json.dump(data, f, indent=2)
            f.write('\n')
        print(json.dumps({k: data[k] for k in ['auditCompleted', 'everySourceSeamHasContinuousClosureEvidence', 'gatheredExcludedCount', 'maximumMeasuredContinuousGapMetersApprox']}))
    elif not a.self_test:
        p.error('Specify --self-test or --case')
