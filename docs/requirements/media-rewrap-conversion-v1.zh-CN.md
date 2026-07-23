# 321Doit「媒体封装与无损转换」V1 需求单

- 状态：待开发
- 优先级：P1
- 目标版本：主应用下一功能版本
- 面向平台：macOS
- 所属产品：321Doit 影视工具箱
- 工具标识建议：`mediaConverter`
- 中文名称：媒体封装与转换
- 英文名称：Media Rewrap & Convert

## 1. 背景

321Doit 面向所有影视工作者，而不只面向 DIT。媒体封装转换、无损音频转换和
专业格式规范化是摄影、录音、DIT、剪辑、调色、声音、视效、发行和归档部门都
会使用的基础能力。

市场上的普通“格式转换器”通常只暴露编码参数，容易把重新编码宣传成“无损”，
也经常丢失时码、音轨、色彩标签或其他影视元数据。本工具必须把“是否重编码、
可能损失什么、转换后是否一致”明确告诉用户。

## 2. 产品定位

本工具不是万能视频压缩器，V1 聚焦三个可信能力：

1. **仅更换封装（Rewrap / Stream Copy）**：不重新编码音视频码流。
2. **无损音频转换**：PCM、FLAC、ALAC 等可逆音频格式之间转换。
3. **转换验证**：转换前预检、转换后逐流复核，并生成可审计报告。

严禁将 ProRes、DNxHR、H.264、HEVC 等有损或视觉无损重新编码描述为“真正
无损”。后续加入专业中间格式时，必须单独归类为“专业转码”。

## 3. 产品架构要求

### 3.1 工具独立性

- 在 `ToolIdentifier` 中新增 `mediaConverter`。
- 在 `ToolRegistry.builtIn` 注册独立工具卡片。
- 工具必须支持：
  - 独立使用；
  - 关联现有项目；
  - 启动后补充或解除项目关联。
- 未关联项目时不得禁用任何核心转换能力。
- 关联项目只提供默认输出位置、任务归档和项目上下文，不改变转换算法。

### 3.2 模块边界

建议新增以下文件，允许开发者根据现有代码风格调整文件名，但职责不可混杂：

- `MediaConvertModels.swift`：任务、媒体流、预检、结果模型。
- `MediaProbeService.swift`：调用 ffprobe 并解析媒体信息。
- `MediaCompatibilityService.swift`：判断目标封装兼容性与风险。
- `MediaConversionEngine.swift`：执行转换、暂停/取消和进度处理。
- `MediaVerificationService.swift`：转换后逐流验证。
- `MediaConversionStore.swift`：队列、持久化和状态恢复。
- `MediaConverterView.swift`：工具主界面。
- `MediaConversionReport.swift`：JSON 和可读报告。

不得把所有逻辑写进一个 SwiftUI View，也不得复用 `ProxyTranscoder` 后通过大量
布尔参数区分行为。可以复用其进程执行、进度解析等基础能力，但要保持独立领域
模型。

## 4. 术语与强制文案规则

| 类型 | 中文显示 | 英文显示 | 是否重编码 | 是否允许称“无损” |
|---|---|---|---|---|
| Stream copy | 仅更换封装 | Rewrap / Stream Copy | 否 | 是，需注明“码流不变” |
| Lossless audio | 无损音频转换 | Lossless Audio Conversion | 是 | 是，数学无损 |
| Lossless video codec | 无损视频编码 | Lossless Video Encoding | 是 | 仅使用可证明可逆的编码时 |
| Mezzanine transcode | 专业中间格式 | Mezzanine Transcode | 是 | 否，只能称“视觉无损/剪辑友好” |
| Delivery encode | 交付压缩 | Delivery Encode | 是 | 否 |

界面必须始终显示：

- 视频是否重编码；
- 音频是否重编码；
- 字幕/数据流是否保留；
- 预计质量变化；
- 已知元数据风险。

## 5. V1 功能范围

### 5.1 输入

- 支持拖放文件和“添加文件”按钮。
- 支持一次选择多个文件。
- 支持拖放文件夹，并递归发现媒体文件。
- 默认忽略隐藏文件、`.DS_Store` 和 321Doit 自身结果目录。
- 不自动修改、移动或重命名输入文件。
- 输入格式的“可分析范围”以本机 ffprobe 实际能力为准，不写死为有限白名单。
- 常见目标包括 MOV、MP4/M4V、MKV、MTS/M2TS/TS、MXF、WAV、AIFF、FLAC、
  M4A/ALAC。

### 5.2 输出模式

#### A. 仅更换封装

- 视频、音频、字幕和数据流默认使用 stream copy。
- V1 输出容器至少提供 MOV、MP4、MKV。
- 只有源流与目标容器兼容时才允许进入执行状态。
- 不兼容时不得静默改为转码，必须阻断并解释原因。
- 用户可选择排除某条字幕、附件或数据流，但默认保留全部可兼容流。

