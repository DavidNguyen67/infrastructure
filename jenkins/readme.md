# Jenkins Docker Compose

Chạy Jenkins controller cùng hai inbound agent kết nối qua WebSocket:

- `jenkins-build-agent`: có Git, SSH client và Docker CLI/Buildx/Compose; build image qua Docker-in-Docker (DinD).
- `jenkins-deploy-agent`: có Git, SSH client, `kubectl` và Helm để triển khai K3s/Kubernetes.

## Yêu cầu

- Docker Desktop (hoặc Docker Engine) đang chạy.
- Docker Compose v2: `docker compose version`.
- Cổng `8080` trên máy chưa được sử dụng.

> Dịch vụ `docker-dind` cần chế độ `privileged`. Chỉ chạy stack này trong môi trường bạn tin cậy.

## Các file chính

| File | Mục đích |
| --- | --- |
| `docker-compose.yaml` | Khai báo controller, hai agent, Docker DinD, volumes và network. |
| `jenkins-agents/build/Dockerfile` | Image cho build agent: Docker CLI, Buildx, Compose, Git và SSH client. |
| `jenkins-agents/deploy/Dockerfile` | Image cho deploy agent: Kubectl, Helm, Git và SSH client. |
| `.env` | Tên/secret của từng agent, phiên bản Kubectl và Helm; không commit file này. |

## Chạy lần đầu

1. Tạo Docker volume dữ liệu Jenkins (được khai báo là `external`):

   ```powershell
   docker volume create jenkins_data
   ```

2. Mở `.env` và điền thông tin của hai node inbound agent. Compose yêu cầu tất cả biến này phải có giá trị:

   ```env
   JENKINS_BUILD_AGENT_NAME=docker-builder
   JENKINS_BUILD_AGENT_SECRET=<secret-cua-docker-builder>
   JENKINS_DEPLOY_AGENT_NAME=k3s-deployer
   JENKINS_DEPLOY_AGENT_SECRET=<secret-cua-k3s-deployer>
   KUBECTL_VERSION=v1.30.6
   HELM_VERSION=v3.21.1
   ```

   Tên node phải trùng biến `*_AGENT_NAME` tương ứng. Không commit `.env` hoặc chia sẻ các biến `*_AGENT_SECRET`.

3. Cấp quyền ghi cho Jenkins vào volume. Jenkins chạy bằng UID/GID `1000`; bước này tránh lỗi `copy_reference_file.log: Permission denied`:

   ```powershell
   docker run --rm --user root `
     -v jenkins_data:/var/jenkins_home `
     alpine:3.20 sh -c "chown -R 1000:1000 /var/jenkins_home"
   ```

4. Khởi động riêng Jenkins controller để thực hiện thiết lập ban đầu:

   ```powershell
   docker compose up -d jenkins-controller
   docker compose logs -f jenkins-controller
   ```

5. Lấy mật khẩu mở khóa ban đầu, sau đó mở `http://localhost:8080` trong trình duyệt:

   ```powershell
   docker exec jenkins-controller cat /var/jenkins_home/secrets/initialAdminPassword
   ```

   Hoàn thành wizard Jenkins, cài plugin được đề xuất và tạo tài khoản quản trị.

6. Trong Jenkins, tạo hai node inbound agent. Với mỗi node, vào **Manage Jenkins** → **Nodes** → **New Node**, chọn **Permanent Agent**, rồi cấu hình:

   | Node | Tên từ `.env` | Remote root directory | Nhãn gợi ý |
   | --- | --- | --- | --- |
   | Build | `JENKINS_BUILD_AGENT_NAME` | `/home/jenkins/agent` | `docker build` |
   | Deploy | `JENKINS_DEPLOY_AGENT_NAME` | `/home/jenkins/agent` | `k3s deploy` |

   Chọn launch method **Launch agent by connecting it to the controller**, bật **Use WebSocket** nếu có, lưu node rồi sao chép `Secret` trong lệnh kết nối của từng node.

