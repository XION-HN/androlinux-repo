#!/usr/bin/env bash
# 查询 androlinux 私有仓库的 GitHub Actions 状态
#
# 用法:
#   ./scripts/ci-status.sh                # 列出最近 5 次 run 概要
#   ./scripts/ci-status.sh latest         # 同上 + 展示最新 run 的 job/artifact
#   ./scripts/ci-status.sh <run-id>       # 查指定 run 的 job/artifact/失败日志
#   ./scripts/ci-status.sh artifacts      # 仅列出最新 run 的 artifact 下载链接
#
# 鉴权（私有仓库必需，三选一）:
#   1) export GH_TOKEN=ghp_xxx            # PAT（需 repo + actions:read）
#   2) export GITHUB_TOKEN=ghp_xxx        # 同上，CI 常用变量名
#   3) gh auth login                      # 交互式登录，凭证存 ~/.config/gh/
#
# 无 token 时脚本会给出明确提示并退出，不会盲目撞 API 限流。
set -euo pipefail

REPO="XION-HN/androlinux"

# 统一 token 入口（GH_TOKEN 优先，与 gh CLI 一致）
if [ -z "${GH_TOKEN:-}" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
    export GH_TOKEN="$GITHUB_TOKEN"
fi

# 检查 gh CLI 是否可用
if ! command -v gh >/dev/null 2>&1; then
    echo "错误: 未安装 gh CLI。" >&2
    echo "  macOS:  brew install gh" >&2
    echo "  Ubuntu: sudo apt install gh" >&2
    echo "  其他:   https://cli.github.com/" >&2
    exit 1
fi

# 检查鉴权状态（gh auth status 在无 token 时返回非 0）
if [ -z "${GH_TOKEN:-}" ]; then
    if ! gh auth status >/dev/null 2>&1; then
        echo "错误: 未登录 GitHub，无法访问私有仓库 $REPO" >&2
        echo "" >&2
        echo "解决方法（三选一）:" >&2
        echo "  1) export GH_TOKEN=ghp_xxx  &&  ./scripts/ci-status.sh" >&2
        echo "     PAT 需勾选 repo + actions:read 权限" >&2
        echo "     创建: https://github.com/settings/tokens" >&2
        echo "  2) gh auth login  # 交互式登录，凭证持久化到 ~/.config/gh/" >&2
        echo "  3) 浏览器手动查看: https://github.com/$REPO/actions" >&2
        exit 2
    fi
fi

# 限定查询分支（默认 main，可通过 BRANCH 环境变量改）
BRANCH="${BRANCH:-main}"

# -------------------------------------------------------------------
# 命令分发
# -------------------------------------------------------------------
cmd="${1:-latest}"

list_runs() {
    local limit="${1:-5}"
    echo "=== $REPO 最近 $limit 次 run（branch=$BRANCH）==="
    # --json 输出稳定结构，避免 jq 依赖（用 gh 自带 template）
    gh run list \
        --repo "$REPO" \
        --branch "$BRANCH" \
        --limit "$limit" \
        --json databaseId,status,conclusion,event,headSha,displayTitle,createdAt \
        --template '{{range .}}'\
'{{.databaseId}}	{{.status}}	{{.conclusion}}	{{.event}}	{{.createdAt}}	{{slice .headSha 0 7}}	{{.displayTitle}}
{{end}}' \
        | awk -F'\t' '{
            # 对齐显示：id 状态 结论 事件 时间 sha 标题
            printf "%-12s %-10s %-12s %-18s %-22s %s  %s\n", $1, $2, $3, $4, $5, $6, $7
        }'
    echo ""
    echo "图例: status=in_progress/queued/completed  conclusion=success/failure/cancelled"
}

show_run_detail() {
    local run_id="$1"
    echo "=== Run $run_id 详情 ==="
    gh run view "$run_id" --repo "$REPO" || true
    echo ""

    echo "=== Jobs ==="
    gh run view "$run_id" --repo "$REPO" --json jobs \
        --template '{{range .jobs}}{{.name}}	{{.status}}	{{.conclusion}}	{{.url}}
{{end}}' \
        | awk -F'\t' '{ printf "  %-30s %-12s %-12s %s\n", $1, $2, $3, $4 }'
    echo ""

    echo "=== Artifacts ==="
    local artifacts
    artifacts=$(gh run view "$run_id" --repo "$REPO" --json artifacts \
        --template '{{range .artifacts}}{{.name}}	{{.sizeInBytes}}	{{.url}}
{{end}}' 2>/dev/null || true)
    if [ -z "$artifacts" ]; then
        echo "  (无 artifact 或 run 尚未产出)"
    else
        echo "$artifacts" | awk -F'\t' '{
            size=$2
            unit="B"
            if (size > 1073741824) { size/=1073741824; unit="GB" }
            else if (size > 1048576) { size/=1048576; unit="MB" }
            else if (size > 1024) { size/=1024; unit="KB" }
            printf "  %-30s %8.1f %s  %s\n", $1, size, unit, $3
        }'
        echo ""
        echo "下载: gh run download $run_id --repo $REPO --name <artifact-name> -D ./dist/"
    fi
}

show_failed_logs() {
    local run_id="$1"
    echo ""
    echo "=== 失败 job 日志（末尾 80 行）==="
    # --log-failed 只输出失败 step 的日志；体量大时用户可自行加 | tail
    gh run view "$run_id" --repo "$REPO" --log-failed 2>&1 | tail -80 || \
        echo "  (无失败日志或 run 仍在进行)"
}

list_artifacts_only() {
    local latest_id
    latest_id=$(gh run list --repo "$REPO" --branch "$BRANCH" --limit 1 \
        --status completed --json databaseId --template '{{range .}}{{.databaseId}}{{end}}')
    [ -z "$latest_id" ] && { echo "无已完成的 run"; exit 0; }
    echo "最新完成 run: $latest_id"
    show_run_detail "$latest_id"
}

case "$cmd" in
    latest)
        list_runs 5
        latest_id=$(gh run list --repo "$REPO" --branch "$BRANCH" --limit 1 \
            --json databaseId --template '{{range .}}{{.databaseId}}{{end}}')
        if [ -n "$latest_id" ]; then
            show_run_detail "$latest_id"
            # 失败时自动 dump 日志
            conclusion=$(gh run view "$latest_id" --repo "$REPO" --json conclusion \
                --template '{{.conclusion}}')
            if [ "$conclusion" = "failure" ] || [ "$conclusion" = "cancelled" ]; then
                show_failed_logs "$latest_id"
            fi
        fi
        ;;
    artifacts)
        list_artifacts_only
        ;;
    ''|*[!0-9]*)
        echo "未知命令: $cmd" >&2
        echo "用法: $0 [latest|artifacts|<run-id>]" >&2
        exit 1
        ;;
    *)
        # 数字 → 视为 run-id
        show_run_detail "$cmd"
        show_failed_logs "$cmd"
        ;;
esac