#### B. 无损音频转换

V1 至少提供：

- WAV PCM；
- AIFF PCM；
- FLAC；
- ALAC（M4A 容器）。

要求：

- 默认保留采样率、位深、声道数和声道布局；
- 不允许默认重采样或改变位深；
- 若目标格式无法表示原始位深/布局，必须阻断或要求用户明确选择转换；
- BWF 时间参考、iXML、轨道名等专业音频元数据要进入风险检查。

### 5.3 暂不纳入 V1

- ProRes、DNxHR、H.264、HEVC 等重新编码预设；
- RAW 解码或去拜耳；
- LUT 烧录；
- 图片序列与视频互转；
- DCP、IMF 打包；
- Dolby Vision、Dolby Atmos 重新封装；
- 直接替换源文件；
- 云端转换。

以上内容可以在界面中显示为“后续版本”，但不得放置无效按钮。

## 6. 媒体分析与预检

### 6.1 ffprobe

- 复用现有 `FFmpegLocator` 的已配置路径和自动搜索策略。
- 在 ffmpeg 同目录寻找 `ffprobe`；必须验证其可执行性。
- 找不到 ffprobe 时，工具卡仍可打开，但转换按钮禁用，并给出中英文路径选择与正式离线安装包说明；正式安装包会自动使用 App 内嵌的 Universal 2 FFmpeg/FFprobe。
- 使用 `Process.executableURL` 和参数数组调用，不得拼接 shell 命令。

### 6.2 每个文件至少读取

- 容器名称；
- 文件大小和时长；
- 每一条流的 index、类型、codec、profile；
- 分辨率、像素格式、位深、帧率；
- 时基、起始时间、帧数（可用时）；
- 采样率、声道数、声道布局、音频位深；
- 字幕、附件和数据流；
- timecode、reel/tape name、creation time；
- color primaries、transfer、matrix、range；
- mastering display、content light level 等 HDR 信息（存在时）；
- display matrix/rotation、像素宽高比；
- chapters 和 format/stream tags。

解析必须使用 ffprobe JSON 输出，不得依赖面向人类的控制台文本。

### 6.3 兼容性结论

每个任务必须得到以下状态之一：

- `compatible`：可以仅换封装；
- `compatibleWithWarnings`：可以执行，但有元数据或兼容风险；
- `incompatible`：目标容器不能承载至少一条必要流；
- `probeFailed`：无法读取输入；
- `missingDependency`：缺少 ffmpeg/ffprobe。

兼容性判断必须基于实际流，不得只看扩展名。例如“`.mov` 转 `.mp4`”不是天然
兼容，仍需检查视频、音频、字幕和 timecode track。

### 6.4 预检展示

执行前以清晰摘要显示，例如：

```text
输入：H.264 / MOV / 25 fps / 4:2:2 10-bit / 4 声道 PCM
输出：H.264 / MKV / 25 fps / 4:2:2 10-bit / 4 声道 PCM

视频重编码：否
音频重编码：否
码流内容：保持不变
预计质量变化：无
元数据风险：MOV Timecode Track 将转换为容器标签
```

风险按严重度区分：信息、提醒、阻断。不得使用蓝色系统焦点边框作为风险表达。

## 7. 元数据保护策略

### 7.1 默认策略

- 使用显式 `-map 0` 思路保留所有可兼容流，不能只取第一条视频和音频。
- 保留可承载的 format tags、stream tags、chapters 和 disposition。
- 保留原始时基和起始时间，避免擅自归零时码。
- 保留音轨顺序、语言、标题和声道布局。
- 保留色彩标签、旋转和像素宽高比。
- 对目标容器无法承载的字段生成逐项风险，不得静默丢弃。

### 7.2 时码

- 单独识别 QuickTime timecode track、流标签 timecode、容器 start time。
- UI 中分别展示“素材时码”和“容器起始时间”，不得混为一项。
- 转换后重新读取时码并与源文件对比。
- 目标容器不能等价保存 timecode track 时，至少给出黄色提醒；专业用户可选择
  继续，但报告必须记录。

## 8. 执行引擎

### 8.1 文件安全

- 输出先写入同目录隐藏临时文件，例如 `.<name>.321doit-partial`。
- 转换与验证均成功后再原子重命名为最终文件。
- 失败或取消时删除临时文件；若删除失败，明确提示残留路径。
- 默认永不覆盖现有文件。
- 冲突策略：跳过、自动编号、手动选择；默认自动编号。
- 输出路径不可与源路径相同。

### 8.2 队列

