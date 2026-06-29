# Jenkins Deploy Agent kết nối Rancher/K3s

Tài liệu này hướng dẫn cấu hình từ đầu để `jenkins-deploy-agent` có thể dùng `kubectl` và `helm` deploy ứng dụng vào namespace `staging` trên K3s.

> Rancher chỉ là giao diện quản lý cluster. Jenkins Deploy Agent kết nối trực tiếp tới Kubernetes API của K3s qua cổng `6443`.

---

## 1. Kiến trúc

```text
VPS DEVOPS
├── Jenkins Controller
├── jenkins-build-agent
│   └── Docker DinD: build và push Docker image
└── jenkins-deploy-agent
    ├── kubectl
    ├── helm
    └── kubeconfig Jenkins Secret File
             │
             ▼
VPS APP: 139.59.125.131
└── K3s API: https://139.59.125.131:6443
    └── namespace staging
```

Trong tài liệu này:

```text
K3s Server IP: 139.59.125.131
K3s API Port: 6443
Namespace: staging
ServiceAccount: jenkins-deployer
Role: jenkins-deployer-role
RoleBinding: jenkins-deployer-binding
Token Secret: jenkins-deployer-token
Jenkins Credential ID: k3s-staging-kubeconfig
Jenkins Agent Label: deploy-agent
```

---

## 2. Kiểm tra Jenkins Deploy Agent

Thực hiện trên VPS Jenkins:

```bash
cd /home/Devops/Jenkins

docker compose ps

docker exec jenkins-deploy-agent kubectl version --client
docker exec jenkins-deploy-agent helm version
```

Nếu agent chưa chạy:

```bash
docker compose up -d --build jenkins-deploy-agent
docker logs --tail=100 jenkins-deploy-agent
```

Cần bảo đảm:

- `jenkins-deploy-agent` đang chạy.
- Agent đã Online trên Jenkins.
- Container có `kubectl`.
- Container có `helm`.

---

## 3. Mở Kubectl Shell trên Rancher

Trên giao diện Rancher:

```text
Cluster Management
→ Chọn cluster K3s
→ Explore
→ Kubectl Shell
```

Kiểm tra cluster:

```bash
kubectl get nodes
kubectl get namespaces
```

---

## 4. Tạo Namespace và quyền cho Jenkins

Chạy toàn bộ khối sau trong Rancher Kubectl Shell hoặc trên VPS K3s.

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: staging

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-deployer
  namespace: staging
automountServiceAccountToken: false

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins-deployer-role
  namespace: staging
rules:
  # Rule 1: Core API group
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - configmaps
      - secrets
      - persistentvolumeclaims
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete

  # Rule 2: Apps API group
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
      - statefulsets
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete

  # Rule 3: Networking API group
  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
      - networkpolicies
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-deployer-binding
  namespace: staging
subjects:
  - kind: ServiceAccount
    name: jenkins-deployer
    namespace: staging
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: jenkins-deployer-role

---
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-deployer-token
  namespace: staging
  annotations:
    kubernetes.io/service-account.name: jenkins-deployer
type: kubernetes.io/service-account-token
EOF
```

### Ý nghĩa ba rule trong Role

| Rule | `apiGroups` | Tài nguyên chính |
|---|---|---|
| 1 | `[""]` | Pod, Service, ConfigMap, Secret, PVC |
| 2 | `["apps"]` | Deployment, ReplicaSet, StatefulSet |
| 3 | `["networking.k8s.io"]` | Ingress, NetworkPolicy |

`apiGroups: [""]` là Core API Group, không có nghĩa là tất cả API group.

---

## 5. Kiểm tra tài nguyên vừa tạo

```bash
kubectl get serviceaccount jenkins-deployer -n staging

kubectl get role jenkins-deployer-role -n staging

kubectl get rolebinding jenkins-deployer-binding -n staging

kubectl get secret jenkins-deployer-token -n staging
```

Kết quả Secret cần có dạng:

```text
NAME                     TYPE                                  DATA
jenkins-deployer-token   kubernetes.io/service-account-token   3
```

Con số `DATA = 3` của Secret gồm:

```text
ca.crt
namespace
token
```

Kiểm tra mà không in token:

```bash
kubectl describe secret jenkins-deployer-token -n staging
```

Có thể thấy ServiceAccount hiển thị `SECRETS = 0`. Điều này không nhất thiết là lỗi khi token Secret được tạo thủ công. Hãy kiểm tra trực tiếp Secret `jenkins-deployer-token`.

---

## 6. Kiểm tra quyền RBAC

```bash
JENKINS_SUBJECT="system:serviceaccount:staging:jenkins-deployer"
```

Kiểm tra Pod:

```bash
kubectl auth can-i get pods \
  -n staging \
  --as="$JENKINS_SUBJECT"
