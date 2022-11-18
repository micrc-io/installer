#!/bin/bash

./kk create cluster --with-kubernetes v1.22.10 --with-local-storage -f ./config/kubernetes-config.yaml -y


echo "=============修改kube-proxy配置mode: "ipvs"和strictARP: true============="
kubectl get configmap kube-proxy -n kube-system -o yaml | \
        sed -e 's/mode: ""/mode: "ipvs"/' | \
        sed -e "s/strictARP: false/strictARP: true/" | \
        kubectl diff -f - -n kube-system
kubectl get configmap kube-proxy -n kube-system -o yaml | \
	sed -e 's/mode: ""/mode: "ipvs"/' | \
	sed -e "s/strictARP: false/strictARP: true/" | \
	kubectl apply -f - -n kube-system
kubectl get pod -n kube-system | grep kube-proxy | awk '{system("kubectl delete pod "$1" -n kube-system")}'
sleep 20  # todo 修复，查看kube-proxy状态决定是否运行或等待
kubectl get pod -n kube-system | grep kube-proxy | awk '{system("kubectl logs "$1" -n kube-system")}' | egrep "ipvs"
echo "=========================Done.============================="

echo "=====================创建openelb负载均衡器ip pool====================="
kubectl label --overwrite nodes master1 master2 master3 lb.kubesphere.io/v1alpha1=openelb
helm repo add stable https://charts.kubesphere.io/stable
helm repo update
helm install -f ./config/openelb-values.yaml -n kube-system openelb stable/openelb

echo "等待openelb-manager启动..."
sleep 120  # todo 修复，查看openelb-manager状态以决定是否继续运行或等待

cat <<EOF | kubectl create -f -
---
apiVersion: network.kubesphere.io/v1alpha2
kind: Eip
metadata:
  name: ouxxa-dev-eip
spec:
  address: 10.0.5.1-10.0.5.100
  interface: can_reach:10.0.0.1
  protocol: layer2
  disable: false
EOF

kubectl scale deployment openelb-manager --replicas=3 -n kube-system
echo "==============================Done.=================================="