- 支持批量队列。
- V1 默认串行执行，设置中可选择最多 2 个并行任务。
- 单项状态：等待、分析、可执行、转换中、验证中、完成、提醒、失败、已取消。
- 显示当前文件、总体进度、处理速度、已用时间和预计剩余时间。
- 允许取消当前任务和清空未开始任务。
- 应用重启后恢复未完成队列为“已中断”，不得自动继续写盘；用户确认后恢复。

### 8.3 FFmpeg 参数约束

- 仅换封装模式不得出现视频或音频编码器参数，必须使用 stream copy。
- 无损音频模式只允许所选无损编码器。
- 不得自动加入缩放、重采样、帧率转换、色彩转换、响度处理或滤镜。
- 所有路径通过 `Process.arguments` 传递，禁止 `sh -c`、字符串拼接和未转义参数。
- 保存实际执行参数到诊断日志和结果记录，但界面默认不展示冗长命令。

## 9. 转换后验证

### 9.1 结构验证（强制）

重新运行 ffprobe，至少比较：

- 流数量与流类型；
- codec/profile；
- 分辨率、像素格式和位深；
- 帧率、时基、时长和起始时间；
- 采样率、位深、声道数和布局；
- 字幕、附件和章节数量；
- timecode 与色彩标签。

### 9.2 码流验证（仅换封装强制）

- 对每条音视频流计算有序 packet payload 摘要。
- 推荐通过 ffprobe 的 packet data hash 能力读取 payload hash，并按流 index、DTS/PTS、
  packet size 建立稳定聚合摘要。
- 源和目标每条必要流的 packet 数量、总 payload 大小和聚合摘要必须一致。
- 若容器导致合法的 packet 边界变化，不能简单宣告失败：应降级为“需要深度验证”，
  使用解码帧/采样摘要比较；无法证明一致时不得显示“码流验证通过”。
- 哈希算法使用 SHA-256。

### 9.3 无损音频验证

- 解码源和目标为标准 PCM 数据后计算 SHA-256。
- 同时比较采样数、采样率、位深、声道数和布局。
- 只有解码 PCM 摘要和结构全部一致时，才显示“数学无损验证通过”。

### 9.4 结果等级

- `verifiedLossless`：满足对应模式的完整验证；
- `verifiedWithMetadataWarnings`：码流一致，但存在已知元数据差异；
- `structureOnly`：只完成结构验证，不得标为无损验证通过；
- `verificationFailed`：内容或必要结构不一致；
- `conversionFailed`：转换失败。

## 10. 报告与审计

每个批次生成一个 JSON 结果文件，至少包含：

- schema：`com.321doit.media-conversion-result`；
- schemaVersion：`1`；
- taskID、projectAssociationMode、linkedProjectID；
- startedAt、endedAt、appVersion、ffmpegVersion；
- 源/目标绝对路径和文件大小；
- 用户选择的模式；
- 源/目标完整流摘要；
- 兼容性警告；
- 是否发生视频/音频重编码；
- 验证方法、逐流摘要和最终结果等级；
- 实际执行参数数组；
- warnings、errors。

默认报告位置：

- 独立使用：用户选择的输出目录下 `.321doit/conversion/`；
- 关联项目：项目数据目录中的转换任务目录，同时在输出目录写一份可携带副本。

报告失败不得把已验证的输出文件判为转换失败，但必须显示“报告写入失败”。

## 11. 界面要求

### 11.1 页面结构

单窗口工具页，建议四段：

1. 输入队列；
2. 输出模式与目标目录；
3. 转换前预检；
4. 任务进度与验证结果。

默认界面只展示专业用户作决定所需的信息；完整 stream/tag 数据放入可展开的
“技术详情”。

### 11.2 视觉

- 沿用主应用现有主题和 `LiquidGlassStyle`，不另造一套 UI。
- 不使用蓝色焦点外框；保留键盘可访问性时，使用应用主题定义的低干扰焦点样式。
- 状态颜色：成功为绿、提醒为黄/橙、失败为红；颜色必须同时配文字或图标。
- 不使用 Lite、FFmpeg 或第三方产品 Logo 作为模块 Logo。

### 11.3 中英文

- 所有新增用户可见文案必须通过 `L10n.t(zh, en, language:)`。
- 跟随 `settings.settings.general.language`，不得建立第二套语言设置。
- 中文和英文下都要检查截断、按钮宽度、表格列宽和 VoiceOver 标签。
- JSON schema 字段保持稳定英文，不随界面语言变化。

## 12. 与其他工具的衔接

V1 必须保持接口能力，但不要求全部自动化：

- 拷卡完成后可把已验证素材发送到本工具队列；
- 后期交接可以引用转换任务结果，而不是重新猜测文件；
- 项目管理可以展示关联的转换任务数量和最近状态；
- Resolve Workflow Integration 后续可读取转换结果与输出路径；
- 不得让本工具反向依赖拷卡模块才能运行。

