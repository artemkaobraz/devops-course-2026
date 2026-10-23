# Конфигурация виртуальной машины devops-vm

Конфигурация проверена 23.10.2026. Хост — macOS на Apple Silicon, VirtualBox 7.2.8; гостевая система — Ubuntu Server 24.04.5 LTS **arm64** без графической подсистемы. Образ arm64 выбран из-за архитектуры хоста.

## 1. Параметры машины

| Параметр | Значение |
| --- | --- |
| Имя | `devops-vm` |
| ОЗУ | 2048 МБ |
| Процессоры | 2 |
| Диск | 25 ГБ, VDI, динамически расширяемый |
| Установка | Ubuntu Server, обычный вариант; весь диск; OpenSSH server; без Featured snaps |

После установки выполнены `sudo apt update && sudo apt upgrade -y`.

## 2. Сетевые интерфейсы

| Адаптер VirtualBox | Интерфейс Ubuntu | Адрес | Назначение |
| --- | --- | --- | --- |
| 1: NAT | `enp0s8` | `10.0.2.15/24` | Выход в интернет и SSH через проброс порта |
| 2: Host-only network `devops-hostonly` | `enp0s9` | `192.168.56.101/24` | Прямой доступ с Mac; адрес Mac — `192.168.56.100` |

Оба адаптера включены. Адреса проверяются командой `ip -brief address`. Адрес Host-only выдан DHCP-сервером VirtualBox; при восстановлении его нужно проверить перед редактированием `hosts`.

## 3. Правило проброса портов

Правило `ssh`: TCP `127.0.0.1:2222` на Mac → порт `2222` ВМ, адрес гостя в правиле не задан. При первоначальной установке порт гостя был `22`; после изменения SSH-сервера правило обновлено. Проверка с Mac: `ssh devops`.

## 4. Учётные записи

| Учётная запись | Группы | Способ входа |
| --- | --- | --- |
| `student` | `student`, `adm`, `cdrom`, `sudo`, `dip`, `plugdev`, `lxd` | Локальная консоль с паролем; SSH запрещён директивой `AllowUsers` |
| `devops` | `devops`, `sudo`, `users` | SSH по отдельному ключу Ed25519; `sudo` с паролем |

Пароли не хранятся в репозитории. Владелец ВМ хранит их отдельно. На Mac закрытый ключ расположен в `~/.ssh/devops_vm` (права `600`), открытый — в `~/.ssh/devops_vm.pub`. На сервере открытый ключ добавлен в `/home/devops/.ssh/authorized_keys`; права: `700` для `.ssh`, `600` для `authorized_keys`.

В `~/.ssh/config` на Mac настроен псевдоним `devops`: `HostName 127.0.0.1`, `Port 2222`, `User devops`, `IdentityFile ~/.ssh/devops_vm`, `IdentitiesOnly yes`. Для `devops.local` указан тот же ключ и порт. Отпечаток ключа SSH-сервера: `SHA256:aapurb76RMoDZrVPc2klsz6du0ig+mUpQvuWMeNKUeQ` (Ed25519).

Для демонстрации подключения из консоли самой ВМ дополнительно создан отдельный гостевой ключ `~/.ssh/devops_vm_local`. Основной доступ с Mac от этого ключа не зависит.

## 5. Служба SSH

Действующий порт — `2222`. `ssh.service` включён и активен, `ssh.socket` отключён. Основной `/etc/ssh/sshd_config` не изменялся; его копия — `/etc/ssh/sshd_config.backup`. Дополнительные директивы находятся в `/etc/ssh/sshd_config.d/99-hardening.conf`:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

В `/etc/ssh/sshd_config.d/50-cloud-init.conf` строка `PasswordAuthentication yes` закомментирована: этот файл читается раньше `99-hardening.conf`. Перед перезапуском проверены `sudo sshd -t` и действующие значения `sudo sshd -T`. Команда `sudo ss -tlnp | grep sshd` показывает прослушивание `0.0.0.0:2222` и `[::]:2222`.

## 6. Правила межсетевого экрана

UFW активен, журналирование — `medium`. Политики: `deny incoming`, `allow outgoing`, маршрутизируемый трафик отключён.

