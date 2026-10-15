using System.Collections.Generic;
using UnityEngine;
using GarmentSimPOC.Data;
using GarmentSimPOC.Core;

namespace GarmentSimPOC.RouteA
{
    /// <summary>
    /// 路线 A：将 2D 裁片顶点 / 边点 / 内部点映射到 3D 人台表面或附近解剖位置。
    /// 每条边界边按 role 走不同映射规则；内部点先走基础包裹，再由装配器做约束平滑。
    /// 单位：输入 cm，输出 cm（调用方负责 ×0.01 转米）。
    ///
    /// 方向约定：各边 fromVertex→toVertex 方向不统一，所有目标曲线统一以
    /// "t=0 为低端/腋点/外侧，t=1 为高端/肩点/中心"定义，并通过顶点 y/|x| 自动翻转。
    /// </summary>
    public static class GarmentMapper
    {
        class PieceCtx
        {
            public Dictionary<string, VertexData> vById = new Dictionary<string, VertexData>();
            public float maxAbsX;
            public float maxY;
            public bool isFront, isBack, isSleeve;
            public int sleeveSide; // +1 左 / -1 右（仅袖片有效）
            public Vector3 shoulderDir, shoulderAway, shoulderSide;
        }

        public static Vector3[] MapPiece(PieceData piece, List<PolygonTriangulator.PointInfo> pts)
        {
            var ctx = BuildCtx(piece);
            var result = new Vector3[pts.Count];
            for (int i = 0; i < pts.Count; i++)
                result[i] = MapPoint(piece, ctx, pts[i]);
            return result;
        }

        /// <summary>单点映射（缝合采样用）。</summary>
        public static Vector3 MapSingle(PieceData piece, PolygonTriangulator.PointInfo pt)
        {
            return MapPoint(piece, BuildCtx(piece), pt);
        }

        static PieceCtx BuildCtx(PieceData piece)
        {
            var c = new PieceCtx();
            foreach (var v in piece.vertices) c.vById[v.id] = v;
            float maxX = 0f, maxY = 0f;
            foreach (var v in piece.vertices)
            {
                maxX = Mathf.Max(maxX, Mathf.Abs(v.x));
                maxY = Mathf.Max(maxY, v.y);
            }
            c.maxAbsX = maxX;
            c.maxY = maxY;
            c.isFront = piece.type == "front";
            c.isBack = piece.type == "back";
            c.isSleeve = piece.type == "sleeveLeft" || piece.type == "sleeveRight";
            c.sleeveSide = piece.type == "sleeveLeft" ? +1 : (piece.type == "sleeveRight" ? -1 : 0);
            if (c.isSleeve)
            {
                c.shoulderDir = new Vector3(0.18f * c.sleeveSide, -0.98f, 0f).normalized;
                c.shoulderAway = Vector3.ProjectOnPlane(new Vector3(c.sleeveSide, 0f, 0f), c.shoulderDir).normalized;
                c.shoulderSide = Vector3.Cross(c.shoulderAway, c.shoulderDir).normalized;
            }
            return c;
        }

        static Vector3 MapPoint(PieceData piece, PieceCtx ctx, PolygonTriangulator.PointInfo pt)
        {
            if (pt.edgeIndex >= 0 && pt.edgeIndex < piece.edges.Count)
            {
                var edge = piece.edges[pt.edgeIndex];
                switch (edge.role)
                {
                    case "hem":
                    case "side":
                        return ctx.isSleeve ? SleeveTube(ctx, pt.p) : TorsoWrap(ctx, pt.p, ctx.isBack);
                    case "sleeveCap":
                        return ctx.isSleeve ? SleeveCap(ctx, edge, pt) : BodyArmhole(ctx, edge, pt);
                    case "shoulder":
                        return ShoulderCurve(ctx, edge, pt);
                    case "neckline":
                        return NecklineCurve(ctx, edge, pt);
                    case "sleeveCuff":
                        return SleeveTube(ctx, pt.p);
                }
            }
            return ctx.isSleeve ? SleeveTube(ctx, pt.p) : TorsoWrap(ctx, pt.p, ctx.isBack);
        }

        /// <summary>tBaseToTop：根据顶点 y 坐标把 edgeT 归一成 腋/低端(t=0)→肩/顶端(t=1)。</summary>
        static float BaseToTop(PieceCtx ctx, EdgeData edge, float edgeT)
        {
            float yFrom = ctx.vById.TryGetValue(edge.fromVertex, out var a) ? a.y : 0f;
            float yTo = ctx.vById.TryGetValue(edge.toVertex, out var b) ? b.y : 0f;
            return yFrom <= yTo ? edgeT : 1f - edgeT;
        }

