# SHA-256 本机复现流程与修复记录

整理日期：2026-10-14。本文按本次实际运行结果整理，使用当前工作区的修复版脚本；原仓库的 README 数值不代表本次结果。

## 1. 流程和本机环境

```text
环境安装 → RTL 仿真 → 综合 → 综合后门级功能仿真 → 布局/CTS/布线/寄生提取/STA
 → DEF 与 Verilog 连接比较 → 最终布线修复
 → Magic DRC 与实际版图提取 LVS → 最终网表门级功能仿真
 → 功耗/PDN/静态 IR → GDS 导出与结构检查 → 热力图
```

| 项目 | 本次路径或版本 |
| --- | --- |
| OS | Ubuntu 22.04.5 LTS |
| 工程 | `/root/eda/SHA-256` |
| ORFS | `/root/eda/OpenROAD-flow-scripts` |
| PDK 源码 | `/root/eda/open-pdks`，目录名用连字符 |
| 安装的 PDK | `/usr/local/share/pdk/sky130A` |
| 原仓库 HEAD | `6ae6b275ce7d401ae7a423fb11eda4c9074ac5cb` |
| ORFS HEAD | `e5cc6e799f5ddf36e6bdf2d8c5db73373b88f52c` |
| OpenROAD | `26Q4-110-g91e5f5ff2f` |
| Yosys | `0.68+`，提交 `a5af9d690` |
| Icarus | 11.0 |
| Magic | 8.3.685 |
| Netgen 源码 VERSION | 1.5.324 |
| KLayout | 0.30.12 |
| open-pdks HEAD | `0ec4fa67eade28cd0a4352c04df981840809427b` |

完整工具、PDK 库源码和子模块提交见 `flow/local/reproduction/environment.txt`。

`synth_local.ys`、`openroad_flow_15ns_local.tcl`、`repair_final_route.tcl` 仍含本机绝对路径。换目录时必须同步修改，不能认为新脚本已经完全跨机器参数化。

## 2. 工具安装：已安装的本机可跳过

### 2.1 工程与补丁

```bash
mkdir -p /root/eda
cd /root/eda
git clone https://github.com/Xavierwar2/SHA-256.git
cd SHA-256
```

当前已经修复的工作区不要重复应用补丁。

### 2.2 基础工具和 Icarus

```bash
sudo apt update
sudo apt install -y \
  iverilog git curl ca-certificates build-essential \
  autoconf automake libtool pkg-config m4 tcsh tcl-dev tk-dev \
  libx11-dev libxrender-dev libgl1-mesa-dev libglu1-mesa-dev \
  libcairo2-dev libreadline-dev libncurses-dev libpng-dev zlib1g-dev \
  python3 python3-pip python3-venv
```

### 2.3 OpenROAD 与配套 Yosys

```bash
cd /root/eda
git clone https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git
cd OpenROAD-flow-scripts
git checkout e5cc6e799f5ddf36e6bdf2d8c5db73373b88f52c
git submodule update --init --recursive
sudo -E ./setup.sh
./build_openroad.sh --local --threads 2
source ./env.sh
openroad -version
yosys -V
command -v klayout
```

默认构建会安装配套 Yosys，不必另外 `apt install yosys`；已装的 apt 版本可以并存。以 `command -v yosys` 确认使用版本。`--openroad_only` 会跳过配套工具，本文不使用该选项。

`setup.sh` 会安装 KLayout 等依赖。若仍缺少 KLayout，可 `sudo apt install klayout`，但发行版版本可能不同。安装后与环境快照核对，不应认为安装最新源码必然得到同样结果。

### 2.4 Magic 与 Netgen LVS

```bash
cd /root/eda
git clone https://github.com/RTimothyEdwards/magic.git
cd magic
git checkout bed8d4ff84333767aa923d469d339cd05c56a00a
./configure --prefix=/usr/local
make -j2
sudo make install
magic --version

cd /root/eda
git clone https://github.com/RTimothyEdwards/netgen.git
cd netgen
git checkout 3cb047bd6b55ae09c8eefeb479b4fe746cfdb948
./configure --prefix=/usr/local
make -j2
sudo make install
netgen -batch <<'TCL'
puts "Netgen Tcl interface loaded"
quit
TCL
```

