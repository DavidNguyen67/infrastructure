# K3s Kubernetes

Triển khai K3s một node, cài NGINX Ingress Controller và dùng các manifest trong thư mục này để deploy ứng dụng. K3s được ghim ở phiên bản `v1.30.6+k3s1`; Traefik mặc định bị tắt để tránh trùng ingress controller.

## Yêu cầu

- Máy chủ Linux 64-bit, khuyến nghị tối thiểu 2 vCPU, 4 GB RAM và quyền `root`/`sudo`.
- Mở các cổng `6443/TCP` (Kubernetes API, khi cần truy cập từ ngoài), `30080/TCP` và `30443/TCP` (Ingress HTTP/HTTPS).
- Máy quản trị có `kubectl`; trên K3s server, lệnh này đã được cài kèm.

> Các manifest trong repo là template. Không commit Secret thật vào Git; dùng biến môi trường hoặc secret manager khi triển khai production.

## Các file chính

| File | Mục đích |
| --- | --- |
| `00-project.yaml` | Template đầy đủ: Namespace, ConfigMap, Secret, Deployment, Service, Ingress và HPA. |
| `01-namespace.yaml` đến `12-statefullset.yaml` | Các manifest tách riêng để tham khảo hoặc áp dụng từng resource. |
| `ingress-controller.sh` | Cài NGINX Ingress Controller qua Helm với NodePort `30080`/`30443`. |
| `backend.yaml`, `frontend.yaml` | Manifest mẫu cho backend và frontend. |
| `values/` | Helm values cho PostgreSQL, Redis và monitoring. |

## Cài K3s lần đầu

1. Cài K3s và tắt Traefik mặc định:

   ```bash
   curl -sfL https://get.k3s.io | \
     INSTALL_K3S_VERSION='v1.30.6+k3s1' sh -s - server --disable traefik
   ```

2. Kiểm tra node và hệ thống pod:

   ```bash
   sudo kubectl get nodes
   sudo kubectl get pods -A
   ```

3. Để dùng `kubectl` không cần `sudo`, sao chép kubeconfig cho người dùng hiện tại:

   ```bash
   mkdir -p ~/.kube
   sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
   sudo chown "$(id -u):$(id -g)" ~/.kube/config
   chmod 600 ~/.kube/config
   kubectl get nodes
   ```

4. Nếu quản trị từ máy khác, sao chép `/etc/rancher/k3s/k3s.yaml` sang máy đó và thay `127.0.0.1` trong trường `server` bằng IP hoặc DNS của K3s server. Kubeconfig này có quyền quản trị cluster, không chia sẻ công khai.

## Cài NGINX Ingress Controller

1. Cài Helm nếu máy chưa có, rồi thêm Helm repository:

   ```bash
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
   helm repo update
   ```

2. Chạy script trong thư mục này:

   ```bash
   bash ingress-controller.sh
   kubectl get pods -n ingress-nginx
   kubectl get svc -n ingress-nginx
   ```

   Controller được expose qua `http://<NODE_IP>:30080` và `https://<NODE_IP>:30443`. Cấu hình DNS của domain ứng dụng trỏ về IP node hoặc load balancer phía trước node.

## Lệnh vận hành thường dùng

```bash
# Xem tài nguyên toàn cluster
kubectl get nodes
kubectl get pods -A

# Theo dõi log và mô tả pod
kubectl logs -n <NAMESPACE> <POD_NAME> -f
kubectl describe pod -n <NAMESPACE> <POD_NAME>

# Kiểm tra Service có endpoint hay không
kubectl get endpoints -n <NAMESPACE>

# Xem trạng thái ingress và HPA
kubectl describe ingress -n <NAMESPACE> <APP_NAME>-ingress
kubectl describe hpa -n <NAMESPACE> <APP_NAME>-hpa
```

## Khắc phục nhanh