        /// <summary>tOutToCenter：根据 |x| 把 edgeT 归一成 外侧(t=0)→中心(t=1)。</summary>
        static float OutToCenter(PieceCtx ctx, EdgeData edge, float edgeT)
        {
            float xFrom = ctx.vById.TryGetValue(edge.fromVertex, out var a) ? Mathf.Abs(a.x) : 0f;
            float xTo = ctx.vById.TryGetValue(edge.toVertex, out var b) ? Mathf.Abs(b.x) : 0f;
            return xFrom >= xTo ? edgeT : 1f - edgeT;
        }

        static int EdgeSide(PieceCtx ctx, EdgeData edge, bool frontConvention)
        {
            float avg = 0f;
            if (ctx.vById.TryGetValue(edge.fromVertex, out var a) && ctx.vById.TryGetValue(edge.toVertex, out var b))
                avg = (a.x + b.x) * 0.5f;
            int sign = avg >= 0f ? +1 : -1;
            // 前片：+x=穿着者左；后片镜像：+x=穿着者右
            return frontConvention ? sign : -sign;
        }

        // ---- 躯干基础包裹（腋下区域 + 内部点） ----
        // 坐标约定（与 EdgeSide 一致）：前片 +x → +X（穿着者左）；后片 +x → -X（镜像）。
        static Vector3 TorsoWrap(PieceCtx ctx, Vector2 p, bool isBack)
        {
            float h = BodyProfile.GarmentHemH + p.y;
            BodyProfile.TorsoEllipse(h, true, out float a, out float b);
            float span = ctx.maxAbsX > 0 ? ctx.maxAbsX : 22f;
            float theta = (p.x / span) * (Mathf.PI * 0.5f);
            if (isBack) theta = -theta;
            float z = Mathf.Abs(b * Mathf.Cos(theta));
            if (isBack) z = -z;
            return new Vector3(a * Mathf.Sin(theta), h, z);
        }

        // ---- 袖片管状包裹 ----
        static Vector3 SleeveTube(PieceCtx ctx, Vector2 p)
        {
            float total = ctx.maxY > 0 ? ctx.maxY : 24f;
            float t = Mathf.Clamp01(p.y / total);
            float r = Mathf.Lerp(4.77f, 5.70f, t);
            Vector3 axisPt = BodyProfile.ShoulderTip(ctx.sleeveSide) + ctx.shoulderDir * (total - p.y);
            float span = ctx.maxAbsX > 0 ? ctx.maxAbsX : 15f;
            float phi = -Mathf.PI * (p.x / span);
            return axisPt + r * (Mathf.Cos(phi) * ctx.shoulderAway + Mathf.Sin(phi) * ctx.shoulderSide);
        }

        // ---- 袖片 cap 弧线（比身体袖窿外扩一点，布料盖在肩臂外侧） ----
        static Vector3 SleeveCap(PieceCtx ctx, EdgeData edge, PolygonTriangulator.PointInfo pt)
        {
            float t = BaseToTop(ctx, edge, pt.edgeT);
            // 本数据约定：两条 cap 边中，fromVertex 为基部的视作前半（对称形状，前后半等价）
            bool frontHalf = ctx.vById.TryGetValue(edge.fromVertex, out var vf) && vf.y < (ctx.maxY * 0.9f);
            float outward = 3.0f;
            return BodyProfile.ArmholeCurve(ctx.sleeveSide, frontHalf, t, outward);
        }

        // ---- 身体裁片的袖窿边 ----
        static Vector3 BodyArmhole(PieceCtx ctx, EdgeData edge, PolygonTriangulator.PointInfo pt)
        {
            int side = EdgeSide(ctx, edge, ctx.isFront);
            float t = BaseToTop(ctx, edge, pt.edgeT);
            return BodyProfile.ArmholeCurve(side, ctx.isFront, t, 0f);
        }

        // ---- 肩线：t=0 肩点 → t=1 颈侧（按 |x| 归一） ----
        static Vector3 ShoulderCurve(PieceCtx ctx, EdgeData edge, PolygonTriangulator.PointInfo pt)
        {
            int side = EdgeSide(ctx, edge, ctx.isFront);
            float t = OutToCenter(ctx, edge, pt.edgeT);
            return Vector3.Lerp(BodyProfile.ShoulderTip(side), BodyProfile.NeckSide(side, ctx.isFront), t);
        }

        // ---- 领口线：t=0 颈侧 → t=1 颈中心（按 |x| 归一） ----
        static Vector3 NecklineCurve(PieceCtx ctx, EdgeData edge, PolygonTriangulator.PointInfo pt)
        {
            int side = EdgeSide(ctx, edge, ctx.isFront);
            float t = OutToCenter(ctx, edge, pt.edgeT);
            Vector3 sidePt = BodyProfile.NeckSide(side, ctx.isFront);
            Vector3 center = ctx.isFront ? BodyProfile.NeckCenterFront : BodyProfile.NeckCenterBack;
            return Vector3.Lerp(sidePt, center, t);
        }
    }
}
