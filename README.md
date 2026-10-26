# ABB RobotStudio MCP Server — LiskinLabs Edition

> **v3.1.0 (Safety-First & Hardened Edition)** — Advanced MCP server for ABB RobotStudio and ABB robot controllers with TcpListener transport, 63 MCP tools, AutoLoad, RAPID syntax validator, pre-simulation safety guards, and path-traversal protection.

Model Context Protocol (MCP) server for ABB RobotStudio (desktop application) and ABB robot controllers (OmniCore / IRC5 / Virtual Controllers).

Exposes **63 tools** across two transports:

- **`rs_*`** (33 tools) — RobotStudio SDK via TcpListener in-process Add-In. Inspect/edit stations, targets, paths, modules, variables, I/O signals, configs. Drive simulation with safety guards. Capture screenshots.
- **`rws_*`** (30 tools) — Robot Web Services REST API direct to controller. Motors, program execution, I/O signals, filesystem, mastership, event log, runtime target controller switching.

Mục tiêu hiện tại: **ABB RobotStudio 6.08 trên Windows**. Đã nạp Add-In và đọc module qua MCP trên Virtual Controller cục bộ; xem phạm vi kiểm chứng bên dưới.

---

## ✨ Features & Architecture Highlights

| Feature | Original | LiskinLabs v3.1.0 |
|---|---|---|
| HTTP Transport | `HttpListener` — requires `netsh urlacl` (Admin) | **`TcpListener`** — zero admin rights required |
| Tool Count | 50 | **63** (+13 new tools) |
| Add-In Installation | Manual per-session "Load Add-In" | **AutoLoad** (cần kiểm chứng runtime 6.08) |
| RAPID Validation | None (silent syntax failures) | ✅ **`rs_validate_rapid`** (structural AST block check) |
| Safety Guard | None (sim starts blindly) | ✅ **`rs_check_safety`** + pre-simulation error block |
| Path Traversal Defense | None | ✅ **`validateControllerPath`** ($SYSTEM protection, `..` filter) |
| RWS Target Switching | Static env var | ✅ **`rws_set_controller_url`** (runtime virtual ↔ real switch) |
| 3D Screenshot | ❌ | ✅ `rs_get_screenshot` (base64 PNG) |
| Controller Event Log | ❌ | ✅ `rs_get_execution_errors` & `rws_event_log` |
| Variable Inspection | ❌ | ✅ `rs_list_variables` (type & module filters) |
| Individual I/O Control | Stubs | ✅ `rs_read_io_signal` & `rs_write_io_signal` |
| Automated Testing | None | ✅ **`npm test`** (`node:test` suite in CI) |

---

## Build và dùng với RobotStudio 6.08 trên máy này

Add-In được chuyển sang **.NET Framework 4.6.1**, tham chiếu trực tiếp SDK 6.08 đang cài tại `D:\Program Files (x86)\ABB Industrial IT\Robotics IT\RobotStudio 6.08`. Đã kiểm chứng nạp Add-In, `rs_ping`, `rs_read_module` trên Virtual Controller cục bộ; chưa kiểm chứng ghi chương trình, mô phỏng hoặc robot thật.

### 1. Build MCP và Add-In

Chạy PowerShell tại thư mục repository:

```powershell
Set-Location 'D:\mcp_server\mcp-robotstudio\abb-robotstudio-mcp'
npm ci
npm run build
npm test
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\install-addin.test.ps1

$rs = 'D:\Program Files (x86)\ABB Industrial IT\Robotics IT\RobotStudio 6.08'
$json = Join-Path $rs 'Bin\Addins\ConveyorTrackingModuleAddin\Newtonsoft.Json.dll'
dotnet build .\addin\ClaudeBridge.csproj -c Release "-p:RobotStudioDir=$rs" "-p:NewtonsoftJsonPath=$json"
```

Cần Node.js tương thích các dependency trong `package-lock.json` và .NET SDK có thể build .NET Framework. Lần restore đầu cần truy cập NuGet để lấy reference assemblies 4.6.1. Không cần nâng RobotStudio. Nếu cài ở nơi khác, đổi `$rs`; nếu không có ConveyorTrackingModuleAddin, cung cấp đường dẫn bản `Newtonsoft.Json.dll` tương thích thay cho `$json`.