```

Kiểm tra Deployment:

```bash
kubectl auth can-i patch deployments.apps \
  -n staging \
  --as="$JENKINS_SUBJECT"
```

Kiểm tra Ingress:

```bash
kubectl auth can-i create ingresses.networking.k8s.io \
  -n staging \
  --as="$JENKINS_SUBJECT"
```

Kiểm tra Secret cho Helm:

```bash
kubectl auth can-i create secrets \
  -n staging \
  --as="$JENKINS_SUBJECT"
```

Các lệnh trên cần trả về:

```text
yes
```

Kiểm tra Jenkins không có quyền ở namespace hệ thống:

```bash
kubectl auth can-i get pods \
  -n kube-system \
  --as="$JENKINS_SUBJECT"
```

Kết quả mong muốn:

```text
no
```

---

## 7. Kiểm tra K3s API Server

IP `139.59.125.131` phải là IP của VPS đang chạy K3s Server, không phải IP Jenkins hoặc Rancher UI.

Trên VPS K3s:

```bash
sudo systemctl status k3s
sudo ss -lntp | grep 6443
hostname -I
```

API endpoint:

```text
https://139.59.125.131:6443
```

---

## 8. Mở firewall cho VPS Jenkins

Trên VPS K3s, chỉ cho phép IP của VPS Jenkins truy cập cổng `6443`.

```bash
sudo ufw allow from <IP_PUBLIC_VPS_JENKINS> to any port 6443 proto tcp
sudo ufw status
```

Ví dụ:

```bash
sudo ufw allow from 123.30.50.60 to any port 6443 proto tcp
```

Không nên mở cổng cho toàn Internet:

```bash
# Không khuyến nghị
sudo ufw allow 6443/tcp
```

---

## 9. Kiểm tra kết nối từ VPS Jenkins

Chạy trên VPS Jenkins:

```bash
curl -k https://139.59.125.131:6443/version
```

Các kết quả sau chứng minh kết nối mạng đã thông:

- JSON chứa Kubernetes version.
- `401 Unauthorized`.
- `403 Forbidden`.

Nếu bị timeout:

```text
Connection timed out
```

Kiểm tra:

- UFW trên VPS K3s.
- Cloud firewall/security group.
- IP VPS Jenkins có đúng không.
- K3s có lắng nghe trên `6443` không.

Nếu bị refused:

```text
Connection refused
```

Kiểm tra trên VPS K3s:

```bash
sudo systemctl status k3s
sudo ss -lntp | grep 6443
```

---

## 10. Tạo kubeconfig riêng cho Jenkins

Thực hiện trên VPS K3s.

```bash
NAMESPACE="staging"
SERVICE_ACCOUNT="jenkins-deployer"
TOKEN_SECRET="jenkins-deployer-token"
K3S_API_SERVER="https://139.59.125.131:6443"
```

Lấy token:

```bash
TOKEN_B64="$(
  sudo k3s kubectl get secret "$TOKEN_SECRET" \
    -n "$NAMESPACE" \
    -o jsonpath='{.data.token}'
)"

TOKEN="$(
  printf '%s' "$TOKEN_B64" | base64 -d
)"
```

Lấy CA certificate:

```bash
CA_DATA="$(
  sudo k3s kubectl get secret "$TOKEN_SECRET" \
    -n "$NAMESPACE" \
    -o jsonpath='{.data.ca\.crt}'
)"
```

Kiểm tra biến có dữ liệu, không in token:

```bash
test -n "$TOKEN" && echo "Token: OK" || echo "Token: EMPTY"
test -n "$CA_DATA" && echo "CA: OK" || echo "CA: EMPTY"
```

Tạo kubeconfig:

```bash
umask 077

cat > /root/k3s-staging-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config

clusters:
  - name: k3s-staging
    cluster:
      server: ${K3S_API_SERVER}
      certificate-authority-data: ${CA_DATA}

users:
  - name: jenkins-deployer
    user:
      token: ${TOKEN}