| Hiện tượng | Cách kiểm tra / xử lý |
| --- | --- |
| `kubectl` bị `connection refused` | Kiểm tra dịch vụ: `sudo systemctl status k3s`; xem log: `sudo journalctl -u k3s -f`. |
| Ingress trả `503` | Kiểm tra `kubectl get endpoints -n <NAMESPACE>`; selector Service phải khớp label Pod, Pod phải `Ready`, và `targetPort` phải đúng port ứng dụng. |
| Domain không truy cập được | Kiểm tra DNS, firewall các cổng `30080`/`30443`, rồi kiểm tra `kubectl get svc -n ingress-nginx`. |
| HPA hiện `<unknown>` | Kiểm tra `kubectl top pods -n <NAMESPACE>` và đảm bảo Deployment có `resources.requests.cpu`. |
| Pod `CrashLoopBackOff` | Xem `kubectl logs -n <NAMESPACE> <POD_NAME> --previous`; thường do image, biến môi trường/Secret, port hoặc resource limit. |

## Dữ liệu và lưu ý

- K3s lưu dữ liệu cluster mặc định tại `/var/lib/rancher/k3s`. Sao lưu dữ liệu trước khi nâng cấp hoặc gỡ K3s.
- Lệnh gỡ K3s là `sudo /usr/local/bin/k3s-uninstall.sh`; thao tác này xóa cluster và dữ liệu liên quan trên node, không thể hoàn tác.

## Template ứng dụng

### Versions

- Rancher: v2.9.3
- K3s: v1.30.6+k3s1

### Kubernetes App Template

Template này dùng để deploy một ứng dụng lên Kubernetes/Rancher, bao gồm:

- Namespace
- Deployment
- Service
- Ingress
- HorizontalPodAutoscaler (HPA)
- Resource request/limit
- Readiness probe
- Startup probe

## 1. Các giá trị cần thay

| Placeholder                | Ý nghĩa                        | Ví dụ                              |
| -------------------------- | ------------------------------ | ---------------------------------- |
| `<NAMESPACE>`              | Namespace của app              | `car-serv`                         |
| `<APP_NAME>`               | Tên app                        | `car-serv`                         |
| `<IMAGE>`                  | Docker image                   | `elroydevops/car-serv:latest`      |
| `<REPLICAS>`               | Số lượng pod                   | `2`                                |
| `<CONTAINER_PORT>`         | Port app chạy trong container  | `80`, `3000`, `8080`               |
| `<SERVICE_PORT>`           | Port service expose nội bộ     | `80`                               |
| `<DOMAIN>`                 | Domain trỏ vào app             | `car-serv-onpre.devopsedu.vn`      |
| `<HEALTH_CHECK_PATH>`      | Path kiểm tra app còn sống     | `/`, `/health`, `/actuator/health` |
| `<REQUEST_CPU>`            | CPU tối thiểu pod cần          | `100m`                             |
| `<REQUEST_MEMORY>`         | RAM tối thiểu pod cần          | `128Mi`                            |
| `<LIMIT_CPU>`              | CPU tối đa pod được dùng       | `500m`                             |
| `<LIMIT_MEMORY>`           | RAM tối đa pod được dùng       | `512Mi`                            |
| `<MIN_REPLICAS>`           | Số pod tối thiểu khi autoscale | `2`                                |
| `<MAX_REPLICAS>`           | Số pod tối đa khi autoscale    | `5`                                |
| `<CPU_TARGET_UTILIZATION>` | CPU target để HPA scale pod    | `70`                               |

---

## 2. Ví dụ cấu hình cho app `car-serv`

| Placeholder                | Giá trị                       |
| -------------------------- | ----------------------------- |
| `<NAMESPACE>`              | `car-serv`                    |
| `<APP_NAME>`               | `car-serv`                    |
| `<IMAGE>`                  | `elroydevops/car-serv:latest` |
| `<REPLICAS>`               | `2`                           |
| `<CONTAINER_PORT>`         | `8080`                        |
| `<SERVICE_PORT>`           | `80`                          |
| `<DOMAIN>`                 | `car-serv-onpre.devopsedu.vn` |
| `<HEALTH_CHECK_PATH>`      | `/`                           |
| `<REQUEST_CPU>`            | `100m`                        |
| `<REQUEST_MEMORY>`         | `128Mi`                       |
| `<LIMIT_CPU>`              | `500m`                        |
| `<LIMIT_MEMORY>`           | `512Mi`                       |
| `<MIN_REPLICAS>`           | `2`                           |
| `<MAX_REPLICAS>`           | `5`                           |
| `<CPU_TARGET_UTILIZATION>` | `70`                          |