使用 RTimothyEdwards 的 Netgen LVS；Ubuntu 同名 `netgen` 软件包可能是网格生成工具。

### 2.5 完整 sky130A PDK

```bash
export PATH="/usr/local/bin:$PATH"
cd /root/eda
git clone https://github.com/fossi-foundation/open-pdks.git open-pdks
cd open-pdks
git checkout 0ec4fa67eade28cd0a4352c04df981840809427b
./configure --prefix=/usr/local --enable-sky130-pdk --with-sky130-variants=A
make -j1 > build.log 2>&1 && sudo make install > install.log 2>&1
```

只有构建成功后才安装。把日志直接写入文件，可避免本次遇到的终端 `tee` I/O 错误。构建后不要改目录名，否则暂存配置和 `.magicrc` 链接可能失效。

```bash
export PDK_ROOT=/usr/local/share/pdk
export PDK_PATH="$PDK_ROOT/sky130A"
ls -lh \
  "$PDK_PATH/libs.tech/magic/sky130A.magicrc" \
  "$PDK_PATH/libs.tech/netgen/sky130A_setup.tcl" \
  "$PDK_PATH/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds" \
  "$PDK_PATH/libs.ref/sky130_fd_sc_hd/cdl/sky130_fd_sc_hd.cdl" \
  "$PDK_PATH/libs.ref/sky130_fd_sc_hd/spice/sky130_fd_sc_hd.spice" \
  "$PDK_PATH/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v"
```

仅有 `libs.tech` 配置不等于主库安装完整。早期综合/PnR 使用 OpenROAD 测试目录里的 Liberty/LEF；实际版图检查、门级模型和后续分析使用完整 PDK。

### 2.6 带标尺热力图的 Python 依赖

本机活动 Python 已有 Matplotlib。新环境若缺少，可使用独立环境：

```bash
/usr/bin/python3 -m venv /root/eda/plot-venv
source /root/eda/plot-venv/bin/activate
python3 -m pip install matplotlib
```

绘图入口使用活动环境的 `python3`；LVS 使用 `/usr/bin/python3`，解析器只依赖标准库。

## 3. 已安装环境的阶段命令

每次新终端先设置：

```bash
source /root/eda/OpenROAD-flow-scripts/env.sh
export OPENROAD="$(command -v openroad)"
export PDK_ROOT=/usr/local/share/pdk
export PDK_PATH="$PDK_ROOT/sky130A"
export PATH="/usr/local/bin:$PATH"
```

ORFS 的 `env.sh` 把 `OPENROAD` 设成源码目录，而原 `run_all.sh` 将它当可执行文件。上面的赋值消除冲突；新增入口用 PATH 中的 `openroad` 或可选 `OPENROAD_EXE`。

### A. RTL 功能仿真

```bash
cd /root/eda/SHA-256/Verilog
iverilog -s SHA256_testbench -o /tmp/sha256_rtl_sim SHA256.v SHA256_testbench.v
vvp /tmp/sha256_rtl_sim
```

成功标志：`MSG SUCCESSFULLY HASHED`。默认测试数据为新增的 `tb_data_abc.txt`。

`-s` 指定测试平台顶层。测试平台已移除对 `SHA256.v` 的 include，所以编译传入这两个文件。顶层源码内部已经 include 子模块，不要再用 `Verilog/*.v` 重复编译。

原 `tb_data.txt` 是双消息块测试。当前 `wvar.v` 每次 `soc` 都重新加载固定 IV，不能正确累计跨块哈希状态。本次保留原文件，改用单块数据，不把这一改动说成修复了 RTL 多块功能。

另可重跑仓库的空串和 abc RTL 向量：

```bash
cd /root/eda/SHA-256/flow
mkdir -p local/rtl_fips
iverilog -g2012 -I../Verilog -s fips_180_4_post_sim_tb \
  -o local/rtl_fips/fips.vvp fips_180_4_post_sim_tb.v ../Verilog/SHA256.v
(cd local/rtl_fips && vvp fips.vvp)
```

### B. Yosys 综合与输入检查

```bash
cd /root/eda/SHA-256/flow
mkdir -p local
yosys -Q -T -l local/synth.log synth_local.ys > local/synth.stdout.log 2>&1
openroad -no_init -exit check_local_inputs.tcl > local/check_inputs.log 2>&1
```

