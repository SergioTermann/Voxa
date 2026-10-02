# Voxa for Windows

[中文](README.md) | [English](README.en.md) · [返回项目首页](../README.md)

Windows 原生语音输入工具。使用 C#、.NET 8、WPF、Windows `System.Speech` / SAPI 本机听写；不需要 API Key。macOS 版本仍位于仓库根目录的 `Sources/`。

这是 Windows 首版实现，目前已在 macOS 上交叉编译并通过核心逻辑测试，**尚未完成 Windows 真机麦克风与跨应用输入验收**。仓库包含 Windows CI 构建、启动与静默安装 / 卸载检查；真实语音和跨应用输入仍需在目标设备验证。

## 系统要求

- Windows 10 / 11，x64。建议使用仍受支持的 Windows 11。当前打包不声明原生 ARM64 支持。
- 默认录音设备可用，并在“设置 → 隐私和安全性 → 麦克风”允许桌面应用使用麦克风。
- 已安装支持听写的 **桌面 SAPI 语音识别引擎**。程序仅列出 `SpeechRecognitionEngine.InstalledRecognizers()` 实际返回的引擎，不假定中文或任何语言必然可用。
- 可从 Windows 语言选项安装所需语言的“语音”组件，安装后重启 Voxa。具体能否提供兼容引擎取决于 Windows 版本和语言包；若下拉框为空，则本版无法启动识别。
- Windows 11 新版“语音访问”、Win + H、在线听写或文本转语音语言包可用，**不等于**安装了兼容 SAPI 听写引擎。Windows 11 24H2 已移除旧版 Windows Speech Recognition 界面，也不能据此保证机器具有旧版识别组件。没有兼容引擎时需要另行适配识别后端，本版不会静默切换到云服务。

## 安装与卸载