Kết quả: `dist/index.js`, `addin/bin/ClaudeBridge.dll` và `addin/bin/Newtonsoft.Json.dll`. Không chép DLL ABB từ SDK sang thư mục Add-In.

### 2. Chuẩn bị hoặc cài Add-In

```powershell
# Luôn rebuild với SDK được chỉ định, validate manifest bằng XSD của 6.08,
# rồi copy DLL bridge, Newtonsoft và manifest vào artifacts\ClaudeBridge.
powershell -ExecutionPolicy Bypass -File .\install-addin.ps1

# Chọn thư mục staging khác; lệnh này vẫn build trước khi copy.
powershell -ExecutionPolicy Bypass -File .\install-addin.ps1 -RobotStudioDir $rs -NewtonsoftJsonPath $json -Destination .\addin\bin\staging

# Tùy chọn: đóng RobotStudio, chạy PowerShell được nâng quyền nếu cần.
# Cài vào $rs\Bin\Addins\ClaudeBridge.
powershell -ExecutionPolicy Bypass -File .\install-addin.ps1 -RobotStudioDir $rs -System
```

Mặc định chỉ tạo staging trong repository. Không thấy lệnh “Load Add-In” trên giao diện 6.08 đã kiểm tra. Cách đã nạp thành công: lưu station, đóng RobotStudio, rồi mở lại bằng `/addin:` từ thư mục repo:

```powershell
$bridge = Join-Path $PWD 'artifacts\ClaudeBridge\ClaudeBridge.rsaddin'
$station = 'D:\program_abb\Solutions\ABB_Pick&Place_v1.0\Stations\ABB_Pick&Place_v1.0.rsstn'
Start-Process -FilePath (Join-Path $rs 'Bin64\RobotStudio.exe') -ArgumentList @("/addin:`"$bridge`"", "`"$station`"")
```

Đổi `$station` theo station cần mở. Khi chỉ dùng staging, truyền lại `/addin:` ở lần khởi động tiếp theo. Chưa kiểm chứng AutoLoad sau cài toàn hệ thống hoặc đường dẫn user Add-In của các phiên bản mới.

Mở station với Virtual Controller rồi kiểm tra:

```powershell
Invoke-RestMethod 'http://localhost:58080/ping'
```

Nếu không có phản hồi, xem Output của RobotStudio và xác nhận Add-In đã được nạp trước khi cấu hình MCP. Các thao tác ghi RAPID, I/O, simulation hoặc chương trình có thể thay đổi station/controller; kiểm tra trên Virtual Controller trước.

### 3. Cấu hình MCP cho Codex

Thêm vào cấu hình TOML của Codex (ví dụ `%USERPROFILE%\.codex\config.toml`), rồi khởi động lại client:

```toml
[mcp_servers.abb_robotstudio]
command = "node"
args = ['D:\mcp_server\mcp-robotstudio\abb-robotstudio-mcp\dist\index.js']

