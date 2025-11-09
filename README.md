# 🚀 Xray WSL Bootstrap

[![GitHub Stars](https://img.shields.io/github/stars/fixplizz-dev/xray-wsl-bootstrap?style=flat-square&logo=github&color=yellow)](https://github.com/fixplizz-dev/xray-wsl-bootstrap/stargazers)
[![GitHub Issues](https://img.shields.io/github/issues/fixplizz-dev/xray-wsl-bootstrap?style=flat-square&logo=github&color=red)](https://github.com/fixplizz-dev/xray-wsl-bootstrap/issues)
[![GitHub Discussions](https://img.shields.io/github/discussions/fixplizz-dev/xray-wsl-bootstrap?style=flat-square&logo=github&color=blue)](https://github.com/fixplizz-dev/xray-wsl-bootstrap/discussions)
[![Latest Release](https://img.shields.io/github/v/release/fixplizz-dev/xray-wsl-bootstrap?style=flat-square&logo=github&color=green)](https://github.com/fixplizz-dev/xray-wsl-bootstrap/releases)
[![License](https://img.shields.io/github/license/fixplizz-dev/xray-wsl-bootstrap?style=flat-square&color=blue)](LICENSE)

**Быстрый деплой Xray VPN клиента в WSL2: одна команда → рабочий VPN**

Поддерживает VLESS/VMess/Trojan с TLS/XTLS/Reality | Автозапуск systemd | Интерактивное управление

## ⚡ Быстрый старт

```bash
curl -fsSL https://raw.githubusercontent.com/fixplizz-dev/xray-wsl-bootstrap/main/scripts/bootstrap.sh | bash
```

**Что происходит:**
1. 📥 Скачивание проекта в `~/xray-wsl-bootstrap`
2. 🔧 Автоматическая настройка прав выполнения
3. 🚀 Запуск интерактивного меню с красивым ASCII интерфейсом
4. 🎯 Выберите опцию настройки (URL/QR/ручная) → установка → готово!

> **💡 После завершения:** `cd ~/xray-wsl-bootstrap && ./xray-wsl` для повторного запуска меню

## 📋 Интерактивное меню

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                            XRAY WSL BOOTSTRAP                               ║
║                        VPN Client Management System                         ║
╚══════════════════════════════════════════════════════════════════════════════╝

Configuration:
  1. Setup Configuration     Interactive config setup
  2. Import from URL         Parse vless://, vmess://, trojan:// URLs
  3. Import from QR Code     Scan QR code image file

Installation & Management:
  5. Install Xray            Download and install Xray service
  6. Service Control         Start/stop/restart service
  7. Check Connection        Verify VPN connection and IP
```

## 🛠 Ручная установка

<details>
<summary>Если нужна ручная настройка</summary>

```bash
# Клонировать проект
git clone https://github.com/fixplizz-dev/xray-wsl-bootstrap.git
cd xray-wsl-bootstrap

# Настроить конфигурацию
cp .env.example .env
nano .env

# Установить
sudo ./scripts/install.sh

# Запустить интерактивное меню
./xray-wsl
```

</details>

## 🔧 Управление через CLI

```bash
# Статус и управление
./xray-wsl status          # показать статус
./xray-wsl start           # запустить VPN
./xray-wsl stop            # остановить VPN
./xray-wsl check-ip        # проверить IP адрес

# Настройка
./xray-wsl setup           # интерактивная настройка
./xray-wsl install         # установка Xray сервиса
```

## 📝 Конфигурация

### Поддерживаемые протоколы
- **VLESS** с TLS/XTLS/Reality
- **VMess** с TLS/XTLS
- **Trojan** с TLS

### Форматы импорта
- **URL**: `vless://`, `vmess://`, `trojan://` ссылки
- **QR код**: PNG/JPEG файлы с proxy URL
- **Ручная настройка**: пошаговый мастер

### Основные переменные (.env)
```bash
XRAY_PROTOCOL=vless                    # vless/vmess/trojan
XRAY_SERVER_HOST=your-server.com       # адрес сервера
XRAY_SERVER_PORT=443                   # порт сервера
XRAY_UUID_OR_PASS=your-uuid-here       # UUID или пароль
XRAY_SECURITY=tls                      # tls/xtls/reality
XRAY_LOCAL_SOCKS_PORT=1080             # локальный SOCKS порт
```

## 🔍 Системные требования

- **WSL2** с Ubuntu 22.04+
- **systemd** включен (`sudo systemctl --version`)
- Интернет соединение
- Базовые пакеты: `curl`, `jq`, `unzip`

### Проверка systemd в WSL
```bash
# Включить systemd в /etc/wsl.conf
echo -e "[boot]\nsystemd=true" | sudo tee -a /etc/wsl.conf

# Перезапустить WSL
wsl --shutdown
```

## 🚨 Решение проблем

**Ошибка "systemd not available":**
```bash
sudo systemctl --version   # проверить systemd
```

**Порт занят:**
```bash
netstat -tlnp | grep :1080  # проверить занятость порта
```

**Проблемы с правами:**
```bash
cd ~/xray-wsl-bootstrap
./xray-wsl fix-permissions  # исправить права скриптов
```

**Сброс конфигурации:**
```bash
cp .env.example .env         # сбросить настройки
sudo ./scripts/install.sh    # переустановить
```

## 📊 Архитектура

```
xray-wsl-bootstrap/
├── xray-wsl              # Главный CLI интерфейс
├── scripts/
│   ├── bootstrap.sh      # Быстрая установка  
│   ├── install.sh        # Установка Xray
│   ├── manage.sh         # Управление сервисом
│   ├── check-ip.sh       # Проверка соединения
│   ├── setup-config.sh   # Интерактивная настройка
│   ├── generate-config.sh # Генерация конфигураций
│   └── parse-url.sh      # Парсинг URL/QR кодов
├── lib/
│   ├── common.sh         # Общие функции
│   ├── url_parser.sh     # Парсер URL/QR кодов
│   └── validate.sh       # Валидация параметров
└── configs/
    ├── .env.example      # Шаблон конфигурации
    └── xray.template.json # Шаблон Xray конфига
```

## � Версии и обновления

**Текущая версия:** v2.0.3

```bash
./xray-wsl version        # показать версию
git pull origin main      # обновить проект
```

## 🤝 Получить помощь

<div align="center">

### 📞 Поддержка и сообщество

| 🐛 Баги и предложения | 💬 Вопросы и идеи | ⭐ Поддержать проект | 📖 Документация |
|:---:|:---:|:---:|:---:|
| [**Создать Issue**](https://github.com/fixplizz-dev/xray-wsl-bootstrap/issues) | [**Обсуждения**](https://github.com/fixplizz-dev/xray-wsl-bootstrap/discussions) | [**Поставить звезду**](https://github.com/fixplizz-dev/xray-wsl-bootstrap) | [**Wiki**](https://github.com/fixplizz-dev/xray-wsl-bootstrap/wiki) |
| Сообщите о проблеме или<br>предложите улучшение | Задайте вопрос или<br>обсудите идеи | Если проект полезен -<br>поставьте ⭐ | Расширенная документация<br>и руководства |

### 🔗 Полезные ссылки

[![Xray Documentation](https://img.shields.io/badge/Xray-Documentation-blue?style=for-the-badge&logo=v2ray)](https://xtls.github.io/)
[![WSL Documentation](https://img.shields.io/badge/WSL-Documentation-green?style=for-the-badge&logo=microsoft)](https://docs.microsoft.com/en-us/windows/wsl/)
[![Systemd in WSL](https://img.shields.io/badge/Systemd-WSL%20Guide-orange?style=for-the-badge&logo=linux)](https://devblogs.microsoft.com/commandline/systemd-support-is-now-available-in-wsl/)

</div>

## 📄 Лицензия

MIT License - смотри [LICENSE](LICENSE)

---

⚡ **Сделано с ❤️ для WSL сообщества**