从 [v1.3.0 Release](https://github.com/SergioTermann/Voxa/releases/tag/v1.3.0) 下载 `Voxa-v1.3.0-Windows-Setup-x64.exe`，双击运行，选择中文或英文向导即可安装。

- 安装包包含 .NET 运行时，使用者无需另装 .NET，也无需管理员权限。
- 安装目录为 `%LOCALAPPDATA%\Programs\Voxa`，创建开始菜单和桌面快捷方式。
- 更新或卸载前通过系统托盘退出 Voxa；可从 Windows“已安装的应用”卸载。
- 卸载保留 `%LOCALAPPDATA%\Voxa\settings.json` 偏好设置；它不包含录音或转写文字。
- 安装包目前未签名，Windows 可能显示未知发布者提示。
- 便携版 ZIP 需完整解压后运行 `Voxa.exe`，保留同目录的全部运行时文件。

## 构建

开发机器安装 [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)，安装包编译还需 [NSIS 3](https://nsis.sourceforge.io/Download)，将 `makensis` 加入 PATH。

在仓库目录使用 PowerShell：

```powershell
./windows/build-installer.ps1
```

脚本执行核心测试、发布包含运行时的应用，再编译安装包。只要便携版可运行 `./windows/build.ps1`。

```text
build/windows/Voxa-v1.3.0-Windows-Setup-x64.exe
build/windows/Voxa-v1.3.0-Windows-x64.zip
build/windows/win-x64/Voxa.exe
```

macOS / Linux 可交叉编译并使用 NSIS 打包，但不能直接运行 Windows 应用：

```sh
dotnet run --project windows/Voxa.Core.Tests -c Release
dotnet publish windows/Voxa.Windows/Voxa.Windows.csproj -c Release -r win-x64 --self-contained true -o build/windows/win-x64
mkdir -p build/windows/win-x64/windows build/windows/win-x64/Assets
cp README.md build/windows/win-x64/README.md
cp README.en.md build/windows/win-x64/README.en.md
cp windows/README.md build/windows/win-x64/windows/README.md
cp windows/README.en.md build/windows/win-x64/windows/README.en.md
cp Assets/Voxa-icon.png build/windows/win-x64/Assets/Voxa-icon.png
makensis windows/Voxa-Setup.nsi
```

GitHub Actions **Windows build and installer** 工作流会产出安装器和 ZIP。发布 `v*` 标签时，**Release installers** 工作流上传两个平台的安装包到对应 GitHub Release。

## 使用

1. 启动 Voxa，在设置窗口选择本机识别语言。可选择停顿后自动完成。
2. 点击记事本等普通应用的可编辑文本框。
3. **快速按下并松开右 Ctrl 两次**开始；不抢焦点的浮窗显示实时识别结果。
4. 停顿后自动完成，或再次**双击右 Ctrl**完成并输入。自动结束需要已经确认的识别文字、文字稳定且没有语音活动约 1.6 秒；引擎自身的断句还会增加延迟。
5. 按 **Ctrl + Alt + Esc** 取消。每次会话最长约 55 秒，完成阶段另有最多 5 秒超时保护。
6. 关闭设置窗口会隐藏到托盘；从托盘重新打开、复制上次文字或退出。

默认使用右 Ctrl 双击开始 / 完成：每次轻按不超过 0.5 秒，两次间隔不超过 0.65 秒。左 Ctrl 不触发，Ctrl+C 等组合键、长按、鼠标操作和切换窗口会中断序列。**Ctrl + Alt + Space** 保留为备用，普通输入不会被拦截。如果备用快捷键被占用，设置窗口会显示提示。

新界面采用深色卡片、圆角开关与独立转写区域，听写浮窗显示实际麦克风音量。

## 输入行为

- 开始识别时必须处于外部可编辑输入框。Windows UI Automation 用于确认控件可编辑、处于焦点且不是密码框；不能确认的控件不自动输入。
- 听写过程中可以切换输入框，**结束听写时**锁定当前目标，发送前再次核对窗口及控件焦点。
- 使用 `SendInput` 发送 Unicode 按键。保持目标应用的原生选区替换行为，不修改剪贴板、不发送 Enter 或 Tab。快捷键修饰键尚未松开时会短暂等待并再次检查焦点。
- 对于其他应用以管理员身份运行、远程桌面、游戏、自定义编辑器或 UI Automation 支持不足的网页控件，不保证自动输入；Windows 也可能阻止向更高权限窗口注入按键。
- 完成时焦点变化、控件失效、输入失败或识别异常时，已确认的文字保留在设置窗口，可手动复制。输入中途失败时可能已写入部分文字，请检查后再复制，以免重复。
- Windows 接受按键并不等于目标应用一定接收文字；请以输入框实际内容为准。没有剪贴板粘贴回退。
- 未确认的实时识别片段只用于预览，不作为最终结果插入。取消会丢弃当前未完成会话；上次完成的结果仍保留。

## 隐私与配置

本版使用所选本机 SAPI 引擎，没有实现云端 API 调用。Voxa 不保存录音或转写日志，识别文字只存在于内存，退出即清除。点击“复制文字”会把文字写入 Windows 剪贴板，其后由系统剪贴板历史及同步设置管理。

仅语言引擎 ID 和自动结束设置写入：

```text
%LOCALAPPDATA%\Voxa\settings.json
```

右 Ctrl 双击通过不拦截事件的全局键盘 / 鼠标监听检测；备用快捷键通过 `RegisterHotKey` 注册。其他键盘输入不保存。程序以普通用户权限运行，不申请提权。

## 验证

跨平台核心测试覆盖：部分识别与最终结果的替换、多句合并、重复语句保留、中文间距、静音与语音活动对自动结束的影响、换行和 Tab 清理，以及 `SendInput` 原生结构大小。Windows CI 还会构建安装器、检查进程启动，并进行静默安装 / 卸载检查。

发布前请在目标 Windows 设备验证以下项目；编译及 CI 启动检查不能替代这些测试：

- 麦克风已授权 / 未授权 / 没有默认设备，以及中文和英文引擎实际识别。
- 记事本、浏览器输入框中的插入、选区替换，以及不支持控件的拒绝行为。
- 自动结束、手动结束、取消、快捷键仍按住、55 秒时限和连续多次会话。
- 结束过程中切换窗口或输入框时不误输入；密码框不能启动听写。
- 管理员窗口输入失败时保留文字；原剪贴板不因自动输入改变。
- 关闭窗口后托盘继续工作；退出后麦克风和快捷键释放；第二次启动不产生重复实例。
- 无兼容语音引擎、快捷键冲突、多屏幕与高 DPI。