[mcp_servers.abb_robotstudio.env]
ABB_BRIDGE_URL = "http://localhost:58080"
ABB_RWS_URL = "http://localhost:80"
ABB_RWS_USER = "Default User"
ABB_RWS_PASS = "robotics"
```

`rs_*` đi qua Add-In; `rws_*` kết nối trực tiếp controller. Đổi `ABB_RWS_URL` sang endpoint Virtual Controller thực tế; các giá trị trên chỉ là mẫu, không tự phát hiện controller. Chỉ dùng credential mặc định cho môi trường test phù hợp. Sau khi client thấy tools, gọi `rs_ping`, rồi các lệnh đọc station/module trước khi chỉnh sửa.

### Phạm vi kiểm chứng 6.08

Manifest hợp lệ với XSD 6.08 và Add-In build thành công với SDK cục bộ, target net461. Đã nạp bằng `/addin:`, đọc `/ping`, `/station`, `/rapid/tasks`, `/rapid/modules`, và kiểm tra MCP stdio `rs_ping`, `rs_read_module` với `Module1`/`CalibData` của `T_ROB1`, controller `Controller_Pick_Place_1` (RobotWare 6.08.01.00). Chưa kiểm tra AutoLoad, ghi RAPID, mastership, mô phỏng hay robot thật.

RWS GET `/rw/rapid/tasks/T_ROB1/modules` hiện dùng trong tool `rws_get_modules` trả 404 trên controller này; liên kết controller cung cấp `/rw/rapid/modules?task=T_ROB1` trả 200. Dùng `rs_get_modules`/`rs_read_module` qua bridge cho thao tác đã kiểm chứng; chưa sửa các tool RWS trong lượt chỉ đọc này.

Nguồn cục bộ để đối chiếu: `RobotStudioDir\Schemas\RobotStudioAddin.xsd`, `RobotStudioDir\Help\en\RobotStudio API Reference.chm` và `RobotStudioDir\Bin\Addins`.

---
## 🛠️ Complete Tool Index (63 Tools)

### SDK Tools (`rs_*`) — 33 tools
- **Connection & Status:** `rs_ping`, `rs_controller_status`, `rs_check_safety`
- **Station Management:** `rs_get_station`, `rs_get_station_objects`, `rs_save_station`, `rs_get_screenshot`
- **RAPID Management:** `rs_get_tasks`, `rs_get_modules`, `rs_read_module`, `rs_write_module`, `rs_validate_rapid`
- **Variables & Data:** `rs_read_variable`, `rs_write_variable`, `rs_list_variables`
- **I/O Signals:** `rs_get_io_signals`, `rs_read_io_signal`, `rs_write_io_signal`
- **Simulation Control:** `rs_start_simulation`, `rs_stop_simulation`, `rs_pause_simulation`, `rs_reset_simulation`, `rs_simulation_status`, `rs_set_sim_speed`, `rs_check_collisions`
- **Motion & Targets:** `rs_get_position`, `rs_get_paths`, `rs_get_path_targets`, `rs_create_path`, `rs_create_target`
- **Diagnostics & Config:** `rs_get_execution_errors`, `rs_read_config`, `rs_write_config`

### RWS Tools (`rws_*`) — 30 tools
- **Controller & Target:** `rws_set_controller_url`, `rws_controller_status`, `rws_restart_controller`
- **Execution & Safety:** `rws_set_motors`, `rws_start_program`, `rws_stop_program`, `rws_reset_pp`, `rws_execution_state`, `rws_get_speed_override`, `rws_set_speed_override`
- **RAPID & Modules:** `rws_get_tasks`, `rws_get_modules`, `rws_read_module`, `rws_write_module`, `rws_load_module_from_file`, `rws_unload_module`, `rws_save_program`, `rws_load_program`
- **Variables & I/O:** `rws_read_variable`, `rws_write_variable`, `rws_get_position`, `rws_get_io_signals`, `rws_read_io`, `rws_write_io`
- **Filesystem & Logs:** `rws_list_files`, `rws_read_file`, `rws_write_file`, `rws_event_log`
- **Mastership:** `rws_request_mastership`, `rws_release_mastership`

---

## 🔒 Safety Guardrails

- **Zero-Accident Policy:** `rs_start_simulation` and `rws_start_program` automatically scan the controller event log for active RAPID and syntax errors before allowing execution.
- **Path Sanitization:** File operations via RWS enforce `validateControllerPath`, rejecting any `..` directory traversal and forbidding access to `$SYSTEM` critical controller partitions.
- **BOM-Free UTF-8:** Code writes enforce CRLF line-endings and strip UTF-8 Byte Order Marks to guarantee error-free RAPID compiler parsing.

---

## 📜 License & Credits

- **Original Foundation:** [Elias Bitsch](https://github.com/eliasbitsch) — [abb-robotstudio-mcp](https://github.com/eliasbitsch/abb-robotstudio-mcp) (MIT License).
- **Architecture & Hardening:** [LiskinLabs](https://github.com/LiskinLabs) — Silvestr Liskin.
- License: [ISC](LICENSE)