建议为内部调用暴露类似接口：

```swift
struct MediaConversionRequest {
    var sourceURLs: [URL]
    var mode: MediaConversionMode
    var targetContainer: MediaContainer
    var destinationURL: URL
    var projectContext: ToolProjectContext?
}
```

## 13. 权限、隐私与稳定性

- 本地处理，不上传素材、文件名、元数据或报告。
- 使用现有 Security-Scoped Bookmark 机制保存用户授权目录。
- 不把绝对路径写入普通分析日志；诊断包可以包含，但必须由用户主动导出。
- 进程崩溃不能损坏源文件。
- 退出应用时若有任务运行，必须提供“继续等待、取消任务、返回应用”，不得直接退出。
- 8 位、10 位、12 位、Alpha、HDR、多音轨、无音频、纯音频和损坏文件均要有测试覆盖。

## 14. 性能目标

- 仅换封装速度主要受磁盘吞吐限制，不得无故解码视频。
- 1 GB 单文件在本地 SSD 上开始处理前的分析目标小于 3 秒；大型长片文件允许按
  流信息先给初步结论，完整 packet hash 在验证阶段执行。
- UI 线程不得调用 `waitUntilExit()` 或同步读取大管道。
- stdout/stderr 必须持续消费，避免 FFmpeg 管道阻塞。
- 进度更新节流到合适频率，避免每帧刷新 SwiftUI。

## 15. 错误处理

至少覆盖以下错误并提供中英文可行动说明：

- FFmpeg 或 ffprobe 不存在；
- 文件不可读或权限过期；
- 容器/codec 不兼容；
- 输出空间不足；
- 输出文件已存在；
- 目标目录不可写；
- FFmpeg 非零退出；
- 用户取消；
- 验证不一致；
- 元数据无法等价保存；
- 报告写入失败。

错误日志要包含稳定错误码，例如：

- `MC_DEPENDENCY_MISSING`
- `MC_PROBE_FAILED`
- `MC_INCOMPATIBLE_CONTAINER`
- `MC_INSUFFICIENT_SPACE`
- `MC_CONVERSION_FAILED`
- `MC_VERIFICATION_FAILED`
- `MC_REPORT_FAILED`

## 16. 测试要求

### 16.1 单元测试

- ffprobe JSON 解析；
- 容器兼容性矩阵；
- 重编码判定；
- 输出命名与冲突策略；
- 任务状态迁移；
- 进度解析；
- metadata diff；
- packet/PCM 摘要聚合；
- 中英文关键文案存在性。

### 16.2 集成测试

使用测试生成的小体积素材覆盖：

- MOV → MKV stream copy；
- MKV → MOV 兼容流；
- MOV → MP4 不兼容音频时阻断；
- 多音轨与不同声道布局；
- timecode track；
- 字幕和章节；
- 旋转手机素材；
- VFR 素材；
- WAV ↔ FLAC ↔ WAV PCM 摘要一致；
- 用户取消、磁盘空间不足、输出冲突；
- 转换后人为篡改文件，验证必须失败。

测试素材必须由测试代码生成或明确可再分发，不提交受版权保护的影视素材。

## 17. V1 验收标准

以下全部满足才算完成：

1. 工具箱首页出现“媒体封装与转换 / Media Rewrap & Convert”。
2. 可独立或关联项目启动。
3. 支持多文件/文件夹拖放和队列。
4. MOV、MP4、MKV 目标封装根据实际流做兼容性预检。
5. 仅换封装任务确认没有任何视频/音频重编码参数。
6. 支持 WAV、AIFF、FLAC、ALAC 无损音频输出。
7. 不兼容流不会被静默删除或自动转码。
8. 转换后完成结构验证和对应模式的内容摘要验证。
9. 源文件在成功、失败、取消情况下均保持不变。
10. 输出通过临时文件原子落盘，失败不留下伪装成完成品的文件。
11. 生成 schemaVersion 1 的 JSON 结果。
12. 所有界面、错误和状态支持中英文并跟随主应用语言。
13. 无蓝色系统焦点框回归。
14. 新增单元测试和集成测试全部通过，原有测试不得减少或跳过。
15. 未修改与本工具无关的用户文档、DMG、发布说明或署名信息。

## 18. 开发交付清单

开发者交付时必须提供：

- 修改文件列表；
- 架构说明；
- 支持与不支持的格式/流说明；
- FFmpeg/ffprobe 参数示例；
- 测试命令与完整测试结果；
- 至少一份成功报告和一份验证失败报告示例；
- 中文、英文界面截图；
- 已知限制；
- 未提交 DMG、构建缓存、临时素材、个人路径、AI 修改意见或无关文档的确认。

不要自行提交、推送、发布或生成 DMG，除非项目负责人另行明确要求。
