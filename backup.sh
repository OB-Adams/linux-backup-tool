#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR=""
DEST_DIR=""
RETENTION_DAYS=7
LOGFILE=""
QUIET=0
SCRIPT_NAME=$(basename "$0")

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} -s SOURCE_DIR -d DEST_DIR [options]

Required:
  -s DIR   Source directory to back up
  -d DIR   Destination directory to store archives in

Options:
  -r DAYS  Retention window in days; archives older than this are deleted
           (default: ${RETENTION_DAYS})
  -l FILE  Append a timestamped log line to FILE
  -q       Quiet: suppress the human-readable report, keep exit code + log
  -h       Show this help

Exit codes: 0=OK  1=WARNING  2=FAILURE  3=script error

Examples:
  ${SCRIPT_NAME} -s /etc -d /srv/backups
  ${SCRIPT_NAME} -s /var/www -d /srv/backups -r 14 -q -l /var/log/backup.log
EOF
}

while getopts ":s:d:r:l:qh" opt; do
    case "${opt}" in
        s) SOURCE_DIR=${OPTARG} ;;
        d) DEST_DIR=${OPTARG} ;;
        r) RETENTION_DAYS=${OPTARG} ;;
        l) LOGFILE=${OPTARG} ;;
        q) QUIET=1 ;;
        h) usage; exit 0 ;;
        \?) echo "Unknown option: -${OPTARG}" >&2; usage; exit 3 ;;
        :) echo "Option -${OPTARG} requires an argument" >&2; usage; exit 3 ;;
    esac
done

if [[  -z "${SOURCE_DIR}" || -z "${DEST_DIR}" ]]; then
	echo "Error: -s SOURCE_DIR and -d DEST_DIR are both required." >&2
    	usage
	exit 3
fi

if [[ ! -d "${SOURCE_DIR}" ]]; then
	echo "Error: source directory does not exist: ${SOURCE_DIR}" >&2
    	exit 3
fi

if ! command -v tar >/dev/null 2>&1; then
	echo "Error: 'tar' command not found."
	exit 3
fi

mkdir -p "${DEST_DIR}"

timestamp=$(date '+%Y%m%d-%H%M%S')
base_name=$(basename "${SOURCE_DIR}")
archive_name="${base_name}-${timestamp}.tar.gz"
archive_path="${DEST_DIR}/${archive_name}"

status="OK"
exit_code=0

if tar -czf "${archive_path}" -C "$(dirname "${SOURCE_DIR}")" "${base_name}" 2>/tmp/backup-tar-err.$$; then
	tar_ok=1
else
	tar_ok=0
fi

if [[ "${tar_ok}" -eq 0 ]]; then
    status="FAILURE"
    exit_code=2
fi

verify_ok=1
if [[ "${exit_code}" -lt 2 ]]; then
    if ! tar -tzf "${archive_path}" >/dev/null 2>&1; then
        verify_ok=0
        status="FAILURE"
        exit_code=2
    fi
fi

archive_size="n/a"
if [[ -f "${archive_path}" && "${verify_ok}" -eq 1 ]]; then
	archive_size=$(du -h "${archive_path}" | cut -f1)
fi

deleted_count=0
deleted_names=""

if [[ "${exit_code}" -lt 2 ]]; then
    while IFS= read -r -d '' old_archive; do
        if rm -f "${old_archive}"; then
            deleted_count=$(( deleted_count + 1 ))
            deleted_names="${deleted_names}    - $(basename "${old_archive}")"$'\n'
        else
            status="WARNING"
            [[ "${exit_code}" -lt 1 ]] && exit_code=1
        fi
    done < <(find "${DEST_DIR}" -maxdepth 1 -name "${base_name}-*.tar.gz" -mtime "+${RETENTION_DAYS}" -print0)
fi

remaining_count=$(find "${DEST_DIR}" -maxdepth 1 -name "${base_name}-*.tar.gz" | wc -l)

timestamp_log=$(date '+%Y-%m-%d %H:%M:%S')

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

if [[ "${exit_code}" -ge 2 ]]; then
    report=$(cat <<EOF
[${timestamp_log}] backup: ${status}
  Source: ${SOURCE_DIR}
  Failed to create/verify archive at: ${archive_path}
  tar error output:
$(sed 's/^/    /' /tmp/backup-tar-err.$$ 2>/dev/null || echo "    (no error output captured)")
EOF
)
else
    report=$(cat <<EOF
[${timestamp_log}] backup: ${status}
  Source : ${SOURCE_DIR}
  Archive: ${archive_name} (${archive_size})
  Retention: ${RETENTION_DAYS} days, ${remaining_count} archive(s) currently kept
$(if [[ "${deleted_count}" -gt 0 ]]; then
    echo "  Deleted ${deleted_count} archive(s) past retention:"
    printf '%s' "${deleted_names}"
else
    echo "  No archives past retention window."
fi)
EOF
)
fi

rm -f /tmp/backup-tar-err.$$

if [[ "${QUIET}" -eq 0 ]]; then
    echo "${report}"
fi

if [[ -n "${LOGFILE}" ]]; then
    {
        echo "${report}"
        echo
    } >> "${LOGFILE}"
fi

exit "${exit_code}"
