# OPP DevOps - Compose tách riêng

Mỗi thư mục có một `docker-compose.yml` độc lập. Mỗi Compose chỉ quản lý một container.

## Cấu trúc

```text
opp-devops-split/
├── network/
├── postgresql/
├── mongodb/
├── redis/
├── keycloak-postgresql/
└── keycloak/
```

## 1. Tạo network dùng chung

```bash
cd network
./create-networks.sh
```

## 2. Tạo file `.env`

Trong từng thư mục:

```bash
cp .env.example .env
```

Sau đó thay toàn bộ mật khẩu mẫu.

Mật khẩu của `keycloak-postgresql/.env` và `keycloak/.env` phải giống nhau ở các biến:

```env
KEYCLOAK_DB_NAME=keycloak
KEYCLOAK_DB_USERNAME=keycloak
KEYCLOAK_DB_PASSWORD=...
```

## 3. Chạy từng container

```bash
cd postgresql && docker compose up -d
cd ../mongodb && docker compose up -d
cd ../redis && docker compose up -d
cd ../keycloak-postgresql && docker compose up -d
```

Kiểm tra database Keycloak đã healthy:

```bash
docker ps --filter name=opp-keycloak-postgresql
```

Sau đó chạy Keycloak:

```bash
cd ../keycloak
docker compose up -d
```

## 4. Kiểm tra

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

## Địa chỉ kết nối trong Docker network

- PostgreSQL ứng dụng: `opp-postgresql:5432`
- MongoDB: `opp-mongodb:27017`
- Redis: `opp-redis:6379`
- PostgreSQL của Keycloak: `opp-keycloak-postgresql:5432`
- Keycloak: `opp-keycloak:8080`

Backend chạy bằng Docker cần tham gia `opp-database-network` để truy cập database và `opp-auth-network` để truy cập Keycloak.

## Dừng từng container

Ví dụ:

```bash
cd redis
docker compose down
```

Không thêm `-v` nếu muốn giữ dữ liệu.

## Lưu ý production

Compose Keycloak đang dùng `start-dev` để triển khai ban đầu. Trước khi chạy production, đổi sang `start`, cấu hình hostname HTTPS và reverse proxy phù hợp.