| Порт | Правило | Назначение |
| --- | --- | --- |
| `2222/tcp` | `LIMIT IN` | SSH с ограничением частоты подключений |
| `80/tcp` | `ALLOW IN` | HTTP для следующей работы |
| `443/tcp` | `ALLOW IN` | HTTPS для следующей работы |

Правила действуют для IPv4 и IPv6. Сначала добавлено разрешение для `2222/tcp`, затем включён UFW; после проверки нового SSH-подключения разрешение заменено на `LIMIT`. Проверка: `sudo ufw status verbose`. Попытка с Mac подключиться к `192.168.56.101:8080` блокируется и фиксируется в `/var/log/ufw.log` как `UFW BLOCK`.

## 7. Снимки состояния

Время указано по Москве (UTC+3).

| Снимок | Создан | Состояние |
| --- | --- | --- |
| `01-clean-install` | 22.10.2026 22:26 | Чистая Ubuntu Server, два адаптера, OpenSSH, обновления |
| `02-keys-configured` | 22.10.2026 22:48 | Пользователь `devops`, ключевой вход, псевдоним SSH на Mac |
| `03-ssh-hardened` | 22.10.2026 23:46 | SSH на порту 2222, запрет root и пароля, обновлённый проброс |

UFW и полное доменное имя настроены **после** снимка `03-ssh-hardened`.

## Восстановление после отката на 01-clean-install

1. Проверить адреса командой `ip -brief address`. На Mac правило VirtualBox для NAT должно сначала вести `127.0.0.1:2222` на гостевой порт `22`, чтобы можно было подключиться как `student`.
2. В ВМ создать пользователя и дать ему право `sudo`: `sudo adduser devops && sudo usermod -aG sudo devops`. На Mac, где уже существует ключ `~/.ssh/devops_vm`, выполнить `ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1`. Проверить `ssh -i ~/.ssh/devops_vm -p 2222 devops@127.0.0.1` и права `stat -c '%a %n' ~/.ssh ~/.ssh/authorized_keys` в госте.
3. На сервере сохранить основной файл: `sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup`. Создать `/etc/ssh/sshd_config.d/99-hardening.conf` с директивами из раздела 5. Закомментировать `PasswordAuthentication yes` в `/etc/ssh/sshd_config.d/50-cloud-init.conf`. Проверить `sudo sshd -t` и `sudo sshd -T`.
4. Не закрывая действующую сессию, выполнить `sudo systemctl disable --now ssh.socket && sudo systemctl enable --now ssh.service && sudo systemctl restart ssh`. Проверить `sudo ss -tlnp | grep sshd`. На работающей ВМ изменить NAT-правило командами `VBoxManage controlvm devops-vm natpf1 delete ssh` и `VBoxManage controlvm devops-vm natpf1 'ssh,tcp,127.0.0.1,2222,,2222'`. Открыть **новое** соединение `ssh devops`.
5. Создать правила до включения UFW: `sudo ufw default deny incoming`, `sudo ufw default allow outgoing`, `sudo ufw allow 2222/tcp comment 'SSH'`, `sudo ufw allow 80/tcp comment 'HTTP'`, `sudo ufw allow 443/tcp comment 'HTTPS'`. Затем `sudo ufw enable`, проверить новое SSH-подключение и выполнить `sudo ufw delete allow 2222/tcp && sudo ufw limit 2222/tcp comment 'SSH rate-limited' && sudo ufw logging medium`.
6. На Mac добавить в `/etc/hosts` строку `192.168.56.101 devops.local` с фактическим Host-only адресом. На сервере выполнить `sudo hostnamectl set-hostname devops-vm` и задать строку `127.0.1.1 devops-vm.devops.local devops-vm` в `/etc/hosts`. Проверить `hostname -f`, `ping devops.local` и `ssh -p 2222 devops@devops.local` с Mac.
7. Итоговая проверка: `ssh devops`, `sudo sshd -T`, `sudo ss -tlnp | grep sshd`, `sudo ufw status verbose`, а также `scripts/audit.sh` (все проверки должны пройти).
