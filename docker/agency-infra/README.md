# agency-infra — Grafana + Prometheus

Observability stack สำหรับโปรเจกต์ Agency Dashboard (แยกจาก stack ของแอปใน `../docker-compose.yml`)

```
agency-infra/
├─ docker-compose.yml                     # blackbox + prometheus + grafana
├─ blackbox/blackbox.yml                  # probe modules (http_2xx)
├─ prometheus/
│  ├─ prometheus.yml                      # scrape config (self + blackbox; API ยังไม่มี metrics)
│  ├─ rules/blackbox.yml                  # alert rules (SiteDown / SiteSlow / SiteNotOk / CertExpiringSoon)
│  └─ targets/blackbox.yml                # URL ที่จะ probe (file_sd — แก้แล้วไม่ต้อง restart)
└─ grafana/
   ├─ provisioning/datasources/prometheus.yml   # datasource (default)
   ├─ provisioning/dashboards/dashboards.yml    # provider (folder "Agency")
   └─ dashboards/
      ├─ blackbox-http.json                     # synthetic checks
      └─ api-metrics.json                       # Spring Boot (JVM/HTTP/SSE)
```

## ใช้งาน

```bash
cd agency-docs/docker

make infra          # start (docker compose -f agency-infra/docker-compose.yml up -d)
make infra-ps       # ต้องเห็นทั้งคู่ healthy
make infra-logs     # ดู log
make infra-down     # หยุด (make infra-down ARGS=-v เพื่อลบ volumes)
```

หรือเรียก compose ตรง ๆ ก็ได้:
```bash
cd agency-infra
docker compose up -d && docker compose down
```

| Service | Host URL | หมายเหตุ |
|---|---|---|
| Grafana | http://localhost:3000 | `admin` / `admin` (override ด้วย `GRAFANA_ADMIN_PASSWORD`) |
| Prometheus | http://localhost:9090 | scrape ทุก 15 วิ (agency-api ทุก 10 วิ), เก็บ 15 วัน, มี alert rules |
| blackbox_exporter | http://localhost:9115 | ยิง HTTP probe ให้ Prometheus |

- Grafana ตั้ง anonymous viewer ไว้ให้เปิดดูได้เลย (ปิดด้วย `GRAFANA_ANONYMOUS_ENABLED=false`)
- datasource `Prometheus` ถูก provision ให้อัตโนมัติ (default) → สร้าง panel ได้ทันที

```bash
GRAFANA_ADMIN_PASSWORD='s3cret' docker compose up -d
```

## ตรวจว่าใช้งานได้

```bash
curl -s http://localhost:9090/-/ready                 # 200
curl -s http://localhost:3000/api/health              # {"database":"ok",...}
curl -s http://localhost:9090/api/v1/targets \
  | jq -r '.data.activeTargets[] | "\(.labels.job): \(.health)"'
```

## ให้ Prometheus scrape `agency-api` (ยังทำไม่ได้ตอนนี้)

API ยังไม่มี metrics endpoint (`spring-boot-starter-actuator` + `micrometer-registry-prometheus` ยังไม่ได้ใส่)
เมื่อเพิ่มแล้ว เลือกทางใดทางหนึ่ง:

**ก) scrape ผ่าน host port (ง่ายสุด)** — เปิด job ใน `prometheus/prometheus.yml`:
```yaml
  - job_name: agency-api
    metrics_path: /actuator/prometheus
    static_configs:
      - targets: ["host.docker.internal:8080"]
```
`docker-compose.yml` map `host.docker.internal:host-gateway` ไว้แล้ว (ใช้ได้ทั้ง macOS/Linux)
แล้วสั่ง reload: `curl -X POST http://localhost:9090/-/reload`

**ข) ต่อเข้า network ของแอป** — ให้ scrape `api:8080` ตรง ๆ:
```yaml
networks:
  default:
    name: agency-stack_default       # network ที่ ../agency-stack/docker-compose.yml สร้าง
    external: true
```
> ต้องรัน stack ของแอปก่อน (`cd .. && make up`) ไม่งั้น network จะไม่ถูกสร้าง

## หมายเหตุ

- พอร์ตที่ใช้: 3000 (Grafana), 9090 (Prometheus) — ไม่ชนกับ api (8080) / web (4200)
- ข้อมูลเก็บใน named volumes `prometheus-data`, `grafana-data` (ลบด้วย `docker compose down -v`)
- image pin เวอร์ชันไว้: `prom/prometheus:v3.15.1`, `grafana/grafana:13.2.5`

## Synthetic checks (blackbox_exporter)

Prometheus ไม่ได้ scrape `agency-web` โดยตรง (เป็น static site) แต่จะ scrape **blackbox_exporter**
ซึ่งยิง HTTP request จริงไปที่ URL ใน `prometheus/targets/blackbox.yml` แล้วคืน metric:

| metric | ความหมาย |
|---|---|
| `probe_success` | 1 = ผ่าน (2xx + TLS ใช้ได้ + ไม่ timeout), 0 = ไม่ผ่าน |
| `probe_duration_seconds` | เวลารวมของ probe (วินาที) |
| `probe_http_status_code` | HTTP status จริง, **0 = ไม่มี response** (DNS/connect/TLS fail) |
| `probe_ssl_earliest_cert_expiry` | Unix timestamp ของ cert ที่หมดอายุเร็วที่สุด |
| `probe_http_duration_seconds{phase=…}` | แยก resolve / connect / tls / processing / transfer |