---

## 3. Cách dùng với `kubectl`

Sau khi thay toàn bộ placeholder trong file YAML, chạy:

```bash
kubectl apply -f app-template.yaml
```

Kiểm tra namespace:

```bash
kubectl get ns
```

Kiểm tra pod:

```bash
kubectl get pods -n <NAMESPACE>
```

Kiểm tra service:

```bash
kubectl get svc -n <NAMESPACE>
```

Kiểm tra ingress:

```bash
kubectl get ingress -n <NAMESPACE>
```

Kiểm tra HPA:

```bash
kubectl get hpa -n <NAMESPACE>
```

Ví dụ:

```bash
kubectl get pods -n car-serv
kubectl get svc -n car-serv
kubectl get ingress -n car-serv
kubectl get hpa -n car-serv
```

---

## 4. Cách dùng trên Rancher

Vào Rancher UI:

```text
Cluster → Projects/Namespaces → Import YAML
```

Sau đó paste toàn bộ nội dung file YAML đã thay placeholder vào và bấm:

```text
Create / Apply
```

---

## 5. Luồng request sau khi deploy

```text
Client
  ↓
Domain: <DOMAIN>
  ↓
Load Balancer / Nginx VPS
  ↓
Ingress Controller
  ↓
Ingress rule
  ↓
Service
  ↓
Pod
  ↓
Container app
```

Ví dụ:

```text
Client
  ↓
car-serv-onpre.devopsedu.vn
  ↓
Nginx Load Balancer
  ↓
Ingress Nginx Controller
  ↓
car-serv-service
  ↓
car-serv pod
  ↓
container port 8080
```

---

## 6. Lưu ý quan trọng

### Service selector phải khớp với label của Pod

Ví dụ Deployment có label:

```yaml
labels:
  app: car-serv
```

Thì Service phải selector đúng:

```yaml
selector:
  app: car-serv
```

Nếu selector sai, Service sẽ không tìm thấy Pod, dẫn đến lỗi Ingress `503 Service Temporarily Unavailable`.

---

### `containerPort` phải đúng với port app đang chạy

Ví dụ:

- Spring Boot thường chạy port `8080`
- Next.js/Nuxt thường chạy port `3000`
- Nginx/static web thường chạy port `80`

Nếu app chạy port `8080` nhưng YAML để `3000`, Kubernetes vẫn tạo Pod được nhưng request sẽ không vào đúng app.

---

### `HEALTH_CHECK_PATH` phải tồn tại thật

Ví dụ:

Spring Boot Actuator:

```text
/actuator/health
```

Frontend web:

```text
/
```

API health custom:

```text
/health
```

Nếu path sai, Pod có thể bị trạng thái `Not Ready`.

---

### HPA cần `resources.requests.cpu`

HPA tính CPU theo phần trăm dựa trên `requests.cpu`, không phải `limits.cpu`.

Ví dụ pod có:

```yaml
resources:
  requests:
    cpu: "100m"
```

Nếu pod đang dùng trung bình `70m`, Kubernetes hiểu là đang dùng `70%` CPU request.

Công thức HPA tính số pod mong muốn:

```text
desiredReplicas = ceil(currentReplicas * currentCPUUtilization / targetCPUUtilization)
```

Ví dụ:

```text
currentReplicas = 2
currentCPUUtilization = 90
targetCPUUtilization = 60

desiredReplicas = ceil(2 * 90 / 60) = 3
```

Sau khi tính xong, Kubernetes vẫn giới hạn kết quả trong khoảng:

```text
<MIN_REPLICAS> <= desiredReplicas <= <MAX_REPLICAS>
```