输入：RTL 和 TT Liberty。输出：`local/SHA256_synth.v`。输入检查成功标志：`LOCAL INPUT CHECK PASSED`，验证网表、LEF、Liberty 和 15 ns 约束可正确读入。

### B2. 综合后门级功能仿真（PnR 前）

```bash
cd /root/eda/SHA-256/flow
bash run_synth_gate_sim_local.sh
```

输入是 Yosys 生成的 `local/SHA256_synth.v` 与完整 PDK 的 `primitives.v`、`sky130_fd_sc_hd.v`；不再编译 RTL 顶层。复用 `sha256_gate_local_tb.v`，通过 `-DSYNTH_GATE` 选择综合阶段。

Yosys 网表没有 VDD/VSS 端口，因此不定义 `USE_POWER_PINS`，也不强制 DUT 内部电源线；布线后仿真仍使用原来的电源配置。`-DFUNCTIONAL` 选择无延迟标准单元功能模型。

输出为 `local/synth_gate_sim/compile.log`、`sim.log`、`gate.vcd`。成功标志为 empty/abc 两个 PASS 和 `ALL POST-SYNTHESIS FUNCTIONAL TESTS PASSED`。这是零延迟功能检查，不能验证布线时序，也不能替代形式等价检查。

### C. 布局、CTS、布线、寄生提取和 STA

```bash
cd /root/eda/SHA-256/flow
set -o pipefail
openroad -no_init -exit openroad_flow_15ns_local.tcl 2>&1 | tee local/pnr.log
```

输出在 `local/`：DEF、ODB、布线后 Verilog、SPEF、STA、天线及布线 DRC 报告。

本机脚本已补上“插入二极管后再 detailed_route”的循环、剩余违规检查、最终 global_connect 和 `write_verilog -include_pwr_gnd`。不再仅修改已布线单元/连接却不更新布线。

### D. DEF 与 Verilog 连接比较（诊断）

```bash
cd /root/eda/SHA-256/flow
bash run_lvs_local.sh
```

读 `local/SHA256_15ns.odb`，应用全局电源规则，检查未连接电源端子，导出到 `local/lvs_connected/` 后运行 Netgen。

报告：`local/lvs_connected/SHA256_15ns.netgen_lvs.v6pos.report`。本次比较 6,469 个非物理标准单元；物理专用单元被排除。此步骤验证 DEF 记录与 Verilog 连接，不是实际金属提取 LVS。

### E. 最终布线修复、Magic DRC、实际版图提取 LVS

```bash
cd /root/eda/SHA-256/flow
bash run_physical_lvs_local.sh
```

入口先执行 D，再从数据库补跑布线；包括天线修复后重新布线、违规检查、filler、电源连接、寄生提取和 STA。随后以同一修复版 DEF 做 Magic DRC，再用 PDK 单元 GDS 几何和实际 DEF 金属布线提取电路，与完整工艺 SPICE 电路比较。

最终设计：`local/route_repaired/`；最终提取与 LVS：`local/physical_lvs/`。

提取使用 `ext2spice blackbox off`，保留晶体管定义。不删除提取单元电路，不用库电路替代布局侧，不截断实例端口。VDD/VSS 标签落在实际供电金属条带上，不通过修改提取网表的连接强行匹配。

成功标准：Magic `Total DRC violations: 0`；Netgen **最后**的 `Final result: Circuits match uniquely.`；同版路由的布线 DRC/天线为 0，Setup/Hold 裕量非负。

已有修复版且没有改变布线时，可以只重做 DRC/提取/LVS：

```bash
bash run_physical_lvs_local.sh --skip-route
```

`local/extracted_lvs/` 是早期失败诊断产物，不代表最终结果；最终依据是 `local/physical_lvs/`。

### F. 最终网表门级功能仿真

```bash
cd /root/eda/SHA-256/flow
bash run_gate_sim_local.sh
```

输入：`local/route_repaired/SHA256_15ns_final.v` 和 PDK 的 `primitives.v`、`sky130_fd_sc_hd.v`。新 TB 在下降沿驱动输入，避开上升沿采样竞争，适配内部 VDD/VSS 网。

