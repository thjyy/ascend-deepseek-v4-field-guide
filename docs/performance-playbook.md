# 性能验证与指标解释

## 先定义你要优化什么

| 目标 | 主要指标 | 倾向策略 |
|---|---|---|
| 单用户流畅 | TTFT、ITL、单请求token/s | 较小批处理、稳定TP域、图执行、投机解码 |
| 多用户吞吐 | 总output token/s、P95排队 | 多副本DP或多个服务实例、合理批处理 |
| 超长上下文 | 最大可用KV、prefill速度 | Chunked Prefill、控制并发、匹配缓存实现 |
| Agent可靠性 | 工具循环完成率、abort率 | 输出上限、超时、流解析、请求审计 |

## 冷启动与预热

容器健康后不要立刻记录第一条请求为最终性能。ACL Graph首次回放、算子编译和内存池稳定都可能产生额外开销。

建议流程：

1. 等待 `/health=200`；
2. 发3-5个短请求预热；
3. 再开始正式计时；
4. 单请求、4并发、8并发、16并发分别测试；
5. 每组保存完整启动参数和模型版本。

## 一个可重复的流式探测

```bash
for i in 1 2 3; do
  curl --max-time 120 -sS -N -o /dev/null \
    -w "run=$i HTTP=%{http_code} first_byte=%{time_starttransfer}s total=%{time_total}s\n" \
    http://127.0.0.1:7000/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{
      "model":"deepseek-v4-flash",
      "messages":[{"role":"user","content":"请用约200字解释推理服务的吞吐与延迟。"}],
      "max_tokens":256,
      "temperature":0,
      "stream":true
    }'
done
```

流式接口的 `time_starttransfer` 可能只代表HTTP头或首个空SSE块，不一定是首个正文token。严谨TTFT应从客户端记录第一个非空content delta。

## 从Prometheus累计计数计算吞吐

累计指标需要在两个时间点取差值：

```text
generation throughput =
  (generation_tokens_total(t2) - generation_tokens_total(t1)) / (t2 - t1)
```

不要直接把某一时刻的累计值当成吞吐，也不要把日志的10秒窗口尾部值当成整次请求平均速度。

## 对比实验模板

| 实验 | 唯一变化 | 结果 | 结论 |
|---|---|---|---|
| A | DSpark开，Graph开，batch16K | 单请求可能停滞 | 记录为故障基线 |
| B | 仅关闭Graph | 仍可能停滞 | Graph不是唯一原因 |
| C | 仅关闭DSpark | 用于确认基础模型可生成 | 诊断基线，不直接代表最佳性能 |
| D | batch改8K，其余恢复 | 多轮请求稳定完成 | 8K作为当前稳定基线 |
| E | 正式Compose重建 | 首请求冷，预热后恢复 | 固化配置未引入持续退化 |

每次实验都应保留旧容器，而不是覆盖唯一可用环境。

