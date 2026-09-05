# 故障现象与判断矩阵

## 快速判断表

| 现象 | 优先检查 | 常见原因 | 不要立刻做什么 |
|---|---|---|---|
| 容器 `running` 但服务不通 | `RestartCount`、最近日志、端口监听 | 进程正处于重启循环或模型尚未加载 | 不要只重复 `docker restart` |
| `/health=200` 但请求无正文 | running/waiting、generation counter、引擎日志 | 生成引擎停滞、客户端已断开或图执行卡住 | 不要把超时无限增大 |
| 只有8卡有进程 | `ASCEND_RT_VISIBLE_DEVICES`、TP×DP | 配置本来就是 TP8/DP1 | 不要误判为硬件故障 |
| 16卡不如8卡流畅 | TP/DP含义、低并发路由、NUMA/HCCS | DP2不提升单请求速度，或跨域通信开销 | 不要直接改TP16 |
| 模型目录数百GB仍缺文件 | `.incomplete`、索引引用、实际挂载层级 | 下载中断、重复分片、挂载错目录 | 不要只看 `du -sh` |
| 512K启动报KV不足 | 镜像/权重组合、量化识别、缓存布局 | 通用镜像未正确识别专用权重或实现发生变化 | 不要盲目提高HBM利用率到1.0 |
| Agent工具调用后不回复 | 每一轮请求ID、客户端输出上限、abort | 工具结果后的下一轮没发出、输出预算过大 | 不要先怪反代 |
| 日志 `output:''` | `--max-log-len`、实际HTTP响应 | 为避免泄露正文而设置0长度日志 | 不要据此判断空回答 |

## 最小证据包

遇到问题时，先收集以下信息，再修改参数：

```bash
docker inspect -f \
'Status={{.State.Status}} RestartCount={{.RestartCount}} Image={{.Config.Image}}' \
<container>

docker inspect -f '{{range .Config.Entrypoint}}{{println .}}{{end}}' <container>

docker logs --since 10m <container> 2>&1 | \
grep -E 'Received request|Added request|Generated response|Aborted request|Avg prompt throughput|SpecDecoding|ERROR|WARNING|Traceback' | \
tail -200

curl --max-time 5 -sS http://127.0.0.1:7000/metrics | \
grep -E '^vllm:(num_requests_running|num_requests_waiting|kv_cache_usage_perc|prompt_tokens_total|generation_tokens_total){'
```

## 如何确认请求真的卡住

需要同时满足多个证据：

1. API 日志已经出现 `Added request`；
2. 多个统计周期仍为 `Running=1`；
3. `generation_tokens_total` 没有增长；
4. 客户端没有收到正文 token；
5. 最终只在客户端超时后出现 `Aborted request`。

如果请求几秒后出现 `Generated response (streaming complete)`，则服务器已经完成；前端仍无结果时应转向客户端流解析、Agent状态机或工具结果回填链路。

## DSpark 指标解释

```text
Mean acceptance length
Accepted throughput
Drafted throughput
Per-position acceptance rate
Avg Draft acceptance rate
```

- 接受率高不一定代表端到端一定更快，还要计算 draft 成本；
- 短中文回答可能只有约20%的平均接受率；
- 长推理任务中可达到更高接受率；
- 判断价值应对比同一请求集“开启/关闭投机解码”的端到端时延和总吞吐。

## 常见警告

### `max_num_scheduled_tokens` 略小于8192

投机解码需要为 draft token 预留槽位，最终可调度值可能显示为8128。这只是小幅预留，不值得为了消除警告重新升到已知会卡顿的16K。

### block size 被运行时改为32

DeepSeek-V4运行时可能把用户指定的128调整为32以获得更好性能。应以启动日志和 metrics 中的 resolved 配置为准。

### cascade attention 被禁用

异步投机解码与 cascade attention 在当前版本中可能不兼容。只要引擎正常启动且请求稳定，这是能力降级提示，不是致命错误。