输出：`local/gate_sim/sim.log`、`gate.vcd`。通过标志为两个 PASS 和 `ALL POST-ROUTE FUNCTIONAL TESTS PASSED`。

这是 15 ns 时钟下的**无延迟门级功能仿真**，没有 SDF 回标。本次时序由 STA 检查，不能把功能仿真当成带延迟的时序仿真。

### G. 功耗、PDN 连通性、静态 IR Drop

```bash
cd /root/eda/SHA-256/flow
bash run_power_ir_local.sh
```

依次运行 `run_power_local.tcl`、`run_power_grid_local.tcl`、`run_ir_drop_local.tcl`；输入是修复版 ODB/SPEF、完整 PDK 的 TT Liberty 和 15 ns 约束。

输出：`local/power_ir/power.rpt`、`power.log`、`power_grid.log`、`ir_drop.log` 及电压/错误报告。单项命令：

```bash
mkdir -p local/power_ir
openroad -no_init -exit run_power_local.tcl > local/power_ir/power.log 2>&1
openroad -no_init -exit run_power_grid_local.tcl > local/power_ir/power_grid.log 2>&1
openroad -no_init -exit run_ir_drop_local.tcl > local/power_ir/ir_drop.log 2>&1
```

功耗使用 OpenSTA 默认翻转活动。IR 使用 `vdd_vsrc.txt`/`vss_vsrc.txt` 中每条轨四个理想电源点；没有真实工作负载、封装电阻或动态压降。`-dont_require_terminals` 允许独立 block 没有外部供电 PAD，但仍检查网格连接。

### H. GDS 导出与结构检查

```bash
cd /root/eda/SHA-256/flow
bash run_gds_export_local.sh
```

输出：`local/gds/SHA256_final.gds`。KLayout 重新读完整文件，核对顶层、实例数、边界、大小和 SHA-256，写 `validation.json`/`validation.log`。

```bash
# 有桌面环境时查看
klayout local/gds/SHA256_final.gds
```

这是文件完整性和结构检查，尚未完成“最终导出 GDS 独立重新导入，再做 DRC/LVS”。此前实际版图 LVS 的输入为单元 GDS 几何加最终 DEF。

### I. 热力图

```bash
cd /root/eda/SHA-256/flow
bash run_heatmaps_local.sh
```

七类图在 `local/heatmaps/`：布局密度、引脚密度、功耗密度、RUDY、布线拥塞、VDD/VSS met1 IR。包含原生 PNG、CSV 和带坐标/标尺的 `*_plot.png`。

Qt offscreen 不需要显示器。IR 图重跑求解；绘图按 CSV 头读取单位，当前 IR 是 mV，不能再次盲乘 1000。功耗图继承默认活动假设。这些图不是温度场求解。

```bash
# 有桌面环境时交互查看
openroad -gui -no_init show_heatmaps_local.tcl
```

左侧 `Display Control → Heat Maps` 选择图，双击名称修改范围、网格和图例。

## 4. 原仓库问题及处理

