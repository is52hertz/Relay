#!/bin/bash
#
# reset-relay-state.sh — 选择性清空 / 备份 / 恢复 Relay 的本机配置与缓存,用于测试「初始启动」体验。
# 开发者本机自用辅助脚本,不进 app bundle。仅操作下方白名单内的固定路径,不接受任意路径参数。
#
# 三种用法:
#   1) 直接清空(默认):  ./reset-relay-state.sh --config --defaults ...
#   2) 备份式清空:        ./reset-relay-state.sh --backup --all      (删除改为 mv 进快照)
#   3) 从备份恢复:        ./reset-relay-state.sh --restore [latest|<时间戳>]
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
# UserDefaults 域落盘的 plist;cfprefsd 缓存下 `defaults read` 可能漏判,故用文件存在作为兜底判据。
readonly PREFS_PLIST="${HOME}/Library/Preferences/${BUNDLE_ID}.plist"

# 备份根目录:位于本脚本所在目录(Test/)下的 backups/,已在 .gitignore 中忽略。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly BACKUP_ROOT="${SCRIPT_DIR}/backups"
readonly TS="$(date +%Y%m%d-%H%M%S)"
# reset+backup 模式下写入的快照目录(restore 模式会被改写为所选快照)。
SNAPSHOT="${BACKUP_ROOT}/${TS}"
SNAPSHOT_CREATED=0

# ---------- 选项开关 ----------
MODE="reset"          # reset | restore
RESTORE_ID=""         # restore 模式下的快照 id(latest / 时间戳),空=交互选择
DO_CONFIG=0
DO_DEFAULTS=0
DO_CACHES=0
DO_SAVED_STATE=0
DO_TCC=0
DO_BACKUP=0
DRY_RUN=0

# ---------- 汇总记录 ----------
SUMMARY=()

usage() {
    cat <<EOF
用法: $(basename "$0") [选项...]

选择性清空 / 备份 / 恢复 Relay (${BUNDLE_ID}) 的本机状态,用于测试初始启动体验。
无选项时仅打印本说明并退出,不做任何改动。

清理项(reset 模式):
  --config       配置 JSON 目录:
                   ${APP_SUPPORT_DIR}
  --defaults     UserDefaults 域 ${BUNDLE_ID}
                   (注意: KeyboardShortcuts 包录制的快捷键也存在该域,
                    键形如 KeyboardShortcuts_<UUID>,会被一并清掉)
  --caches       缓存与 HTTPStorages(如存在):
                   ${CACHES_DIR}
                   ${HTTP_STORAGES_DIR}
  --saved-state  窗口状态恢复数据(如存在):
                   ${SAVED_STATE_DIR}
  --tcc          重置 Accessibility 权限授权(TCC):
                   tccutil reset Accessibility ${BUNDLE_ID}
                   (无法备份/恢复;--backup 下仍只是 reset)
  --all          以上全部

模式 / 修饰:
  --backup       不删除,改为 mv 进快照目录(可事后 --restore 还原):
                   ${BACKUP_ROOT}/<时间戳>/
                   与上面的清理项组合使用,例: --backup --all
  --restore [id] 从备份恢复(还原快照里包含的全部项:配置 + 快捷键 + 缓存等)。
                   无 id     → 交互列出可用快照供选择
                   latest    → 最新一个快照
                   <时间戳>  → 指定快照目录名
                   与清理项 / --backup 互斥。恢复会覆盖当前状态。
  --dry-run      只打印将执行的操作,不实际执行(对 reset / backup / restore 均生效)
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

# ---------- 确保 Relay 已退出(reset 与 restore 共用) ----------
# AppModel 是防抖保存(~400ms),app 运行时可能把内存配置回写磁盘,
# 因此必须先退出 Relay 再删/移/恢复文件。
ensure_relay_quit() {
    if ! pgrep -x Relay >/dev/null 2>&1; then
        echo "[跳过] Relay 未在运行。"
        return
    fi
    echo "[提示] Relay 正在运行,先请求退出…"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "  [dry-run] osascript -e 'quit app \"Relay\"'(必要时 pkill -x Relay)"
        SUMMARY+=("将退出运行中的 Relay(dry-run 未执行)")
        return
    fi
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
}

# ---------- 备份辅助 ----------
# 懒创建快照目录:仅当确有内容要备份时才建,避免留空目录。
ensure_snapshot_dir() {
    if [[ "${SNAPSHOT_CREATED}" -eq 1 ]]; then
        return
    fi
    echo "[备份] 创建快照目录: ${SNAPSHOT}"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "  [dry-run] mkdir -p ${SNAPSHOT}"
    else
        mkdir -p "${SNAPSHOT}"
    fi
    SNAPSHOT_CREATED=1
}

# 往快照 manifest 追加一行: key|type|original_path (路径不含 |,可安全用作分隔符)
manifest_add() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        return
    fi
    echo "$1" >> "${SNAPSHOT}/manifest.txt"
}