7. Điền secret vào đúng biến trong `.env`:

   ```env
   JENKINS_BUILD_AGENT_SECRET=<secret-cua-docker-builder>
   JENKINS_DEPLOY_AGENT_SECRET=<secret-cua-k3s-deployer>
   ```

8. Build và chạy toàn bộ stack:

   ```powershell
   docker compose up -d --build
   docker compose ps
   docker compose logs -f jenkins-build-agent jenkins-deploy-agent
   ```

   Khi cả hai agent xuất hiện **online** trong Jenkins, stack đã sẵn sàng.

## Các lệnh vận hành thường dùng

```powershell
# Xem trạng thái
docker compose ps

# Theo dõi log của toàn bộ dịch vụ
docker compose logs -f

# Khởi động lại sau khi thay đổi .env hoặc cấu hình
docker compose up -d --build

# Dừng containers, vẫn giữ dữ liệu Jenkins và Docker cache
docker compose down

# Mở shell trong build hoặc deploy agent
docker compose exec jenkins-build-agent bash
docker compose exec jenkins-deploy-agent bash

# Kiểm tra Docker từ build agent
docker compose exec jenkins-build-agent docker version

# Kiểm tra công cụ deploy
docker compose exec jenkins-deploy-agent kubectl version --client=true
docker compose exec jenkins-deploy-agent helm version --short
```

## Dùng agent trong Pipeline

- Job build dùng label của build node. Agent này có Docker CLI và kết nối DinD qua TLS tại `tcp://docker-dind:2376`.
- Job deploy dùng label của deploy node. Image chỉ chứa `kubectl` và Helm, không có kubeconfig được mount từ Compose.
- Cung cấp kubeconfig/K3s credential cho pipeline qua Jenkins Credentials hoặc plugin quản lý kubeconfig; không đặt kubeconfig hoặc token cluster trong Dockerfile, Compose hay `.env`.

## Dữ liệu và lưu ý

- Các volume và network được đặt tên tường minh, không có tiền tố project: `jenkins_data`, `jenkins-docker-certs`, `jenkins-build-workspace`, `jenkins-deploy-workspace`, `jenkins-docker-data` và `jenkins_network`.
- `jenkins_data` giữ cấu hình, plugin, job và credential Jenkins. Vì là external volume, `docker compose down -v` cũng không xóa volume này.
- `jenkins-docker-data` giữ image/layer/cache của DinD; hai volume workspace được tách riêng cho build và deploy agent.
- Để làm sạch toàn bộ dữ liệu (không thể hoàn tác), dừng stack rồi xóa từng volume bằng `docker volume rm <ten-volume>`.
- Không đưa `.env` hoặc các biến `JENKINS_*_AGENT_SECRET` lên Git. Nếu secret từng bị lộ, tạo lại inbound-agent secret tương ứng trong Jenkins và cập nhật `.env`.

## Khắc phục nhanh

| Hiện tượng | Cách kiểm tra / xử lý |
| --- | --- |
| `copy_reference_file.log: Permission denied` | Chạy lệnh `chown` ở bước 3, rồi `docker compose up -d`. |
| Compose báo không có volume `jenkins_data` | Chạy `docker volume create jenkins_data`. |
| Một agent offline | Kiểm tra đúng tên node và secret `JENKINS_BUILD_AGENT_*` hoặc `JENKINS_DEPLOY_AGENT_*`, rồi xem `docker compose logs jenkins-build-agent` hoặc `docker compose logs jenkins-deploy-agent`. |
| Build agent không kết nối Docker | Chờ `jenkins-dind` healthy: `docker compose ps`; xem `docker compose logs docker-dind`. |
| Pipeline deploy không kết nối K3s | Kiểm tra Jenkins Credential/kubeconfig được pipeline sử dụng; deploy agent không được mount kubeconfig mặc định. |
| Build lỗi không tìm thấy Dockerfile/context | Kiểm tra đường dẫn `build.context` trong Compose khớp với tên thư mục Dockerfile. |
| Cổng 8080 đã dùng | Đổi phần bên trái của mapping `8080:8080` trong `docker-compose.yaml`, ví dụ `8081:8080`. |