| 原仓库问题 | 影响 | 修复/替代 |
| --- | --- | --- |
| 旧 TB include 顶层，README 又单独编译顶层 | 重复模块定义 | TB 移除 include |
| 顶层已拆为 8 端口，TB 仍接 6 端口 | 实例化错误，输出读取错误 | 名称连接、data_out 比较、data_oe 检查 |
| 双块默认测试与当前 wvar 固定 IV 不符 | 修改端口后仍哈希失败 | 新增单块 abc，保留原数据，记录多块 RTL 限制 |
| `/home/openroad`、`/mnt/d` 等绝对路径 | 换环境失败 | 新建本机替代脚本 |
| `sky130hd_tt.lib` 等旧文件名 | 当前 ORFS 找不到库 | 按实际库文件名适配 |
| 14.3 ns 与 15 ns 文件混用 | 错误输入或找不到文件 | 统一 15 ns 最终版本目录 |
| 缺失 lvs.py，且被 Git 忽略 | 无法运行 LVS | 新增严格解析器，修改 .gitignore |
| strip_parasitics.py 等依赖缺失 | 旧晶体管流水线不能直接跑 | 新建保留真实提取结果的流程 |
| CTS/修复/filler 后无最终 global_connect | 新单元供电端子未关联 | 导出前补连接，并检查所有端子 |
| 详细布线后加二极管却不重新布线 | 逻辑比较通过，实际版图 LVS 失败 | 修复后再次 detailed_route 并检查剩余违规 |
| 布线后修时序/移动单元后不重布线 | 实际几何和连接可能不一致 | 去掉未配套布线的后置修改，修复路由后重提取 |
| DRC 汇总无条件打印 PASS | 文字可能误导 | 按真实计数和报告判定 |
| 提取/STA catch 失败后仍 COMPLETE | COMPLETE 不代表全过 | 检查实际下游文件和独立报告 |
| fix_layout_subckts 删除提取定义并截断端口 | 不能证明内部版图真实等价 | 实际版图 LVS 不使用该脚本 |
| LVS 只看 Netgen 进程返回码 | 不匹配也可能退出 0 | 仅接受最后 Final result；负向测试验证 |
| 功耗汇总写死 25.9 mW 等 | 不反映本次结果 | 只报告本次 report_power/PDNSim 输出 |
| 门级命令未完整给最终网表和模型 | 后仿不能直接跑 | 新入口给完整模型和适配 TB |
| run_all.sh 的路径/输入/依赖未统一 | 本机不能直接全流程复现 | 使用本文入口，保留原脚本对照 |

以下属于**本次环境问题**，不是 SHA-256 RTL 问题：

- Git 全局代理指向未监听的 7890，覆盖环境代理；移除旧配置后成功克隆。
- PDK 构建发生 `tee` 输出 I/O 错误，随后安装了不完整库；改用文件日志、构建成功后安装。
- 构建目录 `open_pdks` 改名为 `open-pdks` 后，暂存链接/路径失效；修复后重建 HD 库。
- 当前 GUI Tcl 无法设置 ShowLegend 布尔选项；保留原生图，另从 CSV 生成有标尺的图。
- `.gitignore` 的 `flow/test_*.py` 忽略了新增测试；已单独放行 `test_lvs.py`。

## 5. 哪些文件修改了

实际修改原文件：

| 文件 | 修改 |
| --- | --- |
| `Verilog/SHA256_testbench.v` | include、端口、输出校验、默认数据和失败退出 |
| `flow/run_lvs_15ns.py` | 数据目录、严格引脚/电源校验、合法悬空输出、最终报告判断 |
| `.gitignore` | 放行 lvs.py 和 test_lvs.py |

新增文件（未标目录者都在 flow）：

| 用途 | 文件 |
| --- | --- |
| RTL 数据 | `Verilog/tb_data_abc.txt` |
| 综合/检查 | `synth_local.ys`、`check_local_inputs.tcl` |
| PnR/修复 | `openroad_flow_15ns_local.tcl`、`repair_final_route.tcl` |
| 连接 LVS | `lvs.py`、`test_lvs.py`、`connect_lvs_power.tcl`、`run_lvs_local.sh` |
| 实际版图 | `run_magic_drc_local.tcl`、`extract_layout_lvs.tcl`、`run_extracted_lvs.py`、`run_physical_lvs_local.sh` |
| 门级 | `sha256_gate_local_tb.v`、`run_synth_gate_sim_local.sh`、`run_gate_sim_local.sh` |
| 功耗/IR | `load_final_local.tcl`、`run_power_local.tcl`、`run_power_grid_local.tcl`、`run_ir_drop_local.tcl`、`run_power_ir_local.sh` |
| GDS | `export_gds_local.tcl`、`verify_gds_local.py`、`run_gds_export_local.sh` |
| 图 | `render_heatmaps_local.tcl`、`plot_heatmaps_local.py`、`show_heatmaps_local.tcl`、`run_heatmaps_local.sh` |
| 文档 | 本文、`LVS_LOCAL.md`、`POWER_GDS_LOCAL.md`、`HEATMAPS_LOCAL.md` |

原 `synth.ys`、`openroad_flow_15ns_signoff.tcl`、`run_all.sh`、旧提取和功耗脚本没有被覆盖，新脚本作为替代入口。

## 6. 本次结果及证据

