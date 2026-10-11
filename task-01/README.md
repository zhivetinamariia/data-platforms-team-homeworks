# Домашнее задание №1: развертывание HDFS

Кластер развернут на четырех виртуальных машинах Ubuntu 24.04.
Используется Hadoop 3.4.0 и Java 11.

На team-21-nn работают NameNode, SecondaryNameNode и DataNode.
Еще два DataNode работают на team-21-00 и team-21-01.
С team-21-en выполняются команды установки и проверки.

Ниже описаны подготовка машин, настройка Hadoop, первый запуск
и проверка кластера. Команды автоматизированы скриптами
из папки scripts.

## Схема кластера

| Узел | IP | Сервисы |
|---|---|---|
| team-21-en | 10.21.0.10 | Клиент Hadoop, запуск скриптов |
| team-21-nn | 10.21.0.11 | NameNode, SecondaryNameNode, DataNode |
| team-21-00 | 10.21.0.12 | DataNode |
| team-21-01 | 10.21.0.13 | DataNode |

## Файлы проекта

- configs/ — настройки Hadoop и параметры кластера.
- scripts/ — установка, настройка, инициализация, запуск и проверка.
- evidence/ — сохраненные результаты проверок.

## Что нужно перед установкой

Для установки нужны четыре машины Ubuntu 24.04 с архитектурой x86_64. Скрипты настраивают Hadoop на готовых машинах, но не создают виртуальные машины.

Команды установки выполняются на team-21-en под пользователем team. У него должны быть sudo без пароля на всех четырех машинах и SSH-доступ к внутренним узлам.

Имена узлов должны разрешаться в адреса из таблицы выше. Если DNS не настроен, записи из configs/hosts.expected нужно добавить в /etc/hosts на каждой машине, сохранив остальные записи.

Параметры кластера находятся в configs/cluster.env. Путь к внутреннему SSH-ключу задан в ADMIN_SSH_KEY. Сам ключ в репозиторий не включен.

Для загрузки Hadoop и установки пакетов нужен доступ к archive.apache.org и репозиториям Ubuntu.

## Установка Java и Hadoop

Для новой установки разместить проект в /home/team/hdfs-homework-1 на edge. Под пользователем team выполнить:

```bash
cd /home/team/hdfs-homework-1
bash scripts/prepare-cluster.sh --install
```

Скрипт устанавливает Java 11 и SSH, создает пользователя hadoop и устанавливает Hadoop 3.4.0 в /home/hadoop/hadoop-3.4.0. Перед распаковкой архива проверяется SHA-512.

Если пользователь hadoop или каталог Hadoop уже существуют, скрипт использует их и проверяет установку. Существующий каталог Hadoop не перезаписывается.

## Настройка SSH

Для запуска и проверки кластера пользователь hadoop на edge должен подключаться к трем серверным узлам без запроса пароля.

На edge переключиться на hadoop и подготовить каталог для ключей:

```bash
sudo -iu hadoop
install -d -m 700 ~/.ssh
```

Если подходящий ключ уже есть, использовать его. Если файла ~/.ssh/id_ed25519 нет, создать ключ:

```bash
test ! -e ~/.ssh/id_ed25519 &&
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
```

Показать публичный ключ:

```bash
cat ~/.ssh/id_ed25519.pub
```

Администратор добавляет эту строку в /home/hadoop/.ssh/authorized_keys на team-21-nn, team-21-00 и team-21-01. Существующие ключи в файле нужно сохранить. Приватный ключ остается на edge и в репозиторий не добавляется.

На каждом серверном узле подготовить файл:

```bash
sudo install -d -o hadoop -g hadoop -m 700 /home/hadoop/.ssh
sudo touch /home/hadoop/.ssh/authorized_keys
sudo chown hadoop:hadoop /home/hadoop/.ssh/authorized_keys
sudo chmod 600 /home/hadoop/.ssh/authorized_keys
sudo nano /home/hadoop/.ssh/authorized_keys
```

После добавления публичного ключа проверить подключения с edge под hadoop:

```bash
ssh hadoop@team-21-nn hostname
ssh hadoop@team-21-00 hostname
ssh hadoop@team-21-01 hostname
```

При первом подключении сверить отпечаток ключа сервера с администратором или через доверенную консоль машины, затем подтвердить подключение. В текущем кластере SSH уже настроен, создавать новые ключи не требуется.

## Настройка Hadoop

На edge под team выполнить до запуска сервисов:

```bash
cd /home/team/hdfs-homework-1
bash scripts/configure-cluster.sh --apply
```

Скрипт копирует core-site.xml, hdfs-site.xml и workers на все четыре машины и задает JAVA_HOME в hadoop-env.sh. Старые конфиги сохраняются в отдельном каталоге рядом с установленными настройками.

Если на узлах работают процессы HDFS, скрипт отказывается применять изменения.

В конфигурации используются:

- fs.defaultFS — hdfs://team-21-nn:9000;
- dfs.replication — 3;
- JAVA_HOME — /usr/lib/jvm/java-11-openjdk-amd64;
- workers — team-21-nn, team-21-00, team-21-01.

Каталоги хранения:

- /tmp/hadoop-hadoop/dfs/name — метаданные NameNode;
- /tmp/hadoop-hadoop/dfs/data — блоки DataNode;
- /tmp/hadoop-hadoop/dfs/namesecondary — контрольные снимки SecondaryNameNode.

Для этой установки оставлены стандартные пути в /tmp/hadoop-hadoop. Настройка постоянных каталогов хранения в скрипты не включена.

## Подготовка проекта для запуска

Установка и настройка выполняются под team, а запуск и проверка HDFS — под hadoop. После настройки скопировать проект в домашний каталог hadoop:

```bash
sudo install -d -o hadoop -g hadoop -m 750 /home/hadoop/hdfs-homework-1
sudo cp -a /home/team/hdfs-homework-1/. /home/hadoop/hdfs-homework-1/
sudo chown -R hadoop:hadoop /home/hadoop/hdfs-homework-1
```

Переключиться на hadoop и проверить сеть:

```bash
sudo -iu hadoop
cd /home/hadoop/hdfs-homework-1
chmod +x scripts/*.sh
./scripts/check-network.sh
```

## Первый запуск

Форматирование выполняется только при создании нового кластера. Перед этим нужно убедиться, что каталоги NameNode, DataNode и SecondaryNameNode не содержат данных от другой установки. Если такие данные есть, не удалять их и не продолжать форматирование.

На edge под hadoop проверить наличие метаданных:

```bash
cd /home/hadoop/hdfs-homework-1
./scripts/init-namenode.sh --check
```

Для новой установки, если метаданных нет и процессы HDFS остановлены:

```bash
./scripts/init-namenode.sh --initialize
./scripts/start.sh
```

Если найден current/VERSION, скрипт пропускает форматирование. Он также отказывается форматировать непустой каталог или выполнять форматирование при работающих процессах HDFS на узле NameNode. Проверка каталогов DataNode на остальных машинах выполняется отдельно до инициализации.

start.sh запускает NameNode и SecondaryNameNode на team-21-nn и три DataNode на team-21-nn, team-21-00 и team-21-01.

## Повторный запуск

Для уже инициализированного кластера выполнить под hadoop:

```bash
cd /home/hadoop/hdfs-homework-1
./scripts/start.sh
```

Работающие процессы пропускаются с сообщением SKIP. После запуска скрипт проверяет состояние кластера. Повторное форматирование не требуется.

## Проверка кластера

На edge под hadoop:

```bash
cd /home/hadoop/hdfs-homework-1
./scripts/check-network.sh
./scripts/verify.sh
```

check-network.sh проверяет разрешение имен на всех четырех машинах и SSH от hadoop на edge к трем серверным узлам.

verify.sh проверяет:

- наличие трех живых DataNode со статусом Normal;
- отсутствие мертвых DataNode;
- процессы NameNode, SecondaryNameNode и трех DataNode;
- выключенный safe mode;
- отсутствие пропавших, поврежденных и недореплицированных блоков.

При успешной проверке выводится PASS, код завершения — 0. Запись и чтение файлов, а также содержимое логов этот скрипт не проверяет.

Установку и конфигурацию можно проверить без изменений. На edge под team:

```bash
cd /home/team/hdfs-homework-1
bash scripts/prepare-cluster.sh --check
bash scripts/configure-cluster.sh --check
```

## Веб-интерфейс

На своем компьютере открыть SSH-туннель через edge. В команде указать свой ключ и адрес подключения:

```bash
ssh -i ~/.ssh/team21_ed25519 -o IdentitiesOnly=yes -o ExitOnForwardFailure=yes -N -L 127.0.0.1:9870:10.21.0.11:9870 team@171.22.73.179
```

Оставить терминал открытым и перейти в браузере на http://localhost:9870. Во вкладке Datanodes должны отображаться три работающих узла.

## Результаты

На кластере team-21 проверены установка Java и Hadoop, совпадение конфигов на всех машинах, разрешение имен и SSH-доступ. Скрипт инициализации обнаружил существующие метаданные и пропустил форматирование. При повторном запуске все пять работающих сервисов были пропущены.

Итоговая проверка показала три живых DataNode со статусом Normal. NameNode и SecondaryNameNode работают, safe mode выключен. Пропавших, поврежденных и недореплицированных блоков нет. На момент проверки файлов с данными в HDFS еще не было.

Вывод команд сохранен в evidence/.

Кластер развернут вручную по шагам, описанным выше. После развертывания подготовлены скрипты автоматизации. На работающем кластере проверены режимы проверки установки и конфигурации, сетевая проверка, пропуск повторного форматирования и повторный запуск сервисов.