แก้ target ได้ที่ `prometheus/targets/blackbox.yml` (file_sd reload ทุก 30 วิ ไม่ต้อง restart)
ค่าเริ่มต้น probe: CloudFront `/` และ `/api/v1/health`; local Docker stack ถูก comment ไว้

```bash
# ดูค่าดิบ
curl -s 'http://localhost:9115/probe?target=https://dw0pg1vujg42n.cloudfront.net/&module=http_2xx'
# ดูสาเหตุที่ fail
curl -s 'http://localhost:9115/probe?target=https://...&module=http_2xx&debug=true' | grep level=ERROR
```

PromQL ที่ใช้บ่อย:
```promql
avg_over_time(probe_success{job="blackbox-http"}[30d]) * 100                  # uptime %
(probe_ssl_earliest_cert_expiry{job="blackbox-http"} - time()) / 86400         # cert เหลือกี่วัน
probe_duration_seconds{job="blackbox-http"} > 2                                # ช้า
```

Alert rules: `SiteDown` (2m), `SiteSlow` (>2s 10m), `SiteNotOk` (≠200 5m), `CertExpiringSoon` (<14 วัน)
— ดูสถานะที่ Prometheus → Alerts (ยังไม่มี Alertmanager ⇒ ไม่มีการส่ง notification)

> **IPv6 gotcha**: Docker network ปกติไม่มี route IPv6 ถ้า container resolve โดเมนเป็น AAAA
> จะได้ `network is unreachable` ทั้งที่เว็บปกติ → module ตั้ง `preferred_ip_protocol: ip4` ไว้แล้ว
> ถ้าเพิ่ม module ใหม่ อย่าลืมใส่ค่านี้

## Dashboard (provisioned)

`grafana/dashboards/blackbox-http.json` ถูก provision เข้า folder **Agency** อัตโนมัติ
(refresh ทุก 30s) — เปิดที่ http://localhost:3000 → Dashboards → Agency → *Blackbox — HTTP probes*

| panel | query |
|---|---|
| Targets up | `sum(probe_success{job="blackbox-http"})` |
| Probes configured | `count(probe_success{...})` |
| Slowest probe | `max(probe_duration_seconds{...})` |
| Certificate left | `min((probe_ssl_earliest_cert_expiry{...} - time())/86400)` |
| Probe success | `probe_success{...}` (1 = up) |
| Probe duration by phase | `probe_http_duration_seconds{...}` + total |
| HTTP status code | `probe_http_status_code{...}` |
| Certificate days left | `(probe_ssl_earliest_cert_expiry{...} - time())/86400` |

มี variable `instance` (multi + All) ให้กรอง target ได้จาก dropdown

### หมายเหตุการแก้ไข

- แก้ JSON ใน repo → provisioning โหลดใหม่ภายใน 30s (ไม่ต้อง restart)
- panel ทั้งหมด **ไม่ระบุ datasource** → ใช้ default datasource (Prometheus)
  ถ้าเพิ่ม datasource ที่สองแล้วอยากชี้เฉพาะ ให้ใส่ `uid` ให้ datasource นั้นก่อน
  (อย่าเติม `uid` ให้ datasource เดิมที่มีอยู่ใน volume แล้ว — Grafana 13 จะ crash ด้วย
  `Datasource provisioning error: data source not found`; ถ้าจำเป็นให้ `make infra-down ARGS=-v` ทิ้ง volume หนึ่งครั้ง)
- `allowUiUpdates: true` → แก้ใน UI ได้ แต่จะถูกไฟล์เขียนทับเมื่อ provider reload;
  ถ้าอยากเก็บ ให้ export JSON กลับมาวางใน `grafana/dashboards/`

## Whitebox metrics (agency-api)

`agency-api` เปิด `/actuator/prometheus` (actuator + micrometer-registry-prometheus) และ Prometheus
scrape job `agency-api` (ทุก 10 วิ) ชี้ `host.docker.internal:8080`

| กลุ่ม | ตัวอย่าง metric |
|---|---|
| HTTP | `http_server_requests_seconds_count/_bucket{uri,method,status,outcome}` |
| JVM | `jvm_memory_used_bytes{area,id}`, `jvm_gc_pause_seconds_*`, `jvm_threads_live_threads` |
| Tomcat | `tomcat_threads_busy_threads`, `tomcat_threads_config_max_threads` |
| CPU | `process_cpu_usage`, `system_cpu_usage` |
| **Custom SSE** | `dashboard_stream_subscribers`, `dashboard_stream_events_total`, `dashboard_stream_publish_failures_total` |
| **Custom snapshot** | `dashboard_refresh_total`, `dashboard_snapshot_timestamp_seconds` |

Dashboard: **API — Spring Boot metrics** (folder Agency) — requests total, req/s, 5xx rate, p95,
CPU, heap %, req/s by URI/status, latency quantiles, heap by pool, threads, GC pause, SSE subscribers/events, snapshot age

> แก้ `prometheus/prometheus.yml` แล้ว **ต้อง reload** (ไฟล์ถูก bind mount ไม่ trigger restart):
> `curl -X POST http://localhost:9090/-/reload` หรือ `make infra-down && make infra`

> อย่าเปิด `/actuator/**` สู่อินเทอร์เน็ต — ALB ควร route เฉพาะ `/api/*` (และ health) เท่านั้น