| 项目 | 本次结果 | 相对 flow 的证据 |
| --- | --- | --- |
| RTL | abc、空串验证通过 | 测试文件和此前运行；阶段 A 可重跑 |
| 最终 STA | Setup +0.380 ns；Hold +0.090 ns | `local/route_repaired/repair.log`、`timing.rpt` |
| 布线 DRC/天线 | 0 | `local/route_repaired/repair.log`、`route_drc.rpt` |
| Magic DRC | 0 | `local/route_repaired/SHA256_15ns_magic_drc_signoff.rpt` |
| 实际版图 LVS | 通过；两侧 6,487 器件/6,507 网络 | `local/physical_lvs/lvs.report`、`lvs.log` |
| 综合后门级功能 | 空串/abc 通过 | `local/synth_gate_sim/sim.log` |
| 布线后门级功能 | 空串/abc 通过 | `local/gate_sim/sim.log` |
| 估算功耗 | 26.4 mW | `local/power_ir/power.rpt` |
| 电源网格 | VDD/VSS 连通 | `local/power_ir/power_grid.log` |
| 静态 IR | VDD 4.04 mV；VSS 5.61 mV | `local/power_ir/ir_drop.log` |
| GDS | 600×600 µm；47,347 实例；21,085,984 bytes | `local/gds/validation.json` |
| 热力图 | 七类 | `local/heatmaps/` |

GDS 实例数包含 filler、tap 等，不能与非物理标准单元数或 LVS 器件数直接比较。原 `local/pnr.log` 的 +0.378/+0.089 ns 是旧版；最终结果是修复版提取后的 +0.380/+0.090 ns。

已验证七项解析/报告测试，以及故意修改 NAND 输入后的连接 LVS、实际版图 LVS 失败检测：

```bash
cd /root/eda/SHA-256/flow
/usr/bin/python3 -m unittest -v test_lvs
```

尚未完成：SDF 回标、形式等价检查、最终 GDS 独立重新读入 DRC/LVS、真实工作负载功耗、封装/动态 IR、多块 RTL 修复。现有 PASS 不代替这些项目。

## 7. 一段命令重跑设计阶段

已完成安装、应用补丁后执行；遇到失败会停止。重做 PnR 后不得混用上次下游报告。

```bash
set -euo pipefail
source /root/eda/OpenROAD-flow-scripts/env.sh
export OPENROAD="$(command -v openroad)"
export PDK_ROOT=/usr/local/share/pdk
export PATH="/usr/local/bin:$PATH"

cd /root/eda/SHA-256/Verilog
iverilog -s SHA256_testbench -o /tmp/sha256_rtl_sim SHA256.v SHA256_testbench.v
vvp /tmp/sha256_rtl_sim

cd ../flow
mkdir -p local
yosys -Q -T -l local/synth.log synth_local.ys > local/synth.stdout.log 2>&1
openroad -no_init -exit check_local_inputs.tcl > local/check_inputs.log 2>&1
bash run_synth_gate_sim_local.sh
openroad -no_init -exit openroad_flow_15ns_local.tcl 2>&1 | tee local/pnr.log
bash run_physical_lvs_local.sh
bash run_gate_sim_local.sh
bash run_power_ir_local.sh
bash run_gds_export_local.sh
bash run_heatmaps_local.sh
```

实际版图入口会调用连接 LVS，所以不重复单独调用 D。新的主 PnR 已修复布线遗漏，仍保留独立修复入口，确保后续都使用 `route_repaired/`。

## 8. 官方参考

- [OpenROAD 本机构建](https://openroad-flow-scripts.readthedocs.io/en/latest/user/BuildLocally.html)
- [open-pdks sky130 安装](https://github.com/fossi-foundation/open-pdks/blob/main/sky130/README)
- [OpenROAD 天线修复后再布线](https://github.com/The-OpenROAD-Project/OpenROAD/blob/master/test/flow.tcl)
- [Magic ext2spice LVS/blackbox](https://opencircuitdesign.com/magic/commandref/ext2spice.html)
- [OpenROAD 静态 IR 和 PDN 检查](https://openroad.readthedocs.io/en/latest/main/src/psm/README.html)
- [OpenROAD 热力图](https://openroad.readthedocs.io/en/latest/main/src/gui/README.html#set-heatmap)
