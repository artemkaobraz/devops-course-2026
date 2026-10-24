#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Использование: %s [--dry-run]\n' "${0##*/}" >&2
    exit 2
}

dry_run=false
case "${1-}" in
    '') ;;
    --dry-run) dry_run=true ;;
    *) usage ;;
esac
[[ $# -le 1 ]] || usage

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
site_dir="$repo_root/site"
remote='devops:/var/www/devops-site/'
url='https://devops.local/'

if [[ ! -f "$site_dir/index.html" ]]; then
    echo 'Ошибка: site/index.html не найден.' >&2
    exit 1
fi

if [[ -n "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ]]; then
    echo 'Ошибка: в репозитории есть staged, unstaged или untracked изменения.' >&2
    exit 1
fi

revision=$(git -C "$repo_root" rev-parse --short HEAD)
printf 'Ревизия: %s\n' "$revision"
printf 'Источник: %s/\nНазначение: %s\nПроверка: %s\n' "$site_dir" "$remote" "$url"

rsync_options=(-avz --delete --chmod=D755,F644)
if "$dry_run"; then
    rsync_options+=(--dry-run)
fi

rsync "${rsync_options[@]}" \
    -e 'ssh -o BatchMode=yes -o ConnectTimeout=5' \
    "$site_dir/" "$remote"

if "$dry_run"; then
    echo 'Пробный запуск завершён; файлы на сервере не изменены.'
    exit 0
fi

if ! curl --cacert "$HOME/devops.crt" -fsS "$url"; then
    echo 'Ошибка: после синхронизации HTTPS-ресурс недоступен.' >&2
    exit 1
fi
printf '\nДеплой ревизии %s завершён.\n' "$revision"
