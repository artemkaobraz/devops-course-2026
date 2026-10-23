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

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
