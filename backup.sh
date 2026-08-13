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