contexts:
  - name: k3s-staging
    context:
      cluster: k3s-staging
      user: jenkins-deployer
      namespace: staging

current-context: k3s-staging
EOF

chmod 600 /root/k3s-staging-kubeconfig.yaml
```

Không đăng nội dung file kubeconfig lên GitHub, log hoặc chat vì file chứa token.

Kiểm tra file nhưng ẩn token:

```bash
sed 's/token:.*/token: REDACTED/' \
  /root/k3s-staging-kubeconfig.yaml
```

---

## 11. Kiểm tra kubeconfig

Trên VPS K3s:

```bash
sudo k3s kubectl \
  --kubeconfig /root/k3s-staging-kubeconfig.yaml \
  config current-context
```

Kết quả:

```text
k3s-staging
```

Kiểm tra quyền:

```bash
sudo k3s kubectl \
  --kubeconfig /root/k3s-staging-kubeconfig.yaml \
  auth can-i get pods \
  -n staging
```

Kết quả:

```text
yes
```

Kiểm tra tài nguyên:

```bash
sudo k3s kubectl \
  --kubeconfig /root/k3s-staging-kubeconfig.yaml \
  get pods \
  -n staging
```

Nếu chưa có workload:

```text
No resources found in staging namespace.
```

Đây vẫn là kết quả hợp lệ.

---

## 12. Sửa lỗi TLS SAN nếu có

Nếu gặp:

```text
x509: certificate is valid for ..., not 139.59.125.131
```

Mở file K3s config:

```bash
sudo nano /etc/rancher/k3s/config.yaml
```

Thêm IP vào `tls-san`:

```yaml
tls-san:
  - "139.59.125.131"
```

Nếu file đã có cấu hình khác, giữ nguyên cấu hình cũ và chỉ bổ sung `tls-san`.

Khởi động lại K3s:

```bash
sudo systemctl restart k3s
sudo systemctl status k3s
```

Không nên dùng lâu dài:

```yaml
insecure-skip-tls-verify: true
```

---

## 13. Copy kubeconfig sang Jenkins

Từ VPS Jenkins:

```bash
scp root@139.59.125.131:/root/k3s-staging-kubeconfig.yaml \
  /root/k3s-staging-kubeconfig.yaml
```

Sau khi upload kubeconfig lên Jenkins Credentials thành công, xóa file tạm trên VPS Jenkins:

```bash
rm -f /root/k3s-staging-kubeconfig.yaml
```

---

## 14. Tạo Jenkins Secret File Credential

Trong Jenkins:

```text
Manage Jenkins
→ Credentials
→ System
→ Global credentials
→ Add Credentials
```

Cấu hình:

```text
Kind: Secret file
File: k3s-staging-kubeconfig.yaml
ID: k3s-staging-kubeconfig
Description: K3s staging kubeconfig for Jenkins deploy agent
```

Không sử dụng:

- Username/Password.
- Secret text cho cả kubeconfig.
- Kubeconfig admin `/etc/rancher/k3s/k3s.yaml`.

---

## 15. Cấu hình Jenkins Deploy Node

Trong Jenkins:

```text
Manage Jenkins
→ Nodes
→ jenkins-deploy-agent
→ Configure
```

Cấu hình khuyến nghị:

```text
Number of executors: 1
Remote root directory: /home/jenkins/agent
Labels: deploy-agent
Usage: Only build jobs with label expressions matching this node
```

Docker Compose hiện tại:

```yaml
jenkins-deploy-agent:
  build:
    context: ./jenkins-agents/deploy
    dockerfile: Dockerfile
    args:
      KUBECTL_VERSION: ${KUBECTL_VERSION:?KUBECTL_VERSION is required}
      HELM_VERSION: ${HELM_VERSION:?HELM_VERSION is required}

  container_name: jenkins-deploy-agent
  restart: unless-stopped
  init: true

  environment:
    JENKINS_URL: http://jenkins-controller:8080
    JENKINS_AGENT_NAME: ${JENKINS_DEPLOY_AGENT_NAME:?JENKINS_DEPLOY_AGENT_NAME is required}
    JENKINS_SECRET: ${JENKINS_DEPLOY_AGENT_SECRET:?JENKINS_DEPLOY_AGENT_SECRET is required}
    JENKINS_AGENT_WORKDIR: /home/jenkins/agent
    JENKINS_WEB_SOCKET: "true"

  volumes:
    - jenkins-deploy-workspace:/home/jenkins/agent

  depends_on:
    jenkins-controller:
      condition: service_started

  networks:
    - jenkins_network