# 删除 / 备份一个白名单目录:
#   存在 + DO_BACKUP=1 → mv 进快照;存在 + 普通 → rm -rf;不存在 → skip。
# 三段白名单校验(变量非空、位于用户家目录 Library 下、确属本 app)后才动手。
remove_dir() {
    local label="$1"
    local dir="$2"
    local key="$3"   # 在快照内的子目录名
    if [[ -z "${dir}" || "${dir}" != "${HOME}/Library/"* || "${dir}" != *"${BUNDLE_ID}"* ]]; then
        echo "[错误] ${label}: 路径异常,拒绝操作: '${dir}'" >&2
        exit 1
    fi
    if [[ ! -e "${dir}" ]]; then
        echo "[跳过] ${label} 不存在: ${dir}"
        SUMMARY+=("跳过 ${label}(不存在)")
        return
    fi
    if [[ "${DO_BACKUP}" -eq 1 ]]; then
        ensure_snapshot_dir
        echo "[备份] ${label}: ${dir} → ${SNAPSHOT}/${key}"
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            echo "  [dry-run] mv \"${dir}\" \"${SNAPSHOT}/${key}\""
        else
            mv "${dir}" "${SNAPSHOT}/${key}"
        fi
        manifest_add "${key}|dir|${dir}"
        SUMMARY+=("已备份 ${label} → ${SNAPSHOT}/${key}")
    else
        echo "[删除] ${label}: ${dir}"
        run rm -rf "${dir}"
        SUMMARY+=("已删除 ${label}: ${dir}")
    fi
}

# UserDefaults 域:删除 / 备份+删除。域存在判据 = `defaults read` 成功 或 plist 文件存在。
handle_defaults() {
    if ! defaults read "${BUNDLE_ID}" >/dev/null 2>&1 && [[ ! -f "${PREFS_PLIST}" ]]; then
        echo "[跳过] UserDefaults 域不存在: ${BUNDLE_ID}"
        SUMMARY+=("跳过 UserDefaults(域不存在)")
        return
    fi
    if [[ "${DO_BACKUP}" -eq 1 ]]; then
        ensure_snapshot_dir
        echo "[备份] UserDefaults 域 → ${SNAPSHOT}/userdefaults.plist (含 KeyboardShortcuts_<UUID>)"
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            echo "  [dry-run] defaults export ${BUNDLE_ID} ${SNAPSHOT}/userdefaults.plist"
        else
            # 优先 defaults export(cfprefsd 感知);导出为空则回退直接 cp plist 文件。
            defaults export "${BUNDLE_ID}" "${SNAPSHOT}/userdefaults.plist" 2>/dev/null || true
            if [[ ! -s "${SNAPSHOT}/userdefaults.plist" && -f "${PREFS_PLIST}" ]]; then
                cp "${PREFS_PLIST}" "${SNAPSHOT}/userdefaults.plist"
            fi
        fi
        manifest_add "userdefaults|defaults|${BUNDLE_ID}"
        echo "[删除] UserDefaults 域: ${BUNDLE_ID}"
        clear_defaults
        SUMMARY+=("已备份并清除 UserDefaults 域 ${BUNDLE_ID}(含快捷键)")
    else
        echo "[删除] UserDefaults 域: ${BUNDLE_ID}"
        echo "       (含 KeyboardShortcuts 包录制的快捷键缓存 KeyboardShortcuts_<UUID>,一并清除)"
        clear_defaults
        SUMMARY+=("已删除 UserDefaults 域 ${BUNDLE_ID}(含 KeyboardShortcuts 快捷键缓存)")
    fi
}

# 清除 UserDefaults 域 + 删掉残留 plist 文件(dry-run 感知、对 delete 失败容忍)。
clear_defaults() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "  [dry-run] defaults delete ${BUNDLE_ID}"
        echo "  [dry-run] rm -f ${PREFS_PLIST}"
        return
    fi
    defaults delete "${BUNDLE_ID}" >/dev/null 2>&1 || true
    rm -f "${PREFS_PLIST}"
}

