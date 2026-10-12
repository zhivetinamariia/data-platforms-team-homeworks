# Домашнее задание №2: развертывание YARN

Развертывание YARN поверх кластера HDFS из ДЗ-1
Веб-интерфейсы YARN (ResourceManager, NodeManager) и JobHistory Server публикуются наружу через Nginx на edge-ноде

## Схема кластера

| Узел | IP | Сервисы |
|---|---|---|
| `team-21-en` | 10.21.0.10 | **nginx** (публикация веб-интерфейсов) |
| `team-21-nn` | 10.21.0.11 | **ResourceManager**, **NodeManager**, **JobHistory Server** |
| `team-21-00` | 10.21.0.12 | **NodeManager** |
| `team-21-01` | 10.21.0.13 | **NodeManager** |

**Доступ к UI снаружи:**
* ResourceManager: `http://<внешний IP edge-ноды>:8088`
* JobHistory Server: `http://<внешний IP edge-ноды>:19888`
* NodeManager (team-21-nn): `http://<внешний IP edge-ноды>:8042`
* NodeManager (team-21-00): `http://<внешний IP edge-ноды>:8043`
* NodeManager (team-21-01): `http://<внешний IP edge-ноды>:8044`

## Структура репозитория

* `config.env` — основные параметры кластера (порты, хосты, ресурсы контейнеров)
* `deploy.sh` — главный скрипт развертывания
* `scripts/` — пошаговые скрипты настройки (генерация xml-конфигов, запуск демонов, настройка nginx) и файл с общими bash-функциями (`common.sh`)
* `scripts/stop_yarn.sh` — скрипт для остановки всех демонов YARN

## Предварительные требования

- Успешно запущенный HDFS из ДЗ-1 (минимум 3 DataNode)
- Hadoop 3.4.0 установлен в `/home/hadoop/hadoop-3.4.0`
- Беспарольный ssh-доступ для пользователя `hadoop` между нодами
- У пользователя `team` на edge-ноде есть права `sudo` для установки и настройки Nginx

## Особенности конфигурации (YARN & MapReduce)

Так как кластер разворачивается на виртуальных машинах с ограниченными ресурсами (3.8 ГБ RAM), в генерируемых конфигах применены следующие тюнинги:
* **Ресурсы узлов**: NodeManager отдает YARN только 2 ГБ RAM и 2 vCore, чтобы оставить память для NameNode и DataNode
* **Размер контейнеров**: контейнеры MapReduce по 512 МБ (по умолчанию ApplicationMaster просит 1.5 ГБ, что не помещается на узлах)
* **Проверка виртуальной памяти отключена** (`vmem-check-enabled=false`): на небольших ВМ она ошибочно завершает контейнеры

## Запуск

На edge-ноде от пользователя `team`:

```bash
git clone https://github.com/zhivetinamariia/data-platforms-team-homeworks.git
cd data-platforms-team-homeworks/task-02
bash deploy.sh
```

`deploy.sh` по очереди выполняет:
1. `01_configure_yarn.sh` - создаёт yarn-site.xml и mapred-site.xml и копирует их на узлы
2. `02_start_yarn.sh` - запускает ResourceManager, NodeManager-ы и JobHistory Server
3. `03_publish_nginx.sh` - ставит nginx и публикует веб-интерфейсы
4. `04_check.sh` - проверяет интерфейсы и запускает тестовую задачу

## Проверка

- `yarn node -list` на team-21-nn показывает 3 узла в состоянии RUNNING
- тестовая задача `pi` завершается строкой `Estimated value of Pi is ...`
- `http://<внешний IP edge-ноды>:8088` - Active Nodes: 3, задача QuasiMonteCarlo в статусе SUCCEEDED
- `http://<внешний IP edge-ноды>:19888` - задача видна в истории