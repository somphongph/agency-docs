# Docker Compose

โฟลเดอร์นี้เก็บ **เฉพาะการประกอบ stack** — Dockerfile และไฟล์ build ของแต่ละส่วนอยู่ในโปรเจกต์ของตัวเอง

```
agency-api/Dockerfile          # Spring Boot (multi-stage: maven build → JRE runtime)
agency-api/.dockerignore
agency-web/Dockerfile     # Angular build → nginx
agency-web/nginx.conf.template # SPA fallback, cache headers, proxy /api → $API_HOST (render ตอน start)
agency-web/.dockerignore

agency-docs/docker/
├─ Makefile                    # up/down/logs, infra, build-versions, pull
├─ agency-stack/               # stack ของแอป: api + web (build จาก source)
│  └─ docker-compose.yml
├─ agency-pull/                # รัน image ที่ build ไว้ (เดโม develop vs sse)
│  ├─ docker-compose.yml
│  └─ README.md
├─ scripts/build-versions.sh   # build agency-{api,web}:{develop,sse} จาก git refs
└─ agency-infra/               # observability stack (Grafana + Prometheus + blackbox)
   ├─ docker-compose.yml
   ├─ prometheus/{prometheus.yml,rules,targets}
   ├─ blackbox/blackbox.yml
   └─ grafana/{provisioning,dashboards}
```

## ใช้งาน

```bash
cd agency-docs/docker

make up          # build + start (docker compose -f agency-stack/docker-compose.yml up -d --build)
make ps          # ดูสถานะ (healthcheck)
make logs        # ดู log ทั้ง stack
make down        # หยุดและลบ container/network (make down ARGS=-v เพื่อลบ volumes)
```

หรือเรียก compose ตรง ๆ: `cd agency-stack && docker compose up -d --build`

| Service | Container port | Host port | เข้าถึง |
|---|---|---|---|
| api | 8080 | 8080 | http://localhost:8080/api/v1/health |
| web | 80 | 4200 | http://localhost:4200 |

> web ใช้พอร์ต 4200 เหมือน `ng serve` เพื่อให้เปิด URL เดิมได้ และ nginx proxy `/api/*`
> ไปที่ `api:8080` → **same origin ไม่ต้องตั้ง CORS**

## Build image แยก (ไม่ผ่าน compose)

แต่ละคำสั่งรันในโฟลเดอร์ของโปรเจกต์นั้น ๆ (build context = โฟลเดอร์นั้น)

```bash
cd agency-api && docker build -t agency-api .
cd agency-web && docker build -t agency-web .
```

## Healthcheck

- **api**: probe `/api/v1/health` จริงผ่าน bash `/dev/tcp` (image เป็น JRE ล้วน ไม่มี curl/wget)
  → ถ้าได้ `200` แปลว่า Spring context พร้อม ไม่ใช่แค่ port เปิด
- **web**: `wget --spider http://127.0.0.1/`
- `web` มี `depends_on: api: condition: service_healthy` จึงไม่ขึ้นก่อน API พร้อม

## หมายเหตุ

- Tests ไม่รันตอน build image (`-DskipTests`) — รันแยกด้วย `./mvnw test`, `pnpm test`, และ Bruno collection
- Runtime ของ API เป็น user `app` (uid 1001) ไม่ใช่ root
- `JAVA_OPTS` ตั้ง `-XX:MaxRAMPercentage=75` เพื่อให้ heap ปรับตาม memory limit ของ container
- Image size (arm64, ทดสอบจริง): api ~517MB (compressed ~133MB), web ~76MB (compressed ~22MB)

## Observability (Grafana + Prometheus)

แยก stack ต่างหากที่ `agency-infra/` — ไม่ผูกกับ compose ของแอป:

```bash
cd agency-docs/docker

make infra          # = docker compose -f agency-infra/docker-compose.yml up -d
make infra-ps       # ดูสถานะ container
make infra-logs     # ดู log
make infra-down     # = ... down   (เพิ่ม ARGS=-v เพื่อลบ volumes)
```

| URL | หมายเหตุ |
|---|---|
| http://localhost:3000 | Grafana (user `admin`, password `GRAFANA_ADMIN_PASSWORD` หรือ `admin`) |
| http://localhost:9090 | Prometheus |

รายละเอียด + วิธี scrape `agency-api` (ต้องเพิ่ม actuator/micrometer ก่อน) ดูที่
[`agency-infra/README.md`](agency-infra/README.md)

## เดโม 2 เวอร์ชัน (develop vs feature/sse)

```bash
cd agency-docs/docker
make build-versions                  # build agency-{api,web}:{develop,sse}
make pull                            # รัน develop บน 8081/4201
API_TAG=sse WEB_TAG=sse make pull    # สลับเป็น feature/sse
make pull-down
```

| | develop (8081/4201) | feature/sse (8081/4201) |
|---|---|---|
| web | polling ทุก 5 วิ | SSE |
| `/api/v1/health` | 404 | 200 |
| `/api/v1/dashboard/stream` | 404 | SSE event |

รายละเอียด: [`agency-pull/README.md`](agency-pull/README.md)