# ---------- 恢复辅助 ----------
# 把快照里的目录 cp 回 live 路径(cp 非 mv,保持快照可重复恢复)。对目标做白名单校验。
restore_dir() {
    local label="$1"
    local key="$2"
    local target="$3"
    local src="${SNAPSHOT}/${key}"
    if [[ -z "${target}" || "${target}" != "${HOME}/Library/"* || "${target}" != *"${BUNDLE_ID}"* ]]; then
        echo "[错误] ${label}: 目标路径异常,拒绝恢复: '${target}'" >&2
        exit 1
    fi
    if [[ ! -e "${src}" ]]; then
        echo "[跳过] ${label}: 快照内缺少 ${src}"
        SUMMARY+=("跳过 ${label}(快照内缺失)")
        return
    fi
    echo "[恢复] ${label}: ${src} → ${target}"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "  [dry-run] rm -rf \"${target}\" && mkdir -p \"$(dirname "${target}")\" && cp -R \"${src}\" \"${target}\""
    else
        rm -rf "${target}"
        mkdir -p "$(dirname "${target}")"
        cp -R "${src}" "${target}"
    fi
    SUMMARY+=("已恢复 ${label} → ${target}")
}

# 把快照里的 UserDefaults plist 导入回域(cfprefsd 感知,下次启动生效)。
restore_defaults() {
    local plist="${SNAPSHOT}/userdefaults.plist"
    if [[ ! -f "${plist}" ]]; then
        echo "[跳过] 快照内缺少 userdefaults.plist"
        SUMMARY+=("跳过 UserDefaults(快照内缺失)")
        return
    fi
    echo "[恢复] UserDefaults 域: ${plist} → ${BUNDLE_ID}"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "  [dry-run] defaults import ${BUNDLE_ID} ${plist}"
    else
        defaults import "${BUNDLE_ID}" "${plist}"
    fi
    SUMMARY+=("已恢复 UserDefaults 域 ${BUNDLE_ID}(含快捷键)")
}

# 列出所有快照目录名到全局数组 SNAPS(按时间戳字典序升序)。
SNAPS=()
collect_snapshots() {
    SNAPS=()
    if [[ ! -d "${BACKUP_ROOT}" ]]; then
        return
    fi
    local d
    while IFS= read -r d; do
        SNAPS+=("$(basename "${d}")")
    done < <(find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d | sort)
}

# 执行恢复流程。
do_restore() {
    collect_snapshots
    if [[ ${#SNAPS[@]} -eq 0 ]]; then
        echo "[错误] 没有可用备份: ${BACKUP_ROOT}" >&2
        exit 1
    fi

    local chosen=""
    if [[ -n "${RESTORE_ID}" ]]; then
        if [[ "${RESTORE_ID}" == "latest" ]]; then
            chosen="${SNAPS[$(( ${#SNAPS[@]} - 1 ))]}"
        else
            # 防路径穿越:拒绝含 / 或 ..
            if [[ "${RESTORE_ID}" == *"/"* || "${RESTORE_ID}" == *".."* ]]; then
                echo "[错误] 非法快照 id: ${RESTORE_ID}" >&2
                exit 1
            fi
            if [[ ! -d "${BACKUP_ROOT}/${RESTORE_ID}" ]]; then
                echo "[错误] 快照不存在: ${RESTORE_ID}" >&2
                exit 1
            fi
            chosen="${RESTORE_ID}"
        fi
    else
        echo "可用备份快照:"
        local i=1 s summary
        for s in "${SNAPS[@]}"; do
            summary=""
            if [[ -f "${BACKUP_ROOT}/${s}/manifest.txt" ]]; then
                summary="$(cut -d'|' -f1 "${BACKUP_ROOT}/${s}/manifest.txt" 2>/dev/null | paste -sd, -)"
            fi
            echo "  [${i}] ${s}   (${summary})"
            i=$(( i + 1 ))
        done
        printf "选择要恢复的快照编号 (1-%d): " "${#SNAPS[@]}"
        local choice
        read -r choice
        if [[ ! "${choice}" =~ ^[0-9]+$ ]] || [[ "${choice}" -lt 1 ]] || [[ "${choice}" -gt ${#SNAPS[@]} ]]; then
            echo "[错误] 无效选择: ${choice}" >&2
            exit 1
        fi
        chosen="${SNAPS[$(( choice - 1 ))]}"
    fi

    SNAPSHOT="${BACKUP_ROOT}/${chosen}"
    if [[ ! -f "${SNAPSHOT}/manifest.txt" ]]; then
        echo "[错误] 快照缺少 manifest.txt,无法恢复: ${SNAPSHOT}" >&2
        exit 1
    fi

    echo ""
    echo "[警告] 即将用快照 ${chosen} 覆盖当前 Relay 的配置/快捷键/缓存等当前状态(不可撤销)。"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "===== DRY RUN 模式:以下操作只打印,不实际执行 ====="
    fi

    ensure_relay_quit

    # 逐项恢复(按 manifest 记录的内容)。
    local key type orig
    while IFS='|' read -r key type orig; do
        [[ -z "${key}" ]] && continue
        case "${type}" in
            dir)      restore_dir "${key}" "${key}" "${orig}" ;;
            defaults) restore_defaults ;;
            *)        echo "[跳过] 未知 manifest 条目: ${key}|${type}|${orig}" ;;
        esac
    done < "${SNAPSHOT}/manifest.txt"
}

# ---------- 解析参数 ----------
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)      DO_CONFIG=1 ;;
        --defaults)    DO_DEFAULTS=1 ;;
        --caches)      DO_CACHES=1 ;;
        --saved-state) DO_SAVED_STATE=1 ;;
        --tcc)         DO_TCC=1 ;;
        --all)         DO_CONFIG=1; DO_DEFAULTS=1; DO_CACHES=1; DO_SAVED_STATE=1; DO_TCC=1 ;;
        --backup)      DO_BACKUP=1 ;;
        --dry-run)     DRY_RUN=1 ;;
        --restore)
            MODE="restore"
            # 可选:下一个 token 若不以 -- 开头,视作快照 id(latest / 时间戳)。
            if [[ $# -ge 2 && "$2" != --* ]]; then
                RESTORE_ID="$2"
                shift
            fi
            ;;
        -h|--help)     usage; exit 0 ;;
        *)
            echo "[错误] 未知选项: $1" >&2
            echo "使用 --help 查看用法。" >&2
            exit 1
            ;;
    esac
    shift
