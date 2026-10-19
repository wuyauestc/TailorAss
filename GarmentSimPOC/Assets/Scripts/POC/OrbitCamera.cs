using UnityEngine;

namespace GarmentSimPOC.POC
{
    /// <summary>简单环绕相机：左键拖拽环绕，滚轮缩放。</summary>
    public class OrbitCamera : MonoBehaviour
    {
        public Vector3 target = Vector3.zero;
        public float distance = 2.6f;
        float yaw = 180f, pitch = 8f;

        void LateUpdate()
        {
#if UNITY_IOS && !UNITY_EDITOR
            if (Input.touchCount == 1)
            {
                var touch = Input.GetTouch(0);
                if (touch.phase == TouchPhase.Moved)
                {
                    yaw += touch.deltaPosition.x * 0.18f;
                    pitch -= touch.deltaPosition.y * 0.18f;
                    pitch = Mathf.Clamp(pitch, -60f, 80f);
                }
            }
            else if (Input.touchCount == 2)
            {
                var a = Input.GetTouch(0);
                var b = Input.GetTouch(1);
                float previous = (a.position - a.deltaPosition - (b.position - b.deltaPosition)).magnitude;
                float current = (a.position - b.position).magnitude;
                distance = Mathf.Clamp(distance - (current - previous) * 0.004f, 0.8f, 6f);
            }
#else
            if (Input.GetMouseButton(0) && !GUIHot()) { yaw += Input.GetAxis("Mouse X") * 3f; pitch -= Input.GetAxis("Mouse Y") * 3f; pitch = Mathf.Clamp(pitch, -60f, 80f); }
            float scroll = Input.GetAxis("Mouse ScrollWheel");
            if (Mathf.Abs(scroll) > 0.001f) distance = Mathf.Clamp(distance - scroll * 1.5f, 0.8f, 6f);
#endif
            var rot = Quaternion.Euler(pitch, yaw, 0f);
            transform.position = target - rot * Vector3.forward * distance;
            transform.rotation = rot;
        }

        static bool GUIHot() => GUIUtility.hotControl != 0;
    }
}
