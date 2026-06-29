# Rancher Docker Compose

Chạy Rancher Server bằng Docker Compose để quản trị các Kubernetes cluster, bao gồm K3s. Stack hiện dùng Rancher `v2.9.3`, publish giao diện qua HTTP `8081` và HTTPS `8443`, đồng thời lưu dữ liệu bền vững trong volume `rancher_data`.

## Yêu cầu

- Docker Desktop hoặc Docker Engine đang chạy.
- Docker Compose v2: `docker compose version`.
- Các cổng `8081` và `8443` trên máy chưa được sử dụng.
- File `.env` có `RANCHER_BOOTSTRAP_PASSWORD`; không commit hoặc chia sẻ file này.

> Rancher container chạy với `privileged: true`. Chỉ vận hành stack trong môi trường đáng tin cậy và giới hạn quyền truy cập vào cổng quản trị.

## Các file chính

| File | Mục đích |
| --- | --- |
| `docker-compose.yml` | Khai báo Rancher Server, port mapping và volume dữ liệu. |
| `.env` | Chứa `RANCHER_BOOTSTRAP_PASSWORD`; được `.gitignore` loại trừ khỏi Git. |

## Chạy lần đầu

1. Tạo hoặc kiểm tra file `.env`:

   ```env
   RANCHER_BOOTSTRAP_PASSWORD=<mat-khau-khoi-tao-manh>
   ```

   Dùng mật khẩu dài, duy nhất. Nếu `.env` hiện có đã từng bị chia sẻ, hãy thay mật khẩu trước khi chạy Rancher.

2. Khởi động Rancher:

   ```powershell
   docker compose up -d
   docker compose ps
   docker compose logs -f rancher
   ```

3. Khi log cho thấy Rancher sẵn sàng, mở `https://localhost:8443` (hoặc `https://<HOST_IP>:8443`). Chứng chỉ tự ký có thể khiến trình duyệt hiển thị cảnh báo trong lần truy cập đầu tiên.

4. Đăng nhập bằng tài khoản `admin` và giá trị `RANCHER_BOOTSTRAP_PASSWORD`, sau đó hoàn thành phần thiết lập giao diện theo hướng dẫn Rancher.

## Import cluster K3s hiện có

1. Trong Rancher, vào **Cluster Management** → **Import Existing**.
2. Chọn **Generic**, đặt tên cluster, rồi bấm **Create**.
3. Sao chép lệnh `kubectl apply ...` Rancher cung cấp và chạy trên node/máy đã cấu hình quyền quản trị cluster K3s.
4. Chờ agent kết nối; cluster sẽ chuyển sang trạng thái **Active**. Sau đó quản lý workload qua **Cluster Explorer** hoặc `kubectl`.

> Node K3s phải truy cập được Rancher tại địa chỉ Rancher hiển thị trong lệnh import. Không dùng `localhost` nếu K3s và Rancher chạy trên các máy khác nhau; hãy dùng IP hoặc DNS mà node K3s có thể truy cập.

## Các lệnh vận hành thường dùng

```powershell
# Xem trạng thái và log
docker compose ps
docker compose logs -f rancher

# Áp dụng thay đổi compose hoặc nâng image đã cấu hình
docker compose up -d

# Mở shell trong container
docker compose exec rancher sh

# Dừng container, vẫn giữ dữ liệu Rancher
docker compose down
```

## Dữ liệu, sao lưu và nâng cấp

- Volume `rancher_data` lưu toàn bộ dữ liệu Rancher. Volume có tên cố định nên `docker compose down` không xóa dữ liệu.
- Sao lưu trước khi nâng cấp Rancher. Dừng stack trước khi sao lưu volume để tránh backup không nhất quán.
- Khi đổi phiên bản trong `docker-compose.yml`, đọc hướng dẫn nâng cấp tương ứng của Rancher, rồi chạy `docker compose pull` và `docker compose up -d`.
- Không chạy `docker compose down -v` hoặc `docker volume rm rancher_data` trừ khi muốn xóa vĩnh viễn toàn bộ cấu hình Rancher.

## Khắc phục nhanh

| Hiện tượng | Cách kiểm tra / xử lý |
| --- | --- |
| Container không khởi động | Chạy `docker compose logs rancher`; kiểm tra `.env` có `RANCHER_BOOTSTRAP_PASSWORD` và Docker đang chạy. |
| Không mở được giao diện | Kiểm tra `docker compose ps`, port `8081`/`8443` và firewall của host. Truy cập HTTPS qua `8443`. |
| Trình duyệt báo chứng chỉ không tin cậy | Đây là bình thường khi dùng chứng chỉ tự ký. Với production, đặt Rancher sau reverse proxy hoặc cấu hình chứng chỉ TLS hợp lệ. |
| Cluster import bị `Waiting` | Đảm bảo K3s có thể phân giải/kết nối đến URL Rancher và lệnh import đã được áp dụng thành công. Kiểm tra workload `cattle-system` bằng `kubectl get pods -n cattle-system`. |
