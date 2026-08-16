# 任务简报 AN：全量面级分析工具（可达性/难度/参数/数据质量）

> 项目：Trigger Echo。分支 feat/m1-assets，单目录 `/Users/elanyi/Projects/Trigger-Echo`。
> 前置：AU（旋转增强）已完成——`Levels/M2_TDM/jump_edges_dataset.json` 含顶层 `"faces"`
> （160 面）+ 增强 human 边（augmented 标记）。本任务基于该数据集 + 两库实测数据产出
> 完整面级分析报告。
> 用户拍板的数据哲学（2026-08-16，必须反映在口径中）：人类成功=训练主源；人类失败=
> 面难度分析（失误多的面降权）；自动数据=验证器（可行性+成功率）；难面在训练与实战
> 双降权。

## 任务范围

- 新工具（唯一生产文件）：`tools/analyze_faces.py`（纯标准库、确定性、只读全部输入）
- 产出：`docs/reports/2026-08-16-face-analysis.md`（新建目录）+ `/tmp/face_analysis.json`
- **禁止改动**：数据集/语料/auto_traversal 目录/既有任何代码与测试

## 输入（只读）

1. `Levels/M2_TDM/jump_edges_dataset.json`——faces（160）+ edges（human 真实/增强 +
   physics verdict）+ link_audit
2. 人类语料 `~/Library/Application Support/Godot/app_userdata/Trigger Echo/jump_training/`
   ——episodes 全量（含 fail 分类，难度口径必需）
3. 自动遍历 `~/Library/Application Support/Godot/app_userdata/Trigger Echo/auto_traversal/`
   ——summary.json（per_face verdicts）+ attempts head 行（link/verdict/failure_reason）
   （若目录缺失或为空 → auto 字段标 "无数据"，不崩）

## 每面输出字段（160 面，字典序）

```python
{
  "name": str, "top_y": float,
  "reachability": str,   # 见口径
  "difficulty": {"tier": str, "score": int, "reasons": [str]},
  "human": {"real_n": int, "augmented_n": int, "fail_n": int, "fail_ratio": float},
  "auto": {"attempts": int, "success": int, "latest_verdict": str},
  "in_edges": [{"from": str, "verdict": str, "human_p50": float, "human_n": int,
                "augmented": bool}],
}
```

## 口径（确定性公式，逐字实现）

1. **可达性 reachability**：
   - auto 数据该面最新 verdict == "no_path" → `"导航不可达"`
   - 面出现在任一 link_audit 的 from_face/to_face → `"跳跃链接可达"`
   - auto 最新 verdict == "success" → `"实测可达"`
   - 其余（auto 无该面数据且无链接）→ `"未实测"`（优先级自上而下：no_path 最弱信号放最后
     判定——实际顺序：先 no_path 判断 → 链接判断 → success → 未实测；no_path 与链接
     同时成立时取 "导航不可达（链接存在但实测 no_path）"）
2. **难度 difficulty**（进面边= edges 中 to_face == 该面）：
   ```
   verdict_rank = {"easy": 0, "tight": 1, "knife": 2, "infeasible": 3}
   score = min(进面边 verdict_rank)   # 最好进路的几何难度；无进面边 → 0
   人类失误率（同面失败，口径：classification=="fail" 且 start==end==该面 且
     该面 != "Ground"——Ground 平地跳是战斗噪声，用户已拍板排除）:
     human_fail_ratio = fail_n / (fail_n + 该面所有进面边 real human n 之和)
     ratio ≥ 0.5 → score += 2；≥ 0.25 → score += 1
   自动执行：auto 该面 attempts ≥ 2 且成功率 < 0.5 → score += 1
   tier: 0 → "简单"；1 → "中等"；2 → "困难"；≥3 → "高难"
   reasons 逐条列出（如 "进路 verdict=tight"、"人类失误率 0.67"、"自动成功率 0/5"）
   ```
3. **human**：real_n = 进面边真实 human n 之和；augmented_n = 增强 human n 之和；
   fail_n/fail_ratio 如上
4. **auto**：从 summary.per_face 取（attempts/verdict；success 计数 = verdict=="success"）
5. **in_edges**：每条进面边一行（from 面、verdict、human p50（真实/增强都取，augmented
   标 true）、human n）

## 报告输出

`docs/reports/2026-08-16-face-analysis.md`（新建目录）结构：

1. 汇总：总面数 160；分 tier 计数表；人类语料总览（706 episodes：climb/traverse/fail）；
   增强边数；自动数据快照（r9 65 attempts 成功率）
2. 分 tier 清单（每个 tier 一节，面名字典序，每面一行：
   `name（top_y=x.xm）| 可达性 | 人类 n 真实/增强/失误率 | 自动 成/试 | 最优进路 verdict`）
3. 无数据面清单（human real==0 且 augmented==0 且 auto 无 attempts）
4. 数据质量注记（增强边标记说明 + 人类频率偏好的对称性验证证据一段）

`/tmp/face_analysis.json`：全部字段原始数据（deterministic，跑两次逐字节一致）。

## 验证（全部执行并贴输出）

1. 跑两次 diff 输出逐字节一致（确定性）
2. 抽查锚（手算对照，贴报告证据）：
   - CorridorSlab：fail 8 / Ground→CorridorSlab climb 4 → 失误率 8/(8+4)=0.67 → tier
     至少「困难」
   - EastTowerBox：无真实 human、WestTower→WestTowerBox climb 4 增强 → augmented_n=4、
     tier 由 verdict 决定（easy→简单）
   - UmbrellaN：auto no_path → 导航不可达
   - Ground：排除在失误率口径外（fail_n 不计 Ground→Ground）
3. 汇总数字与三库数据一致（如 edges 增强数 == AU 报告数）

## 报告格式

开头一行 DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED + 改动清单 + 汇总数字 +
抽查锚证据 + 报告文件路径。
