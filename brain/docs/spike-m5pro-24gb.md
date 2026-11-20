# Spike results
- Chip: Apple M5 Pro, RAM: 24.00 GB, GPU budget: 17.76 GB, macOS Version 27.2.1 (Build 26B131)

(running system…)

(running qwen3_4b_4bit…)

(running qwen3_8b_4bit…)

| Model | Download | Load s | Tokens/s | Peak MLX | Peak footprint | Tool calls |
|---|---|---|---|---|---|---|
| system | n/a | 0.0 | 16.6 | n/a | 0.06 GB | 16/20 |
| qwen3_4b_4bit | 2.12 GB | 12.7 | 12.7 | 2.88 GB | 2.44 GB | 18/20 |
| qwen3_8b_4bit | 4.30 GB | 777.8 | 4.9 | 7.09 GB | 6.76 GB | 20/20 |

system misses:
- “I drank a glass of water” expected change_goal_progress, got no tool
- “I meditated today” expected change_goal_progress, got no tool
- “Undo my last water entry” expected change_goal_progress, got no tool
- “Reopen the flights task” expected set_task_status, got set_task_status(taskid=8 status=in_progress)

qwen3_4b_4bit misses:
- “Remind me to email Sam, high priority” expected add_task, got no tool
- “Add a task to water the plants” expected add_task, got add_task(title=water plants project=inbox priority=)