```

Không cần mount kubeconfig trong Docker Compose. Jenkins sẽ cấp file tạm qua Credentials Binding.

---

## 16. Jenkins Pipeline kiểm tra kết nối

```groovy
pipeline {
    agent none

    stages {
        stage('Test K3s Connection') {
            agent {
                label 'deploy-agent'
            }

            steps {
                withCredentials([
                    file(
                        credentialsId: 'k3s-staging-kubeconfig',
                        variable: 'KUBECONFIG'
                    )
                ]) {
                    sh '''
                        set -eu
                        set +x

                        echo "=== Tools ==="
                        kubectl version --client
                        helm version

                        echo "=== Kubernetes context ==="
                        kubectl config current-context

                        echo "=== Permissions ==="
                        kubectl auth can-i get pods -n staging
                        kubectl auth can-i patch deployments.apps -n staging
                        kubectl auth can-i create ingresses.networking.k8s.io -n staging
                        kubectl auth can-i create secrets -n staging

                        echo "=== Resources ==="
                        kubectl get pods -n staging
                        kubectl get deployments -n staging
                        kubectl get services -n staging
                        kubectl get ingresses -n staging

                        echo "=== Helm releases ==="
                        helm list -n staging
                    '''
                }
            }
        }
    }
}
```

Kết quả mong muốn:

```text
k3s-staging
yes
yes
yes
yes
```

---

## 17. Pipeline deploy bằng kubectl

Ví dụ deploy backend:

```groovy
stage('Deploy Backend') {
    agent {
        label 'deploy-agent'
    }

    steps {
        withCredentials([
            file(
                credentialsId: 'k3s-staging-kubeconfig',
                variable: 'KUBECONFIG'
            )
        ]) {
            sh '''
                set -eu
                set +x

                kubectl set image \
                    deployment/backend-deployment \
                    backend=davidnguyendev/backend:${IMAGE_TAG} \
                    -n staging

                kubectl rollout status \
                    deployment/backend-deployment \
                    -n staging \
                    --timeout=300s
            '''
        }
    }
}
```

Kiểm tra tên container trong Deployment:

```bash
kubectl get deployment backend-deployment \
  -n staging \
  -o jsonpath='{.spec.template.spec.containers[*].name}{"\n"}'
```

Trong ví dụ:

```text
Deployment name: backend-deployment
Container name: backend
Docker image: davidnguyendev/backend:${IMAGE_TAG}
```

---

## 18. Pipeline deploy bằng Helm

```groovy
stage('Deploy with Helm') {
    agent {
        label 'deploy-agent'
    }

    steps {
        withCredentials([
            file(
                credentialsId: 'k3s-staging-kubeconfig',
                variable: 'KUBECONFIG'
            )
        ]) {
            sh '''
                set -eu
                set +x

                helm upgrade --install backend ./helm/backend \
                    --namespace staging \
                    --set image.repository=davidnguyendev/backend \
                    --set image.tag="${IMAGE_TAG}" \
                    --wait \
                    --timeout 5m
            '''
        }
    }
}
```

Không dùng:

```bash
--create-namespace
```

vì Jenkins chỉ có quyền trong namespace `staging`, không có quyền tạo namespace toàn cluster.

---

## 19. Các lệnh kiểm tra nhanh

### Trên VPS K3s

```bash
sudo systemctl status k3s
sudo ss -lntp | grep 6443

sudo k3s kubectl get nodes
sudo k3s kubectl get all -n staging

sudo k3s kubectl get serviceaccount -n staging
sudo k3s kubectl get role -n staging
sudo k3s kubectl get rolebinding -n staging
sudo k3s kubectl get secret jenkins-deployer-token -n staging
```

### Trên VPS Jenkins

```bash
docker compose ps

docker logs --tail=100 jenkins-deploy-agent

docker exec jenkins-deploy-agent kubectl version --client
docker exec jenkins-deploy-agent helm version

curl -k https://139.59.125.131:6443/version
```

---

## 20. Xử lý lỗi thường gặp

### `Forbidden`

Ví dụ:

```text
deployments.apps is forbidden
```

Kiểm tra quyền:

```bash
kubectl auth can-i patch deployments.apps \
  -n staging \
  --as=system:serviceaccount:staging:jenkins-deployer
