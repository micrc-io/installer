#!/bin/bash


echo "#######################################"
echo "## Start -- 开始最小化安装KubeSphere"
echo "#######################################"



function wait() {
	sleep 60
	CNT=0
	while [[ `kubectl -n kubesphere-system get pod -o name | grep ks-installer | xargs kubectl -n kubesphere-system logs --tail=20 | grep Welcome | wc -l` -eq 0 ]]; do
		CNT=`expr $CNT + 1`
		echo "等待安装...$CNT"
		sleep 5
	done
	kubectl -n kubesphere-system get pod -o name | grep ks-installer | xargs kubectl -n kubesphere-system logs --tail=50
}


echo "=============配置ectd监控============"
cat <<EOF | kubectl create -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: kubesphere-monitoring-system
EOF
kubectl -n kubesphere-monitoring-system create secret generic kube-etcd-client-certs  \
        --from-file=etcd-client-ca.crt=/etc/ssl/etcd/ssl/ca.pem  \
        --from-file=etcd-client.crt=/etc/ssl/etcd/ssl/node-master1.pem  \
        --from-file=etcd-client.key=/etc/ssl/etcd/ssl/node-master1-key.pem
echo "=================Done.================="

echo "=================安装kubesphere================="
# 包括日志，事件，监控告警（包括etcd监控），审计，服务拓扑
kubectl apply -f ./config/kubesphere-installer.yaml
kubectl apply -f ./config/kubesphere-config.yaml

echo "等待kubesphere安装..."
wait
echo "====================Done.======================="

echo "=================配置kubesphere-basic-namespace================="
# 为namespace添加label: istio-injection=disabled不允许sidecar注入, kubesphere.io/workspace=system-workspace标记为kubesphere系统空间
kubectl label namespace kube-system istio-injection=disabled
kubectl label namespace kube-system kubesphere.io/workspace=system-workspace
kubectl label namespace kube-public istio-injection=disabled
kubectl label namespace kube-public kubesphere.io/workspace=system-workspace
kubectl label namespace default istio-injection=disabled
kubectl label namespace default kubesphere.io/workspace=system-workspace
kubectl label namespace kube-node-lease istio-injection=disabled
kubectl label namespace kube-node-lease kubesphere.io/workspace=system-workspace

# 为namespace添加label: istio-injection=disabled不允许sidecar注入
kubectl label namespace kubekey-system kubesphere.io/workspace=system-workspace
kubectl label namespace kubekey-system istio-injection=disabled
kubectl label namespace kubesphere-system istio-injection=disabled
kubectl label namespace kubesphere-logging-system istio-injection=disabled
kubectl label namespace kubesphere-monitoring-system istio-injection=disabled
kubectl label namespace kubesphere-monitoring-federated istio-injection=disabled
echo "==============================Done.============================="


echo "=================安装kubesphere-devops-ci/cd================="
kubectl patch -n kubesphere-system cc ks-installer --type=json -p='[{"op": "replace", "path": "/spec/devops/enabled", "value": true}]'

echo "等待kubesphere-devops安装..."
wait

# 安装gitlab
kubectl create namespace gitlab-system
helm repo add gitlab https://charts.gitlab.io
helm repo update
helm install gitlab gitlab/gitlab --namespace gitlab-system --create-namespace --version 6.5.5 -f ./config/gitlab-values.yaml
echo "============================Done.============================"

echo "=================配置kubesphere-devops-namespace================="
kubectl label namespace kubesphere-devops-system kubesphere.io/workspace=system-workspace
kubectl label namespace kubesphere-devops-system istio-injection=disabled
kubectl label namespace kubesphere-devops-worker kubesphere.io/workspace=system-workspace
kubectl label namespace kubesphere-devops-worker istio-injection=disabled
kubectl label namespace argocd kubesphere.io/workspace=system-workspace
kubectl label namespace argocd istio-injection=disabled
kubectl label namespace gitlab-system kubesphere.io/workspace=system-workspace
kubectl label namespace gitlab-system istio-injection=disabled
echo "==============================Done.============================="


echo "=================安装kubesphere-openpitrix-应用管理================="
kubectl patch -n kubesphere-system cc ks-installer --type=json -p='[{"op": "replace", "path": "/spec/openpitrix/store/enabled", "value": true}]'

echo "等待kubesphere-openpitrix安装..."
wait
echo "=============================Done.================================"


echo "===================安装kubesphere-istio-服务治理===================="
kubectl patch -n kubesphere-system cc ks-installer --type=json -p='[{"op": "replace", "path": "/spec/servicemesh/enabled", "value": true}]'

echo "等待kubesphere-istio安装..."
wait
echo "=============================Done.================================"


echo "============================创建cert-manager========================="
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.10.0 --set installCRDs=true --set 'extraArgs={--dns01-recursive-nameservers-only,--dns01-recursive-nameservers=223.5.5.5:53\,1.1.1.1:53}'

helm install alidns-webhook ./config/alidns-webhook --namespace cert-manager --set groupName=acme.micrc.io

echo "等待cert-manager启动..."
sleep 120 # todo 修复，查看cert-manager状态以决定是否继续运行或等待
echo "=================================Done.==============================="

echo "======================配置cert-manager-namespace====================="
kubectl label namespace cert-manager kubesphere.io/workspace=system-workspace
kubectl label namespace cert-manager istio-injection=disabled
echo "================================Done.================================"


echo "===========================创建sealed-secrets========================"
kubectl apply -f ./config/sealed-secrets.yaml

echo "等待sealed-secrets-controller启动..."
sleep 120 # todo 修复，查看cert-manager状态以决定是否继续运行或等待
echo "=================================Done.================================"


echo "========================安装kubernetes-reflector====================="
helm repo add emberstack https://emberstack.github.io/helm-charts
helm repo update
helm upgrade --install reflector emberstack/reflector --namespace kube-system
echo "=================================Done.==============================="


echo "######################################"
echo "## Successful -- 安装完成."
echo "## 使用 kubectl -n kubesphere-system get pod -o name | grep ks-installer | xargs kubectl -n kubesphere-system logs 确保完成安装"
echo "######################################"