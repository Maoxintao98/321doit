# 321Doit Bridge for DaVinci Resolve（中文）

面向 DaVinci Resolve Studio 的 Electron **Workflow Integration（流程整合）**，
把 321Doit 已验证的拷卡任务导入当前 Resolve 项目，并按需注入场记
（`.321log`）元数据。正式入口位于“工作区 → 流程整合”，升级时会移除旧的
Utility Script 入口。

## 运行环境

- DaVinci Resolve Studio（启用脚本）
- Python >= 3.6（python.org 或 Homebrew 均可）
- 偏好设置 → 系统 → 常规 → **外部脚本使用 = 本地**（或网络）

## 安装

双击 **`install.command`**。Resolve 只扫描系统级 Workflow Integration Plugins
目录，因此 macOS 会请求一次管理员授权。安装后重新启动 Resolve，在
**工作区 → 流程整合 → 321Doit** 打开。安装器会删除旧 Utility Script，避免
出现两个入口。卸载双击 **`uninstall.command`**，已有导入结果记录会保留。

### 手动安装

把组装完成的 `com.321doit.resolve.workflow` 文件夹复制到
`/Library/Application Support/Blackmagic Design/DaVinci Resolve/Workflow Integration Plugins/`。
文件夹必须包含本机 Resolve 21 Developer 示例附带的
`WorkflowIntegration.node` 和 `backend/bridge/`。

## 输入

1. **必选 — 拷卡任务。** 选 `<任务>/.321doit/task.json` 或任务根目录。清单必须
   声明 `schema = "com.321doit.offload-task"`、`schemaVersion = 2`，否则停止。
2. **可选 — 场记。** 选 `.321log`，或留空自动搜索任务根目录下
   `.321doit/`、`.321doit/script-log/`、`_ScriptLog/`。

## 流程

1. 选任务（可选手动选场记）。**此时不改动任何东西。**
2. 点 **仅预检**，概要显示文件/已验证/缺失/匹配/冲突/重复数量。预检不阻断
   后才启用 **执行导入**。
3. 点 **执行导入**。

任务存在 `failedResults > 0` 或 errors 时默认禁止导入；勾选
**允许导入已验证部分** 后只导入已验证文件。

## 行为说明

**会做：**
- 只导入 `copied == true && verified == true` 的素材，且只导入真正的视音频
  扩展名（mov/mp4/mxf/r3d/braw…），XML、校验、相机附属文件一律跳过。
- 建 Bin：`321Doit / <项目名或 Independent> / <日期> / <摄影机> / <卡号>`；
  多机位任务会按每条素材实际匹配的 A/B/C 机分别入箱。
- 按任务根目录 / relativePath、`MEDIA/<卡号>/`、已验证 outputPath 三级解析
  路径——硬盘挂载点变了也能找到。
- 拦截目录穿越（`..`、绝对路径注入、符号链接越界）。
- 用 **`SetMetadata`**（非 `SetClipProperty`）写 Scene/Shot/Take/Camera/
  Comments/Keywords，并逐条检测 Resolve 版本是否支持；Camera 标签按本条素材
  对应的摄影机记录选取，不会把 B 机素材写成 A 机。
- 用 `SetThirdPartyMetadata` 写身份字段
  （`321Doit Media Key = taskID + relativePath + sourceHash`、Task ID、Take ID、
  Relative Path、Source Hash、Project ID）。
- 状态映射：good=绿/OK、hold=黄/KP、ng=红/NG、优选条=绿旗标 + Circle Take。
- 幂等：扫描**整个媒体池**（不止 321Doit 箱）按 media key 与解析路径去重；
  重复运行不新增素材，只补写**空字段**（保留用户手工编辑），不清除用户手工
  颜色/旗标/关键词。
- 状态诚实：已验证但磁盘缺失的素材 → `partial`（一个都找不到 → `failed`）。

**不会做：**
- 创建/覆盖项目、时间线，或破坏性删除 Bin。
- 修改帧率、分辨率、色彩管理、起始时码。
- 复制/移动/重命名原素材。
- 修改 `task.json`、生成 `05_HANDOFF` 或任何"后期包"。
- 猜代理文件或应用 LUT（task v2 无显式代理映射，MVP 暂不启用）。
- 联网、遥测、`eval`、shell 拼接用户路径。

## 结果协议

原子写入 `<任务>/.321doit/integrations/resolve/<taskID>.json`（只读盘回退到
`~/Library/Application Support/321Doit/ResolveBridge/results/`），schema 为
`com.321doit.resolve-import-result` v1。stdout 同时输出：

```
321DOIT_RESULT_BEGIN
{...json...}
321DOIT_RESULT_END
```

## 已知限制

- 文件/文件夹选择走 macOS 原生 AppleScript `choose` 对话框（经 `osascript`，
  标准库），因 UIManager 无跨版本文件对话框；也可把路径粘贴进文本框。
- 元数据字段（Scene/Shot/Take/Camera/Comments/Keywords/Good）逐条经
  `GetMetadata()` 探测，不支持的字段记为 warning。
- 代理链接（`LinkProxyMedia`）在清单提供显式 `proxyRelativePath`/`proxyHash`
  前不启用。
- Workflow Integration 面板支持中英文；首次启动跟随系统语言，并记住面板内
  的语言切换选择。

## 测试

```
python3 -m unittest discover -s tests
```

共 47 个用例，覆盖清单校验（schema/v1/v2/版本）、5 条匹配规则（含卡号联合
消歧与冲突）、路径解析、挂载点变化、缺失素材（partial/failed 状态）、非媒体
附属文件过滤、部分导入、中文/Unicode 路径、目录穿越拦截、Resolve API 失败、
部分成功、预检、多机位 Camera 标签选取、跨箱去重、元数据补写保留用户编辑、
Take ID 写入。
