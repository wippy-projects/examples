# HTTP Async Task — Coroutine Background Processing

HTTP-сервер на Wippy, который принимает `POST /api/tasks`, валидирует входные данные и запускает фоновую задачу через `coroutine.spawn()`. Ответ `202 Accepted` возвращается мгновенно, корутина продолжает работу в фоне.

## Концепция

```
Client                    Handler (function)              Coroutine
  │                            │                              │
  │  POST /api/tasks           │                              │
  │  {"name":"report"}         │                              │
  │ ──────────────────────────▶│                              │
  │                            │  coroutine.spawn(work)       │
  │                            │ ────────────────────────────▶│
  │          202 Accepted      │                              │  step 1/3...
  │ ◀──────────────────────────│                              │  step 2/3...
  │                                                           │  step 3/3...
  │                                                           │  done ✓
```

Ключевая идея: `coroutine.spawn()` запускает фоновую корутину **внутри** того же процесса, в котором работает HTTP-хендлер. Корутина легковесна — нет overhead'а на создание отдельного процесса. Подходит для задач, которые не требуют изоляции состояния.

## Структура

```
http-async-task/
├── wippy.lock
├── k6.js                    # Load test
├── test.http                # Manual test requests
└── src/
    ├── _index.yaml          # Registry: http server + handler
    └── handler.lua          # POST /api/tasks → coroutine.spawn → 202
```

## Registry

| Entry | Kind | Назначение |
|-------|------|-----------|
| `app:processes` | `process.host` | Хост для процессов (4 воркера) |
| `app:gateway` | `http.service` | HTTP-сервер на `:8080` |
| `app:router` | `http.router` | Роутер с prefix `/api` |
| `app:process_task` | `function.lua` | Хендлер задач |
| `app:process_task.endpoint` | `http.endpoint` | `POST /api/tasks` |

## API

### POST /api/tasks

Создать фоновую задачу.

**Request:**
```json
{
  "name": "generate-report",
  "duration": 5
}
```

| Поле | Тип | Обязательно | Описание |
|------|-----|-------------|----------|
| `name` | string | да | Название задачи (непустая строка) |
| `duration` | integer | нет | Длительность в секундах (default: 3) |

**Response `202 Accepted`:**
```json
{
  "task_id": "task_1738880000",
  "name": "generate-report",
  "status": "accepted",
  "message": "Task will run for 5 seconds in background"
}
```

**Errors:**
- `400` — невалидный JSON или отсутствует `name`

## Запуск

```bash
cd examples/http-async-task
wippy run
```

## Тестирование

### Ручное
```bash
# Отправить задачу
curl -X POST http://localhost:8080/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"name": "generate-report", "duration": 5}'

# Ответ мгновенный, в логах видно пошаговое выполнение:
#   Task started      {task_id: "task_...", name: "generate-report"}
#   Task progress     {step: 1, total: 5}
#   Task progress     {step: 2, total: 5}
#   ...
#   Task completed    {task_id: "task_..."}
```

### k6 нагрузочный тест
```bash
k6 run k6.js
```

## Результаты нагрузочного тестирования

### Конфигурация теста

| Phase | Duration | Target RPS |
|-------|----------|------------|
| Ramp 1 | 10s | 1 000 → 10 000 |
| Ramp 2 | 10s | 10 000 → 50 000 |
| Ramp 3 | 20s | 50 000 → 100 000 |
| Sustain | 30s | 100 000 |
| Cooldown | 10s | 100 000 → 1 000 |

Max VUs: **10 000**

### Результаты

| Metric | Value |
|--------|-------|
| **Total requests** | 1 621 176 |
| **Achieved RPS** | ~19 500 rps |
| **Error rate** | 0.00% |
| **p50 (median)** | 1.26 ms |
| **p90** | 5.74 ms |
| **p95** | 10.55 ms |
| **p99** | 60.13 ms |
| **Max** | 1 148 ms |
| **Data received** | 131 MB (1.6 MB/s) |
| **Data sent** | 275 MB (3.3 MB/s) |
| **Duration** | 1m 23s |

### Выводы

- **Wippy стабильно держит ~19.5k rps** с одного инстанса k6 при 0% ошибок
- **Латентность отличная:** медиана 1.26ms, p95 = 10.5ms даже под максимальной нагрузкой
- **Реальный потолок сервера не достигнут** — k6 дропнул 3.7M итераций, не успевая генерировать нагрузку. Для 100k rps нужен распределённый k6
- `coroutine.spawn()` не влияет на латентность ответа — фоновая работа полностью отвязана от HTTP-цикла

## Когда использовать coroutine.spawn

| Подходит | Не подходит |
|----------|-------------|
| Лёгкие фоновые задачи | Задачи с изолированным состоянием |
| Логирование, метрики | Задачи, которые нужно мониторить |
| Fire-and-forget обработка | Задачи с retry/supervision |
| Всё в рамках одного процесса | Задачи, требующие отдельный lifecycle |

Для изолированных задач с supervision используй `process.spawn()` — смотри пример [http-spawn](../http-spawn/).