```

Nếu trả về `no`, kiểm tra Role và RoleBinding:

```bash
kubectl get role jenkins-deployer-role -n staging -o yaml
kubectl get rolebinding jenkins-deployer-binding -n staging -o yaml
```

---

### `Unauthorized`

Nguyên nhân thường gặp:

- Token sai.
- Token Secret chưa có dữ liệu.
- Kubeconfig dùng sai token.
- Secret token đã bị xóa và tạo lại.

Kiểm tra:

```bash
kubectl get secret jenkins-deployer-token -n staging
kubectl describe secret jenkins-deployer-token -n staging
```

Sau khi tạo lại token Secret, cần tạo lại kubeconfig và cập nhật Jenkins Credential.

---

### `Unable to connect to the server`

Kiểm tra:

```bash
curl -k https://139.59.125.131:6443/version
```

Sau đó kiểm tra:

```bash
sudo systemctl status k3s
sudo ss -lntp | grep 6443
sudo ufw status
```

---

### `x509 certificate error`

Thêm IP vào:

```text
/etc/rancher/k3s/config.yaml
```

```yaml
tls-san:
  - "139.59.125.131"
```

Sau đó:

```bash
sudo systemctl restart k3s
```

---

### Jenkins báo không tìm thấy Credential

Kiểm tra ID trong Jenkins:

```text
k3s-staging-kubeconfig
```

ID trong Jenkinsfile phải giống hoàn toàn:

```groovy
credentialsId: 'k3s-staging-kubeconfig'
```

---

### Pipeline chạy nhầm build agent

Stage deploy phải có:

```groovy
agent {
    label 'deploy-agent'
}
```

Node `jenkins-deploy-agent` phải có label:

```text
deploy-agent
```

---

## 21. Quy tắc bảo mật

Không thực hiện các việc sau:

```text
Không commit kubeconfig vào Git.
Không ghi token trong Jenkinsfile.
Không ghi token trong docker-compose.yml.
Không ghi token trong .env.
Không in toàn bộ kubeconfig ra Jenkins log.
Không dùng kubeconfig admin của K3s.
Không cấp cluster-admin cho jenkins-deployer.
Không mở cổng 6443 cho toàn Internet.
```

Nên thực hiện:

```text
Chỉ cấp Role trong namespace staging.
Đặt deploy agent có 1 executor.
Lưu kubeconfig dưới dạng Jenkins Secret File.
Chỉ mở 6443 cho IP VPS Jenkins.
Xoay token định kỳ.
Tách build agent và deploy agent.
```

---

## 22. Xóa toàn bộ cấu hình Jenkins trên K3s

Chỉ chạy khi muốn làm lại từ đầu:

```bash
kubectl delete rolebinding jenkins-deployer-binding -n staging
kubectl delete role jenkins-deployer-role -n staging
kubectl delete secret jenkins-deployer-token -n staging
kubectl delete serviceaccount jenkins-deployer -n staging
```

Không xóa namespace `staging` nếu bên trong còn ứng dụng hoặc dữ liệu.

Nếu chắc chắn muốn xóa toàn bộ namespace:

```bash
kubectl delete namespace staging
```

Lệnh này sẽ xóa tất cả Deployment, Service, Secret, PVC và tài nguyên khác trong namespace.

---

## 23. Checklist hoàn thành

- [ ] `jenkins-deploy-agent` đang Online.
- [ ] Agent có `kubectl`.
- [ ] Agent có `helm`.
- [ ] Namespace `staging` tồn tại.
- [ ] ServiceAccount `jenkins-deployer` tồn tại.
- [ ] Role `jenkins-deployer-role` tồn tại.
- [ ] RoleBinding `jenkins-deployer-binding` tồn tại.
- [ ] Secret `jenkins-deployer-token` có `DATA = 3`.
- [ ] `kubectl auth can-i` trả về `yes`.
- [ ] VPS Jenkins kết nối được `139.59.125.131:6443`.
- [ ] Kubeconfig sử dụng ServiceAccount token.
- [ ] Jenkins Credential ID là `k3s-staging-kubeconfig`.
- [ ] Deploy stage chạy trên label `deploy-agent`.
- [ ] Pipeline test đọc được tài nguyên namespace `staging`.
- [ ] Pipeline deploy cập nhật được Deployment.
