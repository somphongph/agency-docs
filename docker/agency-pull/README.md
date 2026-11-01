# agency-pull — run prebuilt images (demo 2 versions)

รัน **image ที่ build ไว้แล้ว** (ไม่ build ตอน start) เพื่อเดโม/เทียบ 2 เวอร์ชัน:

| tag | มาจาก branch | พฤติกรรม |
|---|---|---|
| `develop` | `develop` | โค้ดเก่า: web **polling ทุก 5 วิ**, API มีแค่ `GET /api/v1/dashboard` (ไม่มี `/api/v1/health`, ไม่มี SSE) |
| `sse` | `feature/sse` | web ต่อ **SSE**, API มี `/api/v1/health`, `/api/v1/dashboard/stream`, `POST /refresh` (+ metrics) |

```
agency-pull/
├─ docker-compose.yml   # image: agency-api:${API_TAG} / agency-web:${WEB_TAG}
└─ .env.example         # (optional) ใช้สลับ version
```

## Build image ทั้ง 2 เวอร์ชัน (ครั้งเดียว)

```bash
cd agency-docs/docker
make build-versions
```

script `scripts/build-versions.sh` จะ `git archive` จาก ref แล้ว `docker build` — **ไม่ต้องสลับ branch**
ได้ผลลัพธ์:
```
agency-api:develop  agency-web:develop
agency-api:sse      agency-web:sse
```
(เปลี่ยน ref/tag เองได้: `./scripts/build-versions.sh develop:dev main:main`)

## รัน / สลับเวอร์ชัน

```bash
cd agency-docs/docker

make pull                            # = develop (ค่า default)
API_TAG=sse WEB_TAG=sse make pull    # = feature/sse
make pull-ps
make pull-logs
make pull-down
```

หรือใช้ `.env` ใน `agency-pull/`:
```bash
cp agency-pull/.env.example agency-pull/.env
# แก้ API_TAG=sse / WEB_TAG=sse
make pull
```

| Service | Host port | develop | sse |
|---|---|---|---|
| web | **4201** | http://localhost:4201 | http://localhost:4201 |
| api | **8081** | `/api/v1/dashboard` = 200 | `/api/v1/health` = 200, `/api/v1/dashboard/stream` = SSE |

> ใช้ 4201/8081 เพื่อให้รันคู่กับ `agency-stack` (4200/8080) ได้พร้อมกัน → เดโม "เก่า vs ใหม่" บนจอเดียว

## เดโมเทียบ 2 เวอร์ชันพร้อมกัน

```bash
# เวอร์ชันใหม่อยู่บน 4200 (build จาก branch ที่ checkout อยู่ เช่น feature/sse)
git -C ../../agency-api switch feature/sse
git -C ../../agency-web switch feature/sse
make up

# เวอร์ชันเก่าอยู่บน 4201 (image ที่ build ไว้)
make pull        # API_TAG=develop (default)
```

| ดูอะไร | 4200 (sse) | 4201 (develop) |
|---|---|---|
| หน้าจอ | อัปเดตทันทีผ่าน SSE | refresh ทุก 5 วิ (polling) |
| `GET /api/v1/health` | 200 | **404** |
| `GET /api/v1/dashboard/stream` | stream ได้ | **404** |
| ปุ่ม/กลไก refresh | `POST /api/v1/dashboard/refresh` | ไม่มี (GET สุ่มใหม่ทุกครั้ง) |

## หมายเหตุ

- compose นี้ **ไม่ pull จาก registry** — ต้องมี image ในเครื่องก่อน (`make build-versions` หรือ `docker build` เอง)
- healthcheck ของ api ใช้ `/api/v1/dashboard` เพราะ `develop` ไม่มี `/api/v1/health`
- `SPRING_PROFILES_ACTIVE=prod` (default) ปิด Swagger; ตั้งเป็น `dev` ถ้าอยากเปิด
- image `develop` ไม่ได้อ่าน `API_HOST` (nginx.conf hardcode `http://api:8080`) — ค่า env ที่ส่งไปจึงไม่มีผล
