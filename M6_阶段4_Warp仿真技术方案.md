# M6 阶段 4：服务器端 Warp 布料仿真技术方案

> **目标**：在 Windows 服务器（RTX 3070Ti）上运行 NVIDIA Warp 布料仿真，iOS 端通过局域网 HTTP 通信获取 3D 成衣结果。

---

## 目录

1. [整体架构](#整体架构)
2. [技术选型](#技术选型)
3. [服务器端实现](#服务器端实现)
4. [iOS 端实现](#ios-端实现)
5. [数据流与 API 设计](#数据流与-api-设计)
6. [本地 POC 步骤](#本地-poc-步骤)
7. [风险与应对](#风险与应对)
8. [时间估算](#时间估算)

---

## 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                         iOS App                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  纸样设计界面（PatternDesignView）                     │  │
│  │  - 用户输入设计参数（38 个参数）                       │  │
│  │  - 生成 GarmentDesignSpec JSON                        │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ↓ HTTP POST                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  网络层（GarmentSimulationService）                    │  │
│  │  - 上传设计参数                                       │  │
│  │  - 轮询/WebSocket 获取结果                            │  │
│  │  - 下载 glTF 文件                                     │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ↓                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Unity 预览（GarmentPreviewLauncherView）              │  │
│  │  - 加载 glTF 模型                                     │  │
│  │  - 展示 3D 成衣                                       │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↕ HTTP (局域网)
┌─────────────────────────────────────────────────────────────┐
│              Windows 服务器（RTX 3070Ti）                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  FastAPI 服务器（Python）                             │  │
│  │  - 接收设计参数                                       │  │
│  │  - 调用 GarmentCode 生成纸样                          │  │
│  │  - 调用 Warp 仿真                                     │  │
│  │  - 导出 glTF                                          │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ↓                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  GarmentCode（Python）                                │  │
│  │  - pattern_sampler.py：生成 2D 纸样                   │  │
│  │  - 输出：panels.json + stitches.json                  │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ↓                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  NVIDIA Warp（Python + CUDA）                         │  │
│  │  - XPBD 布料仿真                                      │  │
│  │  - 缝合约束                                           │  │
│  │  - 碰撞检测                                           │  │
│  │  - 输出：3D 网格（glTF）                              │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 技术选型

### 服务器端

| 组件 | 技术 | 版本 | 说明 |
|------|------|------|------|
| 操作系统 | Windows 11 | - | RTX 3070Ti 驱动支持 |
| GPU 驱动 | NVIDIA Driver | 最新 | 支持 CUDA 11.8+ |
| CUDA | CUDA Toolkit | 11.8+ | Warp 依赖 |
| Python | Python | 3.10+ | Warp 要求 |
| Web 框架 | FastAPI | 0.100+ | 异步 HTTP 服务器 |
| 仿真引擎 | NVIDIA Warp | 1.0.0-beta.6+ | GarmentCode fork |
| 纸样生成 | GarmentCode | 2.0.0+ | PyGarment 库 |
| 任务队列 | Celery + Redis | 最新 | 异步任务处理 |
| 文件存储 | 本地文件系统 | - | 存储 glTF 结果 |

### iOS 端

| 组件 | 技术 | 说明 |
|------|------|------|
| 网络层 | URLSession | HTTP 请求 |
| JSON 解析 | Codable | 序列化/反序列化 |
| 3D 渲染 | Unity (UaaL) | 加载 glTF |
| glTF 加载 | UnityGLTF | Unity 插件 |
| 进度展示 | SwiftUI ProgressView | 仿真进度条 |

---

## 服务器端实现

### 1. 环境搭建

#### 1.1 安装 CUDA

```powershell
# 下载 CUDA Toolkit 11.8
# https://developer.nvidia.com/cuda-11-8-0-download-archive

# 验证安装
nvcc --version
```

#### 1.2 安装 NVIDIA Warp（GarmentCode fork）

```powershell
# 克隆 GarmentCode 的 Warp fork
git clone https://github.com/maria-korosteleva/NvidiaWarp-GarmentCode
cd NvidiaWarp-GarmentCode

# 安装 Git LFS
git lfs install
git lfs pull

# 编译 Warp 核心库
python build_lib.py

# 安装 Warp Python 包
pip install -e .

# 验证安装
python -c "import warp; print(warp.__version__)"
```

#### 1.3 安装 GarmentCode

```powershell
# 克隆 GarmentCode
git clone https://github.com/maria-korosteleva/GarmentCode
cd GarmentCode

# 安装依赖
pip install -r requirements.txt

# 配置 system.json
# 编辑 system.json，设置路径：
# {
#   "bodies_default_path": "path/to/body/meshes",
#   "datasets_path": "path/to/output",
#   "simulation_config_path": "path/to/configs"
# }
```

#### 1.4 安装 FastAPI

```powershell
pip install fastapi uvicorn[standard] celery redis
```

### 2. FastAPI 服务器

**文件：`server.py`**

```python
from fastapi import FastAPI, BackgroundTasks, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel
import uuid
import os
from typing import Optional
import subprocess
import json

app = FastAPI()

# 任务状态存储（生产环境用 Redis）
tasks = {}

class GarmentDesignRequest(BaseModel):
    """iOS 端上传的设计参数"""
    upper: Optional[str] = None
    waistband: Optional[str] = None
    bottom: Optional[str] = None
    measurements: dict
    parameters: dict

class SimulationResponse(BaseModel):
    """返回给 iOS 的响应"""
    task_id: str
    status: str  # pending / processing / completed / failed
    result_url: Optional[str] = None
    error: Optional[str] = None

@app.post("/api/simulate", response_model=SimulationResponse)
async def create_simulation(design: GarmentDesignRequest, background_tasks: BackgroundTasks):
    """
    创建仿真任务
    
    1. 生成 task_id
    2. 保存设计参数到临时文件
    3. 后台异步执行仿真
    4. 立即返回 task_id
    """
    task_id = str(uuid.uuid4())
    
    # 保存设计参数
    design_file = f"temp/{task_id}_design.json"
    os.makedirs("temp", exist_ok=True)
    with open(design_file, "w") as f:
        json.dump(design.dict(), f)
    
    # 初始化任务状态
    tasks[task_id] = {
        "status": "pending",
        "result_url": None,
        "error": None
    }
    
    # 后台执行仿真
    background_tasks.add_task(run_simulation, task_id, design_file)
    
    return SimulationResponse(
        task_id=task_id,
        status="pending"
    )

@app.get("/api/status/{task_id}", response_model=SimulationResponse)
async def get_status(task_id: str):
    """查询仿真状态"""
    if task_id not in tasks:
        raise HTTPException(status_code=404, detail="Task not found")
    
    task = tasks[task_id]
    return SimulationResponse(
        task_id=task_id,
        status=task["status"],
        result_url=task["result_url"],
        error=task["error"]
    )

@app.get("/api/result/{task_id}")
async def get_result(task_id: str):
    """下载仿真结果（glTF 文件）"""
    result_file = f"output/{task_id}/result.gltf"
    
    if not os.path.exists(result_file):
        raise HTTPException(status_code=404, detail="Result not found")
    
    return FileResponse(
        result_file,
        media_type="model/gltf+json",
        filename=f"garment_{task_id}.gltf"
    )

def run_simulation(task_id: str, design_file: str):
    """
    执行仿真（后台任务）
    
    1. 调用 GarmentCode 生成 2D 纸样
    2. 调用 Warp 仿真
    3. 导出 glTF
    4. 更新任务状态
    """
    try:
        tasks[task_id]["status"] = "processing"
        
        # 1. 生成纸样
        print(f"[{task_id}] Generating pattern...")
        pattern_file = f"temp/{task_id}_pattern.json"
        subprocess.run([
            "python", "GarmentCode/pattern_sampler.py",
            "--design", design_file,
            "--output", pattern_file
        ], check=True)
        
        # 2. 运行 Warp 仿真
        print(f"[{task_id}] Running Warp simulation...")
        output_dir = f"output/{task_id}"
        os.makedirs(output_dir, exist_ok=True)
        subprocess.run([
            "python", "GarmentCode/pattern_data_sim.py",
            "--pattern", pattern_file,
            "--output", output_dir,
            "--config", "GarmentCode/data_generation/Sim_props/sim_config.yaml"
        ], check=True)
        
        # 3. 导出 glTF（假设 GarmentCode 已经生成）
        # 如果没有，需要额外转换
        
        # 4. 更新状态
        tasks[task_id]["status"] = "completed"
        tasks[task_id]["result_url"] = f"/api/result/{task_id}"
        
        print(f"[{task_id}] Simulation completed!")
        
    except subprocess.CalledProcessError as e:
        tasks[task_id]["status"] = "failed"
        tasks[task_id]["error"] = str(e)
        print(f"[{task_id}] Simulation failed: {e}")
    except Exception as e:
        tasks[task_id]["status"] = "failed"
        tasks[task_id]["error"] = str(e)
        print(f"[{task_id}] Unexpected error: {e}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

### 3. 启动脚本

**文件：`start_server.bat`**

```batch
@echo off
echo Starting GarmentCode Warp Server...

REM 激活 Python 虚拟环境（如果有）
REM call venv\Scripts\activate

REM 启动 Redis（用于任务队列）
start redis-server

REM 启动 FastAPI 服务器
python server.py

pause
```

---

## iOS 端实现

### 1. 网络层

**文件：`TrailorAss/Services/GarmentSimulationService.swift`**

```swift
import Foundation

/// 服务器端仿真服务
class GarmentSimulationService {
    /// 服务器地址（局域网 IP）
    static let baseURL = "http://192.168.1.100:8000"  // 替换为实际服务器 IP
    
    /// 提交仿真任务
    static func submitSimulation(design: GarmentDesignSpec) async throws -> String {
        let url = URL(string: "\(baseURL)/api/simulate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 转换设计参数为服务器格式
        let requestBody = design.toServerFormat()
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SimulationResponse.self, from: data)
        
        return response.taskId
    }
    
    /// 查询仿真状态
    static func checkStatus(taskId: String) async throws -> SimulationStatus {
        let url = URL(string: "\(baseURL)/api/status/\(taskId)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SimulationResponse.self, from: data)
        
        return SimulationStatus(
            status: response.status,
            resultURL: response.resultUrl,
            error: response.error
        )
    }
    
    /// 下载仿真结果
    static func downloadResult(taskId: String) async throws -> Data {
        let url = URL(string: "\(baseURL)/api/result/\(taskId)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
    
    /// 轮询等待仿真完成
    static func waitForCompletion(taskId: String, progressHandler: @escaping (Double) -> Void) async throws -> Data {
        var attempts = 0
        let maxAttempts = 120  // 最多等待 2 分钟
        
        while attempts < maxAttempts {
            let status = try await checkStatus(taskId: taskId)
            
            switch status.status {
            case "completed":
                return try await downloadResult(taskId: taskId)
            case "failed":
                throw SimulationError.failed(status.error ?? "Unknown error")
            case "processing":
                progressHandler(0.5)  // 简化进度
            default:
                progressHandler(0.1)
            }
            
            try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 秒
            attempts += 1
        }
        
        throw SimulationError.timeout
    }
}

// MARK: - 数据模型

struct SimulationResponse: Codable {
    let taskId: String
    let status: String
    let resultUrl: String?
    let error: String?
    
    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case status
        case resultUrl = "result_url"
        case error
    }
}

struct SimulationStatus {
    let status: String
    let resultURL: String?
    let error: String?
}

enum SimulationError: Error {
    case failed(String)
    case timeout
}

// MARK: - GarmentDesignSpec 扩展

extension GarmentDesignSpec {
    /// 转换为服务器格式
    func toServerFormat() -> [String: Any] {
        return [
            "upper": upper?.rawValue as Any,
            "waistband": waistband?.rawValue as Any,
            "bottom": bottom?.rawValue as Any,
            "measurements": [
                "height": heightCm,
                "bust": bustCm,
                "waist": waistCm,
                "hip": hipCm,
                "shoulder_width": shoulderWidthCm,
                // ... 其他测量参数
            ],
            "parameters": [
                "ease": easeCm,
                "upper_length": upperLengthCm,
                // ... 其他设计参数
            ]
        ]
    }
}
```

### 2. UI 集成

**修改 `TrailorAss/Views/Garment/PatternDesignView.swift`**

在"生成 2D 纸样"按钮下方添加"生成 3D 成衣（服务器仿真）"按钮：

```swift
Section {
    Button {
        Task {
            await simulateOnServer()
        }
    } label: {
        Label("生成 3D 成衣（服务器仿真）", systemImage: "cloud")
            .frame(maxWidth: .infinity)
    }
    .listRowBackground(Color.appAccent)
    .foregroundStyle(.white)
    .disabled(isSimulating)
    
    if isSimulating {
        ProgressView(value: simulationProgress) {
            Text("仿真中... \(Int(simulationProgress * 100))%")
        }
    }
}

// MARK: - 服务器仿真

@State private var isSimulating = false
@State private var simulationProgress: Double = 0

private func simulateOnServer() async {
    isSimulating = true
    simulationProgress = 0
    
    do {
        // 1. 提交仿真任务
        let taskId = try await GarmentSimulationService.submitSimulation(design: design)
        
        // 2. 等待完成
        let gltfData = try await GarmentSimulationService.waitForCompletion(taskId: taskId) { progress in
            await MainActor.run {
                simulationProgress = progress
            }
        }
        
        // 3. 保存 glTF 到临时文件
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("garment_\(taskId).gltf")
        try gltfData.write(to: tempURL)
        
        // 4. 在 Unity 中加载
        await MainActor.run {
            // 传递 glTF 路径给 Unity
            UnityGarmentPreview.loadGLTF(at: tempURL.path)
            isSimulating = false
        }
        
    } catch {
        await MainActor.run {
            validationMessages = ["仿真失败：\(error.localizedDescription)"]
            isSimulating = false
        }
    }
}
```

---

## 数据流与 API 设计

### API 端点

| 端点 | 方法 | 说明 | 请求体 | 响应 |
|------|------|------|--------|------|
| `/api/simulate` | POST | 创建仿真任务 | GarmentDesignRequest | SimulationResponse |
| `/api/status/{task_id}` | GET | 查询任务状态 | - | SimulationResponse |
| `/api/result/{task_id}` | GET | 下载结果文件 | - | glTF 文件 |

### 数据格式

#### GarmentDesignRequest（iOS → 服务器）

```json
{
  "upper": "Shirt",
  "waistband": "StraightWB",
  "bottom": "SkirtCircle",
  "measurements": {
    "height": 168.0,
    "bust": 92.0,
    "waist": 76.0,
    "hip": 98.0,
    "shoulder_width": 39.0,
    "neck_circ": 36.0,
    "arm_length": 58.0,
    "bicep_circ": 28.0,
    "wrist_circ": 16.0
  },
  "parameters": {
    "ease": 8.0,
    "upper_length": 58.0,
    "sleeve_length": 58.0,
    "sleeve_opening": 26.0,
    "waistband_width": 5.0,
    "skirt_length": 70.0
  }
}
```

#### SimulationResponse（服务器 → iOS）

```json
{
  "task_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "processing",
  "result_url": null,
  "error": null
}
```

状态说明：
- `pending`：任务已创建，等待执行
- `processing`：仿真进行中
- `completed`：仿真完成，可下载结果
- `failed`：仿真失败，error 字段包含错误信息

---

## 本地 POC 步骤

### 准备工作（1 天）

1. **Windows 电脑准备**
   - 确认 RTX 3070Ti 驱动已安装
   - 安装 CUDA Toolkit 11.8
   - 安装 Python 3.10+
   - 安装 Git + Git LFS

2. **网络配置**
   - 确认 Windows 电脑和 iPhone 在同一局域网
   - 记录 Windows 电脑的局域网 IP（如 `192.168.1.100`）
   - 关闭 Windows 防火墙（或开放 8000 端口）

### 环境搭建（1 天）

3. **安装 NVIDIA Warp**
   ```powershell
   git clone https://github.com/maria-korosteleva/NvidiaWarp-GarmentCode
   cd NvidiaWarp-GarmentCode
   git lfs install
   git lfs pull
   python build_lib.py
   pip install -e .
   ```

4. **安装 GarmentCode**
   ```powershell
   git clone https://github.com/maria-korosteleva/GarmentCode
   cd GarmentCode
   pip install -r requirements.txt
   # 配置 system.json
   ```

5. **测试 Warp 仿真**
   ```powershell
   # 运行 GarmentCode 示例
   python GarmentCode/pattern_data_sim.py --data example --config sim_config.yaml
   ```

### 服务器开发（2 天）

6. **实现 FastAPI 服务器**
   - 创建 `server.py`
   - 实现 `/api/simulate`、`/api/status`、`/api/result` 端点
   - 测试 API

7. **集成 GarmentCode**
   - 调用 `pattern_sampler.py` 生成纸样
   - 调用 `pattern_data_sim.py` 运行仿真
   - 导出 glTF

### iOS 端开发（2 天）

8. **实现网络层**
   - 创建 `GarmentSimulationService.swift`
   - 实现提交、查询、下载功能

9. **UI 集成**
   - 添加"生成 3D 成衣"按钮
   - 显示仿真进度
   - 加载 glTF 到 Unity

### 测试（1 天）

10. **端到端测试**
    - iOS 提交设计参数
    - Windows 服务器运行仿真
    - iOS 下载并展示结果

---

## 风险与应对

| 风险 | 概率 | 影响 | 应对方案 |
|------|------|------|----------|
| Warp 许可证不允许商业用途 | 中 | 高 | 使用最新版 Warp（Apache 2.0）或联系 NVIDIA |
| Windows 环境搭建失败 | 中 | 高 | 提供详细的安装文档，或改用 Linux 虚拟机 |
| 仿真时间过长（>2 分钟） | 中 | 中 | 降低仿真精度，或使用更小的网格 |
| 局域网通信不稳定 | 低 | 中 | 添加重试机制，显示详细错误信息 |
| glTF 加载失败 | 低 | 中 | 使用 UnityGLTF 插件，或转换为 OBJ |

---

## 时间估算

| 阶段 | 任务 | 时间 |
|------|------|------|
| 准备工作 | Windows 环境准备、网络配置 | 1 天 |
| 环境搭建 | 安装 Warp、GarmentCode、测试仿真 | 1 天 |
| 服务器开发 | FastAPI 服务器、GarmentCode 集成 | 2 天 |
| iOS 开发 | 网络层、UI 集成 | 2 天 |
| 测试 | 端到端测试、bug 修复 | 1 天 |
| **总计** | | **7 天** |

---

## 后续优化方向

### 短期（1-2 周）

1. **性能优化**
   - 降低仿真精度（快速预览模式）
   - 预生成常见款式
   - 结果缓存

2. **用户体验**
   - WebSocket 实时进度推送
   - 预览图生成
   - 取消功能

### 中期（1-2 个月）

3. **部署到云服务器**
   - AWS g4dn.xlarge
   - 负载均衡
   - CDN 加速

4. **功能扩展**
   - 支持更多组件（裤子、连衣裙）
   - 支持动画导出
   - 支持材质编辑

### 长期（3-6 个月）

5. **自建服务器**
   - 购买 GPU 服务器
   - 迁移服务
   - 监控系统

6. **算法优化**
   - 移植 Warp 到 Swift/Metal
   - 本地仿真（iPhone GPU）
   - 实时预览

---

## 参考资料

- [GarmentCode 论文](https://igl.ethz.ch/projects/garmentcode/)
- [GarmentCodeData 论文](https://igl.ethz.ch/projects/GarmentCodeData/)
- [NVIDIA Warp 官方文档](https://nvidia.github.io/warp/)
- [GarmentCode GitHub](https://github.com/maria-korosteleva/GarmentCode)
- [NvidiaWarp-GarmentCode GitHub](https://github.com/maria-korosteleva/NvidiaWarp-GarmentCode)

---

**文档版本**：v1.0  
**创建日期**：2026-10-19  
**作者**：TailorAss 团队
