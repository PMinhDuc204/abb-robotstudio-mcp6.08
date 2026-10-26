# ABB RobotStudio MCP Server

Connect an MCP client to ABB RobotStudio and ABB robot controllers through two interfaces: an in-process RobotStudio SDK bridge and Robot Web Services (RWS).

This repository contains a TypeScript MCP server and the **ClaudeBridge** C# Add-In. It registers **63 tools: 33 `rs_*` tools and 30 `rws_*` tools**. The current desktop integration targets **RobotStudio 6.08 on Windows**.

The package version is `3.1.0`. The MCP handshake and startup banner currently report `3.0.0`, while the Add-In manifest reports `2.0.0`; these version labels have not yet been synchronized.

## Contents

- [Architecture](#architecture)
- [Requirements](#requirements)
- [Installation](#installation)
- [MCP client configuration](#mcp-client-configuration)
- [Configuration reference](#configuration-reference)
- [First connection](#first-connection)
- [Tool reference](#tool-reference)
- [RAPID validation and writes](#rapid-validation-and-writes)
- [Operational limits](#operational-limits)
- [RobotStudio 6.08 compatibility](#robotstudio-608-compatibility)
- [Troubleshooting](#troubleshooting)
- [Development and tests](#development-and-tests)
- [License and credits](#license-and-credits)

## Architecture

```text
MCP client
    |
    | MCP over standard input/output
    v
Node.js server: dist/index.js
    |
    +-- rs_* tools -- HTTP --> ClaudeBridge Add-In, 127.0.0.1:58080
    |                             |
    |                             +--> RobotStudio SDK / controller SDK
    |
    +-- rws_* tools -- HTTP(S) --> Controller Robot Web Services
```

| Interface | Purpose | Requires |
|---|---|---|
| `rs_*` | Inspect/edit the active station, access RAPID through the SDK, control simulation, capture screenshots | RobotStudio running with ClaudeBridge loaded; station/controller as required by the tool |
| `rws_*` | Access controller execution, RAPID runtime values, I/O, files, event logs, and mastership | A reachable controller exposing a compatible RWS API and suitable credentials |

The MCP transport is **stdio**, not an HTTP MCP endpoint. Port `58080` belongs to the internal SDK bridge. Changing the RWS target does not change the station or controller selected by the SDK bridge.

RWS can be used without loading the Add-In. Most `rs_*` tools need the Add-In; `rs_validate_rapid` performs its structural check locally. Large SDK module writes can also use RWS, as described below.

## Requirements

### MCP server

- Node.js and npm compatible with the locked dependencies. The repository's CI configuration uses Node.js 20.
- An MCP client supporting stdio servers.
- Network access for the initial `npm ci` dependency installation.

### RobotStudio bridge

- Windows with RobotStudio **6.08** installed and its SDK assemblies available.
- A .NET SDK capable of building the `net461` Add-In. Initial restore may need NuGet access to obtain .NET Framework reference assemblies.
- A compatible `Newtonsoft.Json.dll`. By default, the build uses the copy installed with RobotStudio's Conveyor Tracking Add-In.
- A station with a Virtual Controller for controller-dependent operations and initial testing.

The default SDK location is:

```text
D:\Program Files (x86)\ABB Industrial IT\Robotics IT\RobotStudio 6.08
```

Override this location with `-RobotStudioDir` when building or staging the Add-In. ABB SDK assemblies are referenced from the installed application and are not copied into the bridge deployment.

### Direct RWS access

Configure the controller URL and account explicitly. A working connection to one Virtual Controller does not establish compatibility with every IRC5, OmniCore, or RobotWare release. In particular, the current code has a known module-endpoint mismatch on the tested RobotWare 6.08 controller.

## Installation

Run the following commands in PowerShell from your checkout. Replace the example repository and RobotStudio paths with your own locations.

### 1. Build the MCP server

```powershell
Set-Location 'D:\mcp_server\mcp-robotstudio\abb-robotstudio-mcp'
npm ci
npm run build
npm test
```

The server entry point is `dist/index.js`. Build before running tests because the tests import the compiled output.

### 2. Build and stage the Add-In

```powershell
$rsDir = 'D:\Program Files (x86)\ABB Industrial IT\Robotics IT\RobotStudio 6.08'
$jsonDll = Join-Path $rsDir 'Bin\Addins\ConveyorTrackingModuleAddin\Newtonsoft.Json.dll'

powershell -NoProfile -ExecutionPolicy Bypass -File .\install-addin.ps1 `
  -RobotStudioDir $rsDir `
  -NewtonsoftJsonPath $jsonDll
```

The installer validates the manifest against the installed RobotStudio XSD, rebuilds the Add-In against that SDK, and stages these files in `artifacts\ClaudeBridge`:

```text
ClaudeBridge.dll
ClaudeBridge.rsaddin
Newtonsoft.Json.dll
```

The default operation stages files inside the checkout; it does not install them into the RobotStudio application directory. A failed build stops deployment before the copy step.

If the default Newtonsoft assembly is absent, pass an existing compatible DLL using `-NewtonsoftJsonPath`.

Optional staging directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-addin.ps1 `
  -RobotStudioDir $rsDir `
  -NewtonsoftJsonPath $jsonDll `
  -Destination .\artifacts\ClaudeBridge-custom
```

Optional application-directory installation:

```powershell
# Close RobotStudio first. Use an elevated shell if the destination requires it.
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-addin.ps1 `
  -RobotStudioDir $rsDir `
  -NewtonsoftJsonPath $jsonDll `
  -System
```

`-System` copies into `RobotStudioDir\Bin\Addins\ClaudeBridge`. It cannot be combined with `-Destination`. The manifest requests automatic loading, but system-installed AutoLoad has not been confirmed on the tested 6.08 setup.

### 3. Load the staged Add-In

The verified loading method for RobotStudio 6.08 is the `/addin:` startup argument. Save your work and close RobotStudio before launching it with the bridge.

```powershell
$bridgeManifest = Join-Path $PWD 'artifacts\ClaudeBridge\ClaudeBridge.rsaddin'
$stationPath = 'D:\RobotStudioProjects\Example\Example.rsstn'
$robotStudioExe = Join-Path $rsDir 'Bin64\RobotStudio.exe'

Start-Process -FilePath $robotStudioExe -ArgumentList @(
  "/addin:`"$bridgeManifest`"",
  "`"$stationPath`""
)
```

Use a real station path. With staged deployment, supply `/addin:` again on subsequent launches. The verified 6.08 UI did not expose a usable “Load Add-In” command, so this guide does not depend on one.

### 4. Check the bridge

```powershell
Invoke-RestMethod 'http://localhost:58080/ping'
```

Check RobotStudio's Output window for the bridge startup message. The Add-In binds to IPv4 loopback on port `58080` using `TcpListener`; it does not require an HTTP URL ACL reservation. Installation into a protected application directory may still require elevation.

## MCP client configuration

### Codex

Add the following to your Codex TOML configuration, typically `%USERPROFILE%\.codex\config.toml`. Update the absolute server path and controller endpoint, then restart or reconnect the client.

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

These credentials are the defaults in the repository and are intended as an example for a suitable local test controller. Set the credentials required by your controller. Do not publish private credentials in a committed client configuration.

### Clients using an `mcpServers` JSON configuration

```json
{
  "mcpServers": {
    "abb_robotstudio": {
      "command": "node",
      "args": [
        "D:\\mcp_server\\mcp-robotstudio\\abb-robotstudio-mcp\\dist\\index.js"
      ],
      "env": {
        "ABB_BRIDGE_URL": "http://localhost:58080",
        "ABB_RWS_URL": "http://localhost:80",
        "ABB_RWS_USER": "Default User",
        "ABB_RWS_PASS": "robotics"
      }
    }
  }
}
```

If `node` is unavailable to the desktop client, use the absolute path to your Node.js executable. No working-directory setting is required when the script path is absolute.

## Configuration reference

| Variable | Default | Meaning |
|---|---|---|
| `ABB_BRIDGE_URL` | `http://localhost:58080` | HTTP base URL for the loaded ClaudeBridge Add-In |
| `ABB_RWS_URL` | `http://localhost:80` | Initial controller RWS base URL; not automatically discovered |
| `ABB_RWS_USER` | `Default User` | RWS account name |
| `ABB_RWS_PASS` | `robotics` | RWS password |
| `ABB_RWS_ALLOWED_HOSTS` | Empty | Comma-separated additional hostnames/IP addresses permitted by runtime target switching |

The built-in runtime-switching host list contains `localhost`, `127.0.0.1`, `[::1]`, and `192.168.125.1`. Additional entries are hostnames/IP addresses, not full URLs.

Example additional host:

```toml
ABB_RWS_ALLOWED_HOSTS = "192.168.1.50"
```

`rws_set_controller_url` validates HTTP(S) URLs against this list and resets the cached RWS session after switching. Credentials remain those loaded when the server started. The initial `ABB_RWS_URL` is read directly from the environment; the runtime allowlist is not a universal outbound-network restriction.

The bridge listening port is a constant in the Add-In. Changing `ABB_BRIDGE_URL` only changes the client destination; it does not reconfigure the listener.

## First connection

Start with inspection on a Virtual Controller:

1. Call `rs_ping` to confirm bridge connectivity.
2. Call `rs_get_station` and verify the station/controller identity.
3. Call `rs_get_tasks` and inspect the available task names.
4. Call `rs_get_modules` with `{"task":"T_ROB1"}` or the task discovered above.
5. Call `rs_read_module` with the selected task and an existing module name.
6. If using RWS, call `rws_controller_status` separately and verify that it points to the intended controller.

Example tool arguments:

```json
{
  "task": "T_ROB1",
  "module": "Module1"
}
```

Example requests to an MCP assistant:

```text
Inspect the active station and list its RAPID tasks and modules without changing them.

Read Module1 from T_ROB1 and explain its I/O dependencies.

Validate this RAPID module structurally without uploading or executing it.

Check the simulation status and recent controller errors without starting motion.
```

Inspection tools do not intentionally start robot motion. Some SDK module-read fallbacks may export temporary files to retrieve source text, so “read” does not imply zero filesystem activity.

## Tool reference

The tables list registered capabilities, not a claim that every operation has passed runtime testing. Consult the input schema exposed by your MCP client for required arguments, defaults, and optional flags.

### RobotStudio SDK tools — 33

| Category | Tools |
|---|---|
| Connection and status | `rs_ping`, `rs_controller_status`, `rs_check_safety` |
| Station | `rs_get_station`, `rs_get_station_objects`, `rs_save_station`, `rs_get_screenshot` |
| RAPID modules | `rs_get_tasks`, `rs_get_modules`, `rs_read_module`, `rs_write_module`, `rs_validate_rapid` |
| Variables | `rs_read_variable`, `rs_write_variable`, `rs_list_variables` |
| I/O | `rs_get_io_signals`, `rs_read_io_signal`, `rs_write_io_signal` |
| Simulation | `rs_start_simulation`, `rs_stop_simulation`, `rs_pause_simulation`, `rs_reset_simulation`, `rs_simulation_status`, `rs_set_sim_speed` |
| Position, paths, and targets | `rs_get_position`, `rs_get_paths`, `rs_get_path_targets`, `rs_create_path`, `rs_create_target` |
| Diagnostics and configuration | `rs_get_execution_errors`, `rs_check_collisions`, `rs_read_config`, `rs_write_config` |

SDK variable tools access declaration/initial-value data. Use the RWS variable tools when you need live controller runtime values. Target creation accepts XYZ only; it does not expose a complete orientation, tool/workobject selection, or a verified robot configuration. Verify the resulting target and coordinate units in RobotStudio before using it for motion.

### Robot Web Services tools — 30

| Category | Tools |
|---|---|
| Controller and target selection | `rws_set_controller_url`, `rws_controller_status`, `rws_restart_controller` |
| Execution | `rws_set_motors`, `rws_start_program`, `rws_stop_program`, `rws_reset_pp`, `rws_execution_state` |
| Speed override | `rws_get_speed_override`, `rws_set_speed_override` |
| RAPID modules and programs | `rws_get_tasks`, `rws_get_modules`, `rws_read_module`, `rws_write_module`, `rws_load_module_from_file`, `rws_unload_module`, `rws_save_program`, `rws_load_program` |
| Runtime variables and position | `rws_read_variable`, `rws_write_variable`, `rws_get_position` |
| I/O | `rws_get_io_signals`, `rws_read_io`, `rws_write_io` |
| Files and logs | `rws_list_files`, `rws_read_file`, `rws_write_file`, `rws_event_log` |
| Mastership | `rws_request_mastership`, `rws_release_mastership` |

RWS requests negotiate Digest authentication and retain controller session state. Several RAPID write/load operations request and release mastership automatically; do not assume that all writes do so. Operations remain subject to the controller's permissions, operating mode, and API support.

Controller filesystem paths are controller-side paths such as `$HOME/Example.mod`, not Windows paths on the MCP host.

## RAPID validation and writes

### Structural validation

`rs_validate_rapid` checks matching RAPID block delimiters, including module, routine, conditional, loop, trap, and record blocks. It is a lightweight structural checker, **not ABB's RAPID compiler**. It does not prove symbol resolution, type correctness, instruction availability, reachability, or collision-free motion.

Both `rs_write_module` and `rws_write_module` run this check before uploading unless `skipValidation=true` is supplied. Passing validation does not guarantee that the controller will accept the module.

### SDK module replacement

The standard SDK write path loads the requested module using `RapidLoadMode.Replace` by default, or `RapidLoadMode.Add` when `replace=false`. It preserves unrelated modules rather than deleting the task's entire program first. This behavior is implemented in the Add-In but is not covered by the recorded read-only runtime verification.

The standard Add-In write path normalizes line endings to CRLF and writes UTF-8 without an encoding preamble. Do not assume equivalent normalization for every RWS write path or that encoding normalization guarantees successful compilation.

### Large-module routing

When `code.length > 50_000`, `rs_write_module` first attempts an RWS file upload/load operation. `useFileUpload=true` forces that route. Automatic routing can fall back to the SDK bridge if the file route fails; forced file upload does not use that fallback.

Important implementation details:

- The threshold uses JavaScript string length, not encoded byte size.
- The RWS fallback must point at the **same intended controller** as the SDK bridge; the server does not establish that correspondence automatically.
- The file-upload helper always requests replacement and does not honor `replace=false`.
- It uses `$HOME/_claude_upload` as a temporary upload location and attempts cleanup afterward.

Back up affected modules before editing and inspect controller diagnostics after loading. Module writes do not automatically synchronize every corresponding RobotStudio station representation.

## Operational limits

### Software preflight checks

`rs_start_simulation` and `rws_start_program` normally run software preflight checks. They inspect controller state and/or recent event-log entries and block when the check reports errors or cannot complete. `force=true` bypasses the preflight.

These checks use a limited set of recent events and filtering heuristics. They may include historical errors or miss conditions outside that window. The returned `safe` field means the software preflight passed; it is not a physical safety assessment or an ABB safety certification.

`rs_check_collisions` invokes the station collision-check API. Its current response is not a detailed collision report; review configured collision sets and the RobotStudio UI before drawing conclusions about a path.

### Mutating operations

Simulation controls, I/O writes, module/program loading, configuration writes, program-pointer resets, motor commands, and controller restarts can change the connected environment. Validate workflows on a Virtual Controller before considering hardware use. Controller permissions and physical safeguards remain necessary.

`rs_write_config` writes a file in the local controller system directory; it does not provide a complete configuration import, validation, backup, or restart workflow.

### Network and path boundaries

- The Add-In listens on loopback, but its HTTP API is not authenticated. Treat it as a trusted-local-process interface and do not expose it through a public proxy or port forward.
- Runtime RWS switching has a host allowlist; startup environment configuration remains trusted input.
- Active RWS file tools use the path validator defined in `src/index.ts`. That validator rejects `..` and requires a supported controller-root path, but **accepts `$SYSTEM` as well as `$HOME` and `$TEMP`**.
- A separate validator in `src/safety-guard.ts` rejects `$SYSTEM`, but that is not the validator wired into those tool handlers. The current implementation must not be described as universally blocking system-root access.

## RobotStudio 6.08 compatibility

Recorded results in [COMPATIBILITY_608.md](COMPATIBILITY_608.md) establish the following scope for the tested local installation:

| Area | Recorded result |
|---|---|
| SDK build | Add-In targets `net461` and builds against the installed 6.08 SDK |
| Manifest | Validates against the installed 6.08 XSD |
| Loading | `/addin:` startup loading confirmed |
| Bridge access | `/ping`, `/station`, RAPID task/module listing confirmed |
| MCP stdio | `rs_ping` and `rs_read_module` confirmed end to end |
| Controller | Virtual Controller running RobotWare `6.08.01.00` |
| System AutoLoad | Not confirmed |
| Controller mutations and simulation | Not established by that read-only verification record |
| Physical robot operation | Not tested |

### Known RWS module endpoint mismatch

On the recorded RobotWare 6.08 controller:

```text
GET /rw/rapid/tasks/T_ROB1/modules   -> 404
GET /rw/rapid/modules?task=T_ROB1    -> 200
```

The current `rws_get_modules` implementation uses the first route. For the verified module-inspection workflow, use `rs_get_modules` and `rs_read_module` through the bridge. Other RWS module operations also require version-specific validation; the table does not imply a general RWS compatibility guarantee.

See the compatibility report for the recorded evidence, SDK adaptation details, and limitations. Its Vietnamese text is retained as a separate historical report; this README is entirely in English.

## Troubleshooting

| Symptom | Check |
|---|---|
| MCP tools do not appear | Run `npm run build`; verify the absolute `dist/index.js` path, Node executable, and client logs; reconnect the client. |
| `ECONNREFUSED` from ClaudeBridge | Start RobotStudio with the Add-In loaded and test `/ping`. Confirm port `58080`; do not confuse it with the controller's RWS port. |
| `localhost` fails but the Add-In is loaded | Test `http://127.0.0.1:58080/ping`; the Add-In binds IPv4 loopback. |
| Add-In fails to build | Check `RobotStudioDir`, SDK DLLs, the Newtonsoft DLL path, and NuGet/reference-assembly restore output. |
| Add-In loads only for one session | Staged deployment requires `/addin:` on each launch. System-installed AutoLoad is not confirmed on the tested setup. |
| Bridge request times out | Check for a busy RobotStudio UI thread, modal dialogs, or a long-running operation; inspect Output before retrying a write. |
| Station/controller-dependent tools fail | Open the intended station, ensure its Virtual Controller is ready, and inspect available tasks before using task/module names. |
| RWS authentication fails | Verify the endpoint, credentials, controller permissions, and API version. Bridge connectivity does not validate RWS connectivity. |
| Runtime URL switch is rejected | Add the exact hostname/IP to `ABB_RWS_ALLOWED_HOSTS`, restart the server, and retry the intended HTTP(S) URL. |
| RWS module listing returns 404 on 6.08 | Use the bridge module tools; see the known endpoint mismatch above. |
| Controller path is rejected | Use controller-root paths and forward slashes; inspect the active path validator in `src/index.ts`. |
| RAPID passes validation but fails to load | Structural balance is only a preliminary check. Read the controller event log and fix compiler or permission errors. |
| Start is blocked by preflight | Inspect reported events and controller state. Do not use `force=true` as the normal fix. |
| A large `rs_write_module` behaves differently | Check automatic RWS routing, controller identity, credentials, and the file-upload replacement behavior. |

## Development and tests

### Repository layout

```text
src/
  index.ts               MCP tool registration and routing
  config.ts              Bridge/RWS settings and runtime URL selection
  bridge-client.ts       HTTP client for the in-process Add-In
  rws-client.ts          RWS HTTP client, Digest sessions, and mastership
  rapid-validator.ts     RAPID structural checks
  safety-guard.ts        Preflight checks and a separate path validator
addin/
  ClaudeBridgeAddIn.cs   RobotStudio/controller SDK integration
  ClaudeBridge.csproj    net461 build and installed SDK references
  ClaudeBridge.rsaddin   Add-In manifest
test/
  validator.test.js      Structural validation and helper path checks
  mcp.test.js            MCP stdio discovery and invalid-write rejection
  install-addin.test.ps1 Installer fixture tests
install-addin.ps1        Build, validate, and stage/install the Add-In
COMPATIBILITY_608.md     Recorded compatibility evidence
```

### Commands

```powershell
npm run build
npm test
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\install-addin.test.ps1
```

`npm start` runs the built stdio server. `npm run dev` builds it once and starts it; it is not a file-watching development server. A server launched directly in a terminal may wait silently for MCP messages on stdin.

To build the Add-In without deployment:

```powershell
dotnet build .\addin\ClaudeBridge.csproj -c Release `
  "-p:RobotStudioDir=$rsDir" `
  "-p:NewtonsoftJsonPath=$jsonDll"
```

The Node tests do not require a live robot. They cover selected validator behavior and MCP stdio registration/rejection, not all 63 operations. Installer tests use fixtures and do not prove RobotStudio runtime loading. In particular, testing the helper validator does not establish the path policy of the active RWS handlers.

The CI workflow builds and runs Node tests on Ubuntu with Node.js 20. It does not build or launch the Windows RobotStudio Add-In.

## License and credits

The checked-in [LICENSE](LICENSE) contains the **MIT License**, copyright 2026 Elias Bitsch. `package.json` currently declares `ISC`; this metadata mismatch remains unresolved. Refer to the license file rather than assuming the declarations agree.

- Original project: [Elias Bitsch — abb-robotstudio-mcp](https://github.com/eliasbitsch/abb-robotstudio-mcp).
- This edition's existing attribution credits [LiskinLabs](https://github.com/LiskinLabs) and Silvestr Liskin for architecture and hardening work.

ABB RobotStudio, its SDK, RobotWare, and related ABB components are separate products subject to their own licensing terms.
