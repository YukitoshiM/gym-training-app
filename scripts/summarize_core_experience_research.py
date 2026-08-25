#!/usr/bin/env python3
"""Summarize locally exported R5/R9 research sessions without echoing free text."""

from __future__ import annotations

import argparse
import json
import math
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


VALID_VARIANTS = {"A", "B", "C"}
VALID_SCORES = {"correct", "incorrect", "unscored"}
R9_TARGETS = {
    "action": 0.90,
    "reason": 0.80,
    "missing": 0.80,
    "change": 0.80,
}


def wilson_interval(successes: int, total: int, z: float = 1.959963984540054) -> tuple[float, float]:
    if total <= 0:
        return 0.0, 0.0
    proportion = successes / total
    denominator = 1 + z * z / total
    center = (proportion + z * z / (2 * total)) / denominator
    margin = z * math.sqrt((proportion * (1 - proportion) + z * z / (4 * total)) / total) / denominator
    return max(0.0, center - margin), min(1.0, center + margin)


def load_sessions(paths: Iterable[Path]) -> list[dict[str, Any]]:
    sessions: dict[tuple[str, str], dict[str, Any]] = {}
    for path in paths:
        payload = json.loads(path.read_text(encoding="utf-8"))
        records = payload.get("sessions") if isinstance(payload, dict) else None
        if not isinstance(records, list):
            raise ValueError(f"{path}: sessions must be an array")
        for record in records:
            if not isinstance(record, dict):
                raise ValueError(f"{path}: each session must be an object")
            participant = str(record.get("participantCode", "")).strip()
            started_at = str(record.get("startedAt", "")).strip()
            variant = record.get("r5Variant")
            tasks = record.get("tasks")
            if not participant or not started_at or variant not in VALID_VARIANTS or not isinstance(tasks, list):
                raise ValueError(f"{path}: invalid or incomplete session")
            sessions[(participant, started_at)] = record
    return sorted(sessions.values(), key=lambda item: str(item.get("startedAt", "")))


def score_summary(tasks: Iterable[dict[str, Any]], key: str) -> dict[str, Any]:
    counts = Counter()
    for task in tasks:
        score = (task.get("scores") or {}).get(key)
        if score in VALID_SCORES:
            counts[score] += 1
    scored = counts["correct"] + counts["incorrect"]
    low, high = wilson_interval(counts["correct"], scored)
    return {
        "correct": counts["correct"],
        "incorrect": counts["incorrect"],
        "unscored": counts["unscored"],
        "scored": scored,
        "rate": counts["correct"] / scored if scored else None,
        "ci95": [low, high] if scored else None,
    }


def build_summary(sessions: list[dict[str, Any]]) -> dict[str, Any]:
    r5_tasks: dict[str, list[dict[str, Any]]] = defaultdict(list)
    r9_tasks: list[dict[str, Any]] = []
    familiarity = Counter()
    watch_use = Counter()

    for session in sessions:
        familiarity[str(session.get("familiarity", "unknown"))] += 1
        watch_use[str(session.get("watchUse", "unknown"))] += 1
        for task in session.get("tasks", []):
            task_id = str(task.get("taskID", ""))
            if task_id.startswith("r5"):
                r5_tasks[session["r5Variant"]].append(task)
            elif task_id.startswith("r9"):
                r9_tasks.append(task)

    r5 = {}
    for variant in sorted(VALID_VARIANTS):
        tasks = r5_tasks[variant]
        choices = Counter(str(task.get("interactionChoice", "not_recorded")) for task in tasks)
        r5[variant] = {
            "sessions": len(tasks),
            "achievement": score_summary(tasks, "achievement"),
            "next": score_summary(tasks, "next"),
            "interaction_choices": dict(sorted(choices.items())),
            "minimum_sample_met": len(tasks) >= 5,
        }

    r9 = {}
    for key, target in R9_TARGETS.items():
        result = score_summary(r9_tasks, key)
        result["target"] = target
        result["minimum_sample_met"] = result["scored"] >= 5
        result["target_met"] = (
            result["minimum_sample_met"]
            and result["rate"] is not None
            and result["rate"] >= target
        )
        r9[key] = result

    return {
        "schemaVersion": 1,
        "session_count": len(sessions),
        "familiarity": dict(sorted(familiarity.items())),
        "watch_use": dict(sorted(watch_use.items())),
        "r5": r5,
        "r9": r9,
        "gates": {
            "r5_each_variant_at_least_5": all(item["minimum_sample_met"] for item in r5.values()),
            "r9_each_required_question_at_least_5": all(item["minimum_sample_met"] for item in r9.values()),
            "first_time_participant_present": familiarity["first_time"] > 0,
        },
    }


def percentage(value: float | None) -> str:
    return "-" if value is None else f"{value * 100:.1f}%"


def markdown(summary: dict[str, Any]) -> str:
    lines = [
        "# BodyMode コア体験調査 集計",
        "",
        f"- 完了セッション: {summary['session_count']}",
        f"- 初見参加者あり: {'はい' if summary['gates']['first_time_participant_present'] else 'いいえ'}",
        "",
        "## R5 完了画面",
        "",
        "| 案 | n | 達成理解 | 次行動理解 | 95%区間（達成） | 最多選択 | 最低人数 |",
        "| --- | ---: | ---: | ---: | --- | --- | --- |",
    ]
    for variant, item in summary["r5"].items():
        achievement = item["achievement"]
        choices = Counter(item["interaction_choices"])
        top_choice = choices.most_common(1)[0][0] if choices else "-"
        ci = achievement["ci95"]
        ci_text = "-" if ci is None else f"{percentage(ci[0])}–{percentage(ci[1])}"
        lines.append(
            f"| {variant} | {item['sessions']} | {percentage(achievement['rate'])} | "
            f"{percentage(item['next']['rate'])} | {ci_text} | {top_choice} | "
            f"{'達成' if item['minimum_sample_met'] else '不足'} |"
        )

    lines.extend([
        "",
        "## R9 根拠表示",
        "",
        "| 質問 | 正答/採点 | 正答率 | 95%区間 | 目標 | 判定 |",
        "| --- | ---: | ---: | --- | ---: | --- |",
    ])
    labels = {"action": "今日の行動", "reason": "提案理由", "missing": "不足データ", "change": "変更方法"}
    for key, item in summary["r9"].items():
        ci = item["ci95"]
        ci_text = "-" if ci is None else f"{percentage(ci[0])}–{percentage(ci[1])}"
        lines.append(
            f"| {labels[key]} | {item['correct']}/{item['scored']} | {percentage(item['rate'])} | "
            f"{ci_text} | {percentage(item['target'])} | {'達成' if item['target_met'] else '未達・未採点'} |"
        )

    lines.extend([
        "",
        "## ゲート",
        "",
        f"- R5各案5人以上: {'達成' if summary['gates']['r5_each_variant_at_least_5'] else '未達'}",
        f"- R9必須4項目が各5人以上: {'達成' if summary['gates']['r9_each_required_question_at_least_5'] else '未達'}",
        "- 自由回答本文はこの集計へ転載していません。原本JSONで別途定性分析してください。",
    ])
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", nargs="+", type=Path, help="Exported research JSON files")
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    args = parser.parse_args()

    summary = build_summary(load_sessions(args.inputs))
    markdown_text = markdown(summary)
    if args.json_output:
        args.json_output.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.markdown_output:
        args.markdown_output.write_text(markdown_text, encoding="utf-8")
    if not args.json_output and not args.markdown_output:
        print(markdown_text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