Nếu `minReplicas = 2`, `maxReplicas = 5`, HPA sẽ không scale xuống dưới `2` pod và không scale vượt quá `5` pod.

---

## 7. Một số lệnh debug hay dùng

Xem log Pod:

```bash
kubectl logs -n <NAMESPACE> <POD_NAME>
```

Xem chi tiết Pod:

```bash
kubectl describe pod -n <NAMESPACE> <POD_NAME>
```

Xem endpoint của Service:

```bash
kubectl get endpoints -n <NAMESPACE>
```

Xem trạng thái HPA:

```bash
kubectl describe hpa -n <NAMESPACE> <APP_NAME>-hpa
```

Test service nội bộ trong cluster:

```bash
kubectl run curl-test -n <NAMESPACE> --image=curlimages/curl -it --rm -- sh
```

Trong container test:

```bash
curl http://<APP_NAME>-service:<SERVICE_PORT>
```

Ví dụ:

```bash
curl http://car-serv-service:80
```

---

## 8. Checklist trước khi apply

Trước khi apply YAML, kiểm tra:

- [ ] Đã thay toàn bộ placeholder `<...>`
- [ ] Namespace đúng
- [ ] Image đúng và pull được
- [ ] Container port đúng với app
- [ ] Service selector khớp với Pod label
- [ ] Ingress domain đúng
- [ ] Domain đã trỏ về Load Balancer hoặc VPS Nginx
- [ ] Health check path tồn tại
- [ ] Resource request/limit phù hợp với VPS
- [ ] HPA có min/max replicas phù hợp
- [ ] Deployment có `requests.cpu` để HPA tính CPU
- [ ] Ingress Controller đang chạy

---

## 9. Checklist sau khi apply

Sau khi deploy, kiểm tra:

```bash
kubectl get pods -n <NAMESPACE>
kubectl get svc -n <NAMESPACE>
kubectl get ingress -n <NAMESPACE>
kubectl get hpa -n <NAMESPACE>
kubectl get endpoints -n <NAMESPACE>
```

Pod cần ở trạng thái:

```text
Running
```

Service cần có endpoint.

Ingress cần có rule đúng domain.

HPA cần đọc được CPU metrics, cột `TARGETS` không bị `<unknown>`.

---

## 10. Lỗi thường gặp

### Lỗi 503 từ Ingress

Nguyên nhân thường gặp:

- Service selector sai
- Pod chưa Ready
- Sai container port
- Sai service port
- App crash
- Health check path sai

Kiểm tra bằng:

```bash
kubectl get endpoints -n <NAMESPACE>
kubectl describe ingress -n <NAMESPACE> <APP_NAME>-ingress
kubectl describe pod -n <NAMESPACE> <POD_NAME>
```

---

### Pod bị CrashLoopBackOff

Kiểm tra log:

```bash
kubectl logs -n <NAMESPACE> <POD_NAME>
```

Nguyên nhân thường gặp:

- Thiếu biến môi trường
- Không kết nối được database
- Sai port
- Image lỗi
- App start quá lâu
- RAM limit quá thấp

---

### Pod không Ready

Kiểm tra readiness probe:

```bash
kubectl describe pod -n <NAMESPACE> <POD_NAME>
```

Nguyên nhân thường gặp:

- Sai `<HEALTH_CHECK_PATH>`
- App chưa start xong
- App không listen đúng port
- Startup probe quá ngắn

---

## 11. Gợi ý đặt tên resource

Với app `<APP_NAME>`, nên đặt tên như sau:

```text
Namespace:   <NAMESPACE>
Deployment:  <APP_NAME>-deployment
Service:     <APP_NAME>-service
Ingress:     <APP_NAME>-ingress
HPA:         <APP_NAME>-hpa
ConfigMap:   <APP_NAME>-config
Secret:      <APP_NAME>-secret
```

Ví dụ với `car-serv`:

```text
Namespace:   car-serv
Deployment:  car-serv-deployment
Service:     car-serv-service
Ingress:     car-serv-ingress
HPA:         car-serv-hpa
ConfigMap:   car-serv-config
Secret:      car-serv-secret
```
