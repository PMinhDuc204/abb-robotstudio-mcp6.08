# RobotStudio 6.08 — kết quả kiểm chứng

Ngày: 2026-10-24. Bản cài: `D:\Program Files (x86)\ABB Industrial IT\Robotics IT\RobotStudio 6.08`.

## Bằng chứng và quyết định

- **Quan sát tĩnh bằng REA:** `Bin/ABB.Robotics.RobotStudio.dll` có assembly version `6.8.8307.1040`, target framework `.NETFramework,Version=v4.6.1`, managed architecture AnyCPU. SHA-256 `870bd4dc5975b6f18501bd2fe5c241f62bbdf27c1660139b19d1adb63def609d`. Evidence: `ev_defef50b41847c07a54047c5b244d6f720764fc0d62d505815d9b8de66a4a6f6`. REA không thực thi assembly.
- **Giới hạn REA:** không đọc được member metadata của `ABB.Robotics.Controllers.PC.dll` qua provider này. Evidence: `ev_8374a0ed454fafd380703c657141196a4b9530f049dce1a0378e18bfc065b545`. Không suy ra API vắng mặt từ kết quả đó.
- **Quan sát bằng compiler và reflection-only của .NET Framework:** SDK 6.08 không có `Controller.Connect`/`ConnectionType`; có constructor `Controller(ControllerInfo)`. Add-In dùng constructor này và đã biên dịch thành công với chính SDK cục bộ.
- **Thiết kế:** target `net461`, truyền vị trí SDK qua `RobotStudioDir`; copy riêng Newtonsoft cùng bridge. SDK ABB do RobotStudio cung cấp khi nạp Add-In.
- **Sửa thao tác ghi:** dùng `RapidLoadMode.Replace` cho module được nạp, bỏ vòng lặp xóa các module khác và bỏ xóa module trước khi load. `replace=false` dùng `RapidLoadMode.Add`. Chưa thử ghi trên controller.

## Kiểm tra đã chạy

- `npm run build`: thành công.
- `npm test`: 5 test đạt, gồm MCP stdio liệt kê các tool chỉnh sửa và từ chối RAPID sai cấu trúc trước khi gọi controller. Kiểm tra stdio trực tiếp thấy 63 tools.
- `dotnet build addin/ClaudeBridge.csproj -c Release`: thành công, 0 lỗi. Có warning NU1900 do không lấy được dữ liệu audit NuGet; chưa xác nhận tình trạng lỗ hổng dependency.
- `powershell -NoProfile -ExecutionPolicy Bypass -File test/install-addin.test.ps1`: đạt với fixture, gồm build thất bại không deploy.
- `install-addin.ps1`: build thật và tạo `artifacts/ClaudeBridge` gồm DLL bridge, Newtonsoft và manifest. Manifest hợp lệ với XSD 6.08 trên máy.

## Runtime bổ sung ngày 2026-10-24

- Đã lưu station theo xác nhận của người dùng, Output RobotStudio báo lưu thành công; đóng và mở lại bằng `/addin:"...\artifacts\ClaudeBridge\ClaudeBridge.rsaddin"` cùng đường dẫn station. Output xác nhận bridge khởi động trên port 58080.
- `/ping`, `/station` xác nhận station `ABB_Pick&Place_v1.0`, controller `Controller_Pick_Place_1`, system ID `{B945551D-8705-43E3-8AC9-6A5E25E4122C}`. Đọc `/rapid/tasks`, `/rapid/modules?task=T_ROB1` thành công.
- MCP end-to-end qua stdio: `rs_ping`, `rs_read_module` thành công. Đọc `Module1` (134 dòng, 10 PROC) và `CalibData` (6 dòng), lưu tại `artifacts/current-program/`. Không sửa hoặc chạy RAPID.
- RWS `/rw/system` xác nhận RobotWare 6.08.01.00. `/rw/rapid/tasks/T_ROB1` cung cấp liên kết `/rw/rapid/modules?task=T_ROB1` (200); đường dẫn `/rw/rapid/tasks/T_ROB1/modules` của repo trả 404. Chưa sửa tool RWS trong lượt chỉ đọc này.
- Reflection metadata của `AddinManager.Initialize` và lambda `<Initialize>b__16_2` tìm thấy `/addin:`; runtime xác nhận cách nạp. Provider REA không đọc được executable mixed-mode này; kết quả reflection không phải bằng chứng REA.

## Còn chưa kiểm chứng

Chưa xác nhận AutoLoad, ghi RAPID, mastership, simulation và các tool RWS ngoài các GET nêu trên. Chưa cài toàn hệ thống hoặc sửa cấu hình MCP của Codex. Chỉ các thao tác runtime nêu trên đã được xác nhận. Không có thử nghiệm trên robot thật.
