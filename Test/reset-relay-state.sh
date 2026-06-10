#!/bin/bash
#
# reset-relay-state.sh — 选择性清空 Relay 的本机配置与缓存,用于测试「初始启动」体验。
# 开发者本机自用辅助脚本,不进 app bundle。仅删除下方白名单内的固定路径,不接受任意路径参数。
#
set -euo pipefail

# ---------- HOME 健全性检查 ----------
# set -u 只能拦住 HOME 未定义;若 HOME 被定义为空串或 "/",
# 下方白名单会退化成 /Library/... 等系统路径,必须直接拒绝。
if [[ -z "${HOME:-}" || "${HOME}" != /* || "${HOME}" == "/" ]]; then
    echo "[错误] \$HOME 异常('${HOME:-}'),拒绝继续。" >&2
    exit 1
fi

# ---------- 固定路径(白名单,全部绝对路径) ----------
readonly BUNDLE_ID="cn.Teethe.Relay"
readonly APP_SUPPORT_DIR="${HOME}/Library/Application Support/${BUNDLE_ID}"
readonly CACHES_DIR="${HOME}/Library/Caches/${BUNDLE_ID}"
readonly SAVED_STATE_DIR="${HOME}/Library/Saved Application State/${BUNDLE_ID}.savedState"
readonly HTTP_STORAGES_DIR="${HOME}/Library/HTTPStorages/${BUNDLE_ID}"

# ---------- 选项开关 ----------
DO_CONFIG=0
DO_DEFAULTS=0
DO_CACHES=0
DO_SAVED_STATE=0
DO_TCC=0
DRY_RUN=0

# ---------- 汇总记录 ----------
SUMMARY=()

usage() {
    cat <<EOF
用法: $(basename "$0") [选项...]

选择性清空 Relay (${BUNDLE_ID}) 的本机状态,用于测试初始启动体验。
无选项时仅打印本说明并退出,不做任何删除。

选项:
  --config       删除配置 JSON 目录:
                   ${APP_SUPPORT_DIR}
  --defaults     删除 UserDefaults 域 ${BUNDLE_ID}
                   (注意: KeyboardShortcuts 包录制的快捷键也存在该域,
                    键形如 KeyboardShortcuts_<UUID>,会被一并清掉)
  --caches       删除缓存与 HTTPStorages(如存在):
                   ${CACHES_DIR}
                   ${HTTP_STORAGES_DIR}
  --saved-state  删除窗口状态恢复数据(如存在):
                   ${SAVED_STATE_DIR}
  --tcc          重置 Accessibility 权限授权(TCC):
                   tccutil reset Accessibility ${BUNDLE_ID}
                   (Relay 的「最小化目标窗口」功能按需申请 Accessibility,
                    重置后才能测到完整的首启权限弹窗流程)
  --all          以上全部
  --dry-run      只打印将执行的操作,不实际执行
  -h, --help     显示本说明

提示: Login item(Launch at login, SMAppService)没有干净的命令行重置方式,
本脚本不处理。若开启过 Launch at login,请先在 Relay 内关掉,
或在「系统设置 > 通用 > 登录项」中移除,再做首启测试。
EOF
}

# 执行(或在 dry-run 下仅打印)一条命令
run() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "  [dry-run] $*"
    else
        "$@"
    fi
}

# 删除一个白名单目录:存在则删,不存在打印 skip
remove_dir() {
    local label="$1"
    local dir="$2"
    # 安全检查:变量非空、位于用户家目录 Library 下、且确属本 app 的路径,才允许 rm -rf
    if [[ -z "${dir}" || "${dir}" != "${HOME}/Library/"* || "${dir}" != *"${BUNDLE_ID}"* ]]; then
        echo "[错误] ${label}: 路径异常,拒绝删除: '${dir}'" >&2
        exit 1
    fi
    if [[ -e "${dir}" ]]; then
        echo "[删除] ${label}: ${dir}"
        run rm -rf "${dir}"
        SUMMARY+=("已删除 ${label}: ${dir}")
    else
        echo "[跳过] ${label} 不存在: ${dir}"
        SUMMARY+=("跳过 ${label}(不存在)")
    fi
}

# ---------- 解析参数 ----------
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

for arg in "$@"; do
    case "${arg}" in
        --config)      DO_CONFIG=1 ;;
        --defaults)    DO_DEFAULTS=1 ;;
        --caches)      DO_CACHES=1 ;;
        --saved-state) DO_SAVED_STATE=1 ;;
        --tcc)         DO_TCC=1 ;;
        --all)         DO_CONFIG=1; DO_DEFAULTS=1; DO_CACHES=1; DO_SAVED_STATE=1; DO_TCC=1 ;;
        --dry-run)     DRY_RUN=1 ;;
        -h|--help)     usage; exit 0 ;;
        *)
            echo "[错误] 未知选项: ${arg}" >&2
            echo "使用 --help 查看用法。" >&2
            exit 1
            ;;
    esac
done

if [[ $((DO_CONFIG + DO_DEFAULTS + DO_CACHES + DO_SAVED_STATE + DO_TCC)) -eq 0 ]]; then
    echo "[提示] 只指定了 --dry-run,没有选择任何清理项;无事可做。"
    usage
    exit 0
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "===== DRY RUN 模式:以下操作只打印,不实际执行 ====="
fi

# ---------- 先确保 Relay 已退出 ----------
# AppModel 是防抖保存(~400ms),app 退出时可能把内存配置重新写回磁盘,
# 因此必须先退出 Relay 再删文件。
if pgrep -x Relay >/dev/null 2>&1; then
    echo "[提示] Relay 正在运行,先请求退出…"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "  [dry-run] osascript -e 'quit app \"Relay\"'(必要时 pkill -x Relay)"
        SUMMARY+=("将退出运行中的 Relay(dry-run 未执行)")
    else
        osascript -e 'quit app "Relay"' >/dev/null 2>&1 || true
        # 给几秒优雅退出
        for _ in 1 2 3 4 5; do
            if ! pgrep -x Relay >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
        if pgrep -x Relay >/dev/null 2>&1; then
            echo "[提示] Relay 未在限时内退出,强制结束(pkill)…"
            pkill -x Relay || true
            sleep 1
        fi
        if pgrep -x Relay >/dev/null 2>&1; then
            echo "[错误] 无法退出 Relay,中止以免配置被回写。" >&2
            exit 1
        fi
        echo "[完成] Relay 已退出。"
        SUMMARY+=("已退出运行中的 Relay")
    fi
else
    echo "[跳过] Relay 未在运行。"
fi

# ---------- 按选项执行 ----------
if [[ "${DO_CONFIG}" -eq 1 ]]; then
    remove_dir "配置目录 (config.json)" "${APP_SUPPORT_DIR}"
fi

if [[ "${DO_DEFAULTS}" -eq 1 ]]; then
    if defaults read "${BUNDLE_ID}" >/dev/null 2>&1; then
        echo "[删除] UserDefaults 域: ${BUNDLE_ID}"
        echo "       (含 KeyboardShortcuts 包录制的快捷键缓存 KeyboardShortcuts_<UUID>,一并清除)"
        run defaults delete "${BUNDLE_ID}"
        SUMMARY+=("已删除 UserDefaults 域 ${BUNDLE_ID}(含 KeyboardShortcuts 快捷键缓存)")
    else
        echo "[跳过] UserDefaults 域不存在: ${BUNDLE_ID}"
        SUMMARY+=("跳过 UserDefaults(域不存在)")
    fi
fi

if [[ "${DO_CACHES}" -eq 1 ]]; then
    remove_dir "缓存目录" "${CACHES_DIR}"
    remove_dir "HTTPStorages" "${HTTP_STORAGES_DIR}"
fi

if [[ "${DO_SAVED_STATE}" -eq 1 ]]; then
    remove_dir "Saved Application State" "${SAVED_STATE_DIR}"
fi

if [[ "${DO_TCC}" -eq 1 ]]; then
    echo "[重置] Accessibility 权限 (TCC): ${BUNDLE_ID}"
    run tccutil reset Accessibility "${BUNDLE_ID}"
    SUMMARY+=("已重置 Accessibility 权限 (tccutil)")
fi

# ---------- 汇总 ----------
echo ""
echo "===== 汇总 ====="
# macOS 自带 bash 3.2 下,set -u + 空数组展开会报 unbound variable;用 ${arr[@]+...} 防护
for line in ${SUMMARY[@]+"${SUMMARY[@]}"}; do
    echo "- ${line}"
done
if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "(DRY RUN:以上均未实际执行)"
fi
echo ""
echo "[提醒] 若开启过 Launch at login(SMAppService 登录项),本脚本未处理;"
echo "       请在 Relay 内关闭,或到「系统设置 > 通用 > 登录项」移除后再测首启。"
