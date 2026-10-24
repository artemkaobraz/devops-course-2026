#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf ' [OK] %s\n' "$desc"
        ((PASS += 1))
    else
        printf " [FAIL] %s (ожидалось: '%s', получено: '%s')\n" "$desc" "$expected" "$actual"
        ((FAIL += 1))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

if ! sshd_config=$(sudo sshd -T); then
    echo '[FAIL] Не удалось получить действующую конфигурацию SSH' >&2
    exit 1
fi

ssh_option() {
    awk -v key="$1" '$1 == key { print $2; exit }' <<< "$sshd_config"
}

echo '[1] Служба SSH'
check 'Вход от имени root запрещён' 'no' "$(ssh_option permitrootlogin)"
check 'Парольная аутентификация отключена' 'no' "$(ssh_option passwordauthentication)"

ssh_ports=$(awk '$1 == "port" { print $2 }' <<< "$sshd_config")
port_result='не 22'
if [[ -z "$ssh_ports" ]]; then
    port_result='отсутствует'
else
    while IFS= read -r ssh_port; do
        if [[ ! "$ssh_port" =~ ^[0-9]+$ || "$ssh_port" == 22 ]]; then
            port_result="$ssh_port"
            break
        fi
    done <<< "$ssh_ports"
fi
check 'Порт SSH отличается от 22' 'не 22' "$port_result"
check 'MaxAuthTries равен 3' '3' "$(ssh_option maxauthtries)"

if ! ufw_status=$(sudo ufw status verbose); then
    echo '[FAIL] Не удалось получить состояние межсетевого экрана' >&2
    exit 1
fi

echo '[2] Межсетевой экран'
check 'Межсетевой экран активен' 'active' "$(awk '/^Status:/ { print $2; exit }' <<< "$ufw_status")"
check 'Политика входящего трафика — deny' 'deny' "$(awk '/^Default:/ { print $2; exit }' <<< "$ufw_status")"

echo '[3] Учётные записи'
awk -F: '$3 >= 1000 && $3 < 65534 { printf " %s (uid=%s)\n", $1, $3 }' /etc/passwd

echo '[4] Веб-сервер и сертификат'
if sudo systemctl is-active --quiet nginx; then
    nginx_status='active'
else
    nginx_status='inactive'
fi
check 'Nginx активен' 'active' "$nginx_status"

if sudo nginx -t >/dev/null 2>&1; then
    nginx_config='valid'
else
    nginx_config='invalid'
fi
check 'Конфигурация Nginx корректна' 'valid' "$nginx_config"

cert_checkend_seconds=${CERT_CHECKEND_SECONDS:-2592000}
if [[ ! "$cert_checkend_seconds" =~ ^[0-9]+$ ]]; then
    echo 'CERT_CHECKEND_SECONDS должен быть неотрицательным числом секунд' >&2
    exit 2
fi
if sudo openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend "$cert_checkend_seconds" >/dev/null 2>&1; then
    cert_status='valid'
else
    cert_status='expired or expiring'
fi
check 'Сертификат действителен не менее 30 дней' 'valid' "$cert_status"

if sudo test -d /var/www/devops-site && \
    world_writable=$(sudo find /var/www/devops-site -type f -perm /0002 -print -quit); then
    if [[ -z "$world_writable" ]]; then
        files_status='safe'
    else
        files_status="$world_writable"
    fi
else
    files_status='site unavailable'
fi
check 'В сайте нет файлов с правом записи для всех' 'safe' "$files_status"

key_mode=$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null) || key_mode='unavailable'
check 'Права закрытого ключа — 600' '600' "$key_mode"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
