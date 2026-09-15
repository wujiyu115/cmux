# WSL 终端中继(wsl.exe)空转烧 CPU:排查记录

日期:2026-09-11 ｜ 环境:Windows 10 19045、WSL 2.7.13.0 + Ubuntu 20.04、TeamPilot 会话 = ConPTY + `wsl.exe -d Ubuntu20.04 --cd <path>`

## 症状

- 任务管理器显示 TeamPilot "占用 CPU 60%",机器持续高负载。
- 打开的十来个 WSL 终端会话大多空闲(停在 shell 提示符),没有重活在跑。

## 结论(TL;DR)

烧 CPU 的**不是** TeamPilot.exe(实测 ~1.5%),也**不是** WSL 虚拟机 vmmem(<0.5%),而是**个别会话的 wsl.exe 子中继进程在空转**:对已 EOF 的 Hyper-V socket 做每秒数百万次"成功但读 0 字节"的 ReadFile 死循环。根因是 WSL 上游已知 bug [microsoft/wsl#41173](https://github.com/microsoft/wsl/issues/41173):会话启动时 hvsocket 出现 EOF 竞态,`ProcessInteropMessages` 读循环缺少同步 EOF 检查,从此永远自旋。

任务管理器把 wsl.exe 的 CPU 归组到 TeamPilot 名下,所以用户看到的是 "TeamPilot 60%"。

**应用侧无法根治**(自旋在微软的 wsl.exe 二进制内部),但可以检测 + 引导重开会话规避——竞态命中率约 2/12,重开大概率恢复正常。详见下文"应用侧能做什么"。

## 证据链(按排查顺序)

### 1. 分层归因:谁在烧 CPU

16 逻辑核,5 秒差分采样(`TotalProcessorTime` 两次相减):

| 对象 | 瞬时 CPU |
|---|---|
| TeamPilot.exe | ~1.5% |
| vmmem(整个 Linux 侧) | <0.5% |
| **wsl.exe pid=198068** | **~143%**(≈22 核突发) |
| **wsl.exe pid=172008** | **~86%**(≈14 核突发) |
| 其余 9 个会话的 wsl.exe | ~0 |

### 2. 定位热点会话

进程树:每个 TeamPilot 会话 = `TeamPilot.exe → wsl.exe(ConPTY 宿主)→ wsl.exe(中继)`。两个热点中继分别属于:

- pid 198068 → `--cd /home/ejoy/git/sedna-ship`(09:22 创建)
- pid 172008 → `--cd /home/ejoy/git/workflow_web`(14:15 创建)

### 3. 会话内部完全空闲(排除"终端里有活")

两个会话各自的 pts 里只有 `-zsh` 停在提示符:6 秒写 **0 字节**、0% CPU、PTY 尺寸正常(54×227,排除"面板折叠成 0 行导致 ConPTY busy-loop"假设)。

### 4. 空转从会话创建就开始(排除当天其他事件)

| 进程 | 存活时长 | 累计 CPU | 平均 |
|---|---|---|---|
| 198068 | 6.3h | 41,059s | ≈1.8 核 |
| 172008 | 86min | 14,347s | ≈2.8 核 |
| 健康会话对照(9 个) | 0.5–21h | 0–12s | ≈0 |

即从创建起持续烧,与下午 15:13 的 951MB `/mnt/c → ~/.claude` 拷贝(ai-toolbox-sync,9P 跨界 IO)无关——那个拷贝当时确实也烧 CPU,但已结束,不是持续占用源。

### 5. I/O 计数器差分(决定性证据)

6 秒窗口(`Win32_Process` 的 `ReadOperationCount` 差分):

| 进程 | 6s 读操作数 | 6s 读到字节 |
|---|---|---|
| 198068(热点) | **27,635,684** | **0** |
| 172008(热点) | **17,069,254** | **0** |
| 197344(健康对照) | 0(进程存活期间累计仅 178 次) | 0 |

每秒 400 多万次 ReadFile 系统调用、零字节返回——教科书级 busy-poll。198068 进程累计已做 **408 亿次**空读。

### 6. 线程画像(确认是内核态 syscall 风暴)

自旋线程 `ThreadState=Running`,内核态时间为用户态的 **~20 倍**(如 2,116s vs 97s)。多根线程阵发自旋:平均 1.8–2.8 核,瞬时突发可到 20+ 核,与"任务管理器 60%"吻合。

### 7. 健康反例(排除"高吞吐转发本来就贵")

一个正跑 qodercli、6 分钟输出 118MB 的会话,其中继累计 CPU 仅 12s。转发大量数据不烧 CPU;烧 CPU 的是零吞吐空转。

## 与 2026-09-10 启动卡死记录的区别

[wsl-terminal-startup-stall.md](wsl-terminal-startup-stall.md) 是**创建路径**阻塞:`CreatePseudoConsole` 在 console 争用下排队 60s。本问题是**运行路径**空转:会话正常创建后,中继读循环因上游竞态死循环。两者都是 Win10/WSL 平台层问题,应用侧分别以"不阻塞/不误杀"和"检测/引导重启"应对。

## 应用侧能做什么 / 不能做什么

**不能根治**:自旋发生在 wsl.exe 内部(微软二进制),应用无权修补;上游 issue 尚未修复,WSL 2.7.13 未带补丁。

**能做的,按性价比排序**:

1. **看门狗检测 + 引导重启(推荐)**。基础设施已就绪:
   - `pty_create` 已为每个会话挂 kill-on-close Job Object(`flutter_pty_win.c` 的 `create_kill_on_close_job`),作业按继承覆盖整棵 wsl.exe 进程树(含中继)。
   - 新增小 FFI 查询 `JobObjectBasicAccountingInformation` 即可拿到作业聚合 CPU 时间;Dart 侧 `TerminalSession` 天然知道输出字节流。
   - 判定:`终端输出增量 = 0 且作业 CPU 增量折算 >50% 单核,持续 ~60s` → toast 提示该终端命中已知 WSL 空转 bug(#41173),附一键重启。
   - 竞态概率约 20%,重开即好。**提示文案必须警告"重启会终止会话内进程"**(用户可能有 dev server 在跑)。
2. **跟踪上游**:关注 #41173 修复进度;`wsl --update` 升级后用本文"复测方法"验证。
3. **已评估、不可行的方向**:
   - 禁用 interop(`/etc/wsl.conf` `[interop] enabled=false`)——不确定能停掉 ProcessInteropMessages 泵,且牺牲用户从 WSL 调 Windows 程序的能力;
   - 挂起/终止单根自旋线程——破坏会话一致性,得不偿失。

## 复测方法(给未来排查者)

```powershell
# 1) 谁在烧:5s 差分采样(16 核机器)
$s1 = @{}; Get-Process | ForEach-Object { $s1[$_.Id] = $_.TotalProcessorTime.TotalMilliseconds }
Start-Sleep -Seconds 5
Get-Process | ForEach-Object {
  if ($s1.ContainsKey($__.Id)) {
    $d = ($_.TotalProcessorTime.TotalMilliseconds - $s1[$_.Id]) / 5000 * 100 / 16
    if ($d -gt 0.5) { Write-Host ('{0,-22} pid={1,-8} cpu={2,5:N1}%' -f $_.Name, $_.Id, $d) }
  }
}

# 2) 零字节读风暴确认(热点 pid):两次采样相减,ReadOperationCount 暴涨、ReadTransferCount 不动
Get-CimInstance Win32_Process -Filter 'ProcessId=<pid>' |
  Select-Object ProcessId,ReadOperationCount,ReadTransferCount,WriteOperationCount

# 3) 会话内部是否空闲(WSL 侧):找会话 pts 的进程与 6s 写出量
wsl.exe -d <distro> -e bash -c "ps -eo pid,ppid,tty,stat,pcpu,args --no-headers | grep pts/<n>"
```

判定特征:**会话内 0 输出 + 中继每秒百万级零字节读 + 内核态时间主导** → 命中本问题;重开该终端 tab 即恢复。
