using System.Collections.Generic;
using UnityEngine;

namespace GarmentSimPOC.Core
{
    /// <summary>
    /// M 码人台（165cm）的身体截面剖面数据 + 关键解剖点。
    /// 单位：cm。人台网格与成衣映射共用同一份数据，保证两者一致。
    /// 坐标系：x 右为正（观察者视角，即穿着者左侧为 +X），y 离地高度，z 前为正。
    /// </summary>
    public static class BodyProfile
    {
        // 躯干横截面椭圆剖面：(height, a=半宽, b=半深)
        static readonly (float h, float a, float b)[] torsoTable =
        {
            ( 80f, 16.5f, 12.0f),
            ( 90f, 17.0f, 12.5f),   // 臀围 92
            (100f, 15.0f, 11.0f),
            (108f, 13.5f, 10.0f),   // 腰围 68
            (116f, 15.0f, 11.0f),
            (122f, 16.0f, 11.5f),   // 胸围 88
            (128f, 15.5f, 11.0f),   // 腋下
            (136f, 15.0f, 10.5f),
            (142f, 14.5f, 10.0f),
            (148f, 11.0f,  8.5f),   // 肩以上收口
            (152f,  6.0f,  5.5f),   // 颈根
        };

        public const float Ease = 1.06f;          // 成衣松量系数
        public const float GarmentHemH = 90f;     // 裁片 y=0 对应离地高度
        public const float ArmpitH = 128f;        // 腋点高度
        public const float ShoulderTipH = 143f;   // 肩点高度
        public const float ShoulderTipX = 19f;    // 肩点横向位置（半肩宽）
        public const float NeckSideX = 6.5f;      // 颈侧点横向
        public const float NeckSideH = 145f;      // 颈侧点高度
        public const float NeckFrontH = 140f;     // 前颈中心高度
        public const float NeckBackH = 144.5f;    // 后颈中心高度
        public const float NeckFrontZ = 5.5f;
        public const float NeckBackZ = -5.0f;

        /// <summary>指定高度的躯干椭圆半轴（含松量）。</summary>
        public static void TorsoEllipse(float h, bool withEase, out float a, out float b)
        {
            var t = torsoTable;
            if (h <= t[0].h) { a = t[0].a; b = t[0].b; }
            else if (h >= t[t.Length - 1].h) { a = t[t.Length - 1].a; b = t[t.Length - 1].b; }
            else
            {
                int i = 0;
                while (i < t.Length - 2 && t[i + 1].h < h) i++;
                float f = (h - t[i].h) / (t[i + 1].h - t[i].h);
                a = Mathf.Lerp(t[i].a, t[i + 1].a, f);
                b = Mathf.Lerp(t[i].b, t[i + 1].b, f);
            }
            if (withEase) { a *= Ease; b *= Ease; }
        }

        /// <summary>肩点（±X）。</summary>
        public static Vector3 ShoulderTip(int side) => new Vector3(ShoulderTipX * side, ShoulderTipH, 0f);

        /// <summary>腋点（±X）：躯干侧面椭圆在腋高的外侧点（含松量）。</summary>
        public static Vector3 Armpit(int side)
        {
            TorsoEllipse(ArmpitH, true, out float a, out _);
            return new Vector3(a * side, ArmpitH, 0f);
        }

        /// <summary>颈侧点（±X, isFront 区分前后倾）。</summary>
        public static Vector3 NeckSide(int side, bool isFront) =>
            new Vector3(NeckSideX * side, NeckSideH, isFront ? 1.5f : -1.5f);

        public static Vector3 NeckCenterFront => new Vector3(0f, NeckFrontH, NeckFrontZ);
        public static Vector3 NeckCenterBack => new Vector3(0f, NeckBackH, NeckBackZ);

        /// <summary>
        /// 袖窿（手臂孔）目标曲线。front/back 裁片的 sleeveCap 边与袖片 cap 边都映射到这条线上，
        /// 使缝合边在 3D 中天然重合。
        /// side: +1 左 / -1 右。isFrontHalf: 前半（前片/袖前）或后半。
        /// t: 0=腋点 → 1=肩点。
        /// </summary>
        public static Vector3 ArmholeCurve(int side, bool isFrontHalf, float t, float outwardOffset = 0f)
        {
            Vector3 armpit = Armpit(side);
            Vector3 tip = ShoulderTip(side);
            float zSign = isFrontHalf ? 1f : -1f;
            // 三段折线 + 平滑：腋点 → 前/后鼓出 → 肩点
            Vector3 mid = new Vector3(side * (ShoulderTipX - 1.5f), 135.5f, zSign * 4.2f);
            Vector3 p;
            if (t < 0.5f) p = Vector3.Lerp(armpit, mid, t * 2f);
            else p = Vector3.Lerp(mid, tip, (t - 0.5f) * 2f);
            if (outwardOffset > 0f)
            {
                // 沿侧向（±X）外推，用于袖片 cap（布料在肩臂外侧）
                float w = Mathf.Sin(t * Mathf.PI); // 两端不外推
                p += new Vector3(side * outwardOffset * w, outwardOffset * 0.35f * w, 0f);
            }
            return p;
        }
    }
}
