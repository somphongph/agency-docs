# Docker Compose

โฟลเดอร์นี้เก็บ **เฉพาะการประกอบ stack** — Dockerfile และไฟล์ build ของแต่ละส่วนอยู่ในโปรเจกต์ของตัวเอง

```
agency-api/Dockerfile          # Spring Boot (multi-stage: maven build → JRE runtime)
agency-api/.dockerignore
agency-web/Dockerfile     # Angular build → nginx
agency-web/nginx.conf     # SPA fallback, cache headers, proxy /api → api:8080
agency-web/.dockerignore

agency-docs/docker/
└─ docker-compose.yml          # ชี้ build context ไปที่ ../../agency-api และ ../../agency-web
```

## ใช้งาน

```bash
cd agency-docs/docker

docker compose up -d --build     # build + start
docker compose ps                # ดูสถานะ (healthcheck)
docker compose logs -f api       # ดู log
docker compose down              # หยุดและลบ container/network
```

| Service | Container port | Host port | เข้าถึง |
|---|---|---|---|
| api | 8080 | 8080 | http://localhost:8080/api/v1/dashboard |
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

- **api**: probe `/api/v1/dashboard` จริงผ่าน bash `/dev/tcp` (image เป็น JRE ล้วน ไม่มี curl/wget)
  → ถ้าได้ `200` แปลว่า Spring context พร้อม ไม่ใช่แค่ port เปิด
- **web**: `wget --spider http://127.0.0.1/`
- `web` มี `depends_on: api: condition: service_healthy` จึงไม่ขึ้นก่อน API พร้อม

## หมายเหตุ

- Tests ไม่รันตอน build image (`-DskipTests`) — รันแยกด้วย `./mvnw test`, `pnpm test`, และ Bruno collection
- Runtime ของ API เป็น user `app` (uid 1001) ไม่ใช่ root
- `JAVA_OPTS` ตั้ง `-XX:MaxRAMPercentage=75` เพื่อให้ heap ปรับตาม memory limit ของ container
- Image size (arm64, ทดสอบจริง): api ~517MB (compressed ~133MB), web ~76MB (compressed ~22MB)