done

# ---------- restore 模式 ----------
if [[ "${MODE}" == "restore" ]]; then
    # 与清理项 / --backup 互斥
    if [[ $((DO_CONFIG + DO_DEFAULTS + DO_CACHES + DO_SAVED_STATE + DO_TCC + DO_BACKUP)) -ne 0 ]]; then
        echo "[错误] --restore 不能与清理项或 --backup 同时使用。" >&2
        exit 1
    fi
    do_restore

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
    echo "[提醒] TCC 权限与 Login item 不在恢复范围;如需可分别用 --tcc 或系统设置处理。"
    exit 0
fi

# ---------- reset / backup 模式 ----------
if [[ $((DO_CONFIG + DO_DEFAULTS + DO_CACHES + DO_SAVED_STATE + DO_TCC)) -eq 0 ]]; then
    echo "[提示] 未选择任何清理项;无事可做。"
    usage
    exit 0
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "===== DRY RUN 模式:以下操作只打印,不实际执行 ====="
fi
if [[ "${DO_BACKUP}" -eq 1 ]]; then
    echo "===== BACKUP 模式:删除改为 mv 进 ${SNAPSHOT}/ ====="
fi

ensure_relay_quit

# ---------- 按选项执行 ----------
if [[ "${DO_CONFIG}" -eq 1 ]]; then
    remove_dir "配置目录 (config.json)" "${APP_SUPPORT_DIR}" "config"
fi

if [[ "${DO_DEFAULTS}" -eq 1 ]]; then
    handle_defaults
fi

if [[ "${DO_CACHES}" -eq 1 ]]; then
    remove_dir "缓存目录" "${CACHES_DIR}" "Caches"
    remove_dir "HTTPStorages" "${HTTP_STORAGES_DIR}" "HTTPStorages"
fi

if [[ "${DO_SAVED_STATE}" -eq 1 ]]; then
    remove_dir "Saved Application State" "${SAVED_STATE_DIR}" "SavedState"
fi

if [[ "${DO_TCC}" -eq 1 ]]; then
    if [[ "${DO_BACKUP}" -eq 1 ]]; then
        echo "[提示] TCC(Accessibility 授权)无法备份,--backup 下仍只是 reset。"
    fi
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
if [[ "${DO_BACKUP}" -eq 1 && "${SNAPSHOT_CREATED}" -eq 1 ]]; then
    echo ""
    echo "[备份完成] 快照: ${SNAPSHOT}"
    echo "           恢复用: $(basename "$0") --restore $(basename "${SNAPSHOT}")"
fi
if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "(DRY RUN:以上均未实际执行)"
fi
echo ""
echo "[提醒] 若开启过 Launch at login(SMAppService 登录项),本脚本未处理;"
echo "       请在 Relay 内关闭,或到「系统设置 > 通用 > 登录项」移除后再测首启。"
