#!/bin/bash


echo "#######################################"
echo "## Start -- Post install"
echo "#######################################"


#echo "=============修复kubesphere gateway ingress-controller版本问题============="
# 修改gateway tag v0.48.1 -> v1.1.0
#kubectl get configmap kubesphere-config -n kubesphere-system -o yaml | \
#        sed -e 's/tag: v0.48.1/tag: v1.1.0/' | \
#        kubectl diff -f - -n kubesphere-system
#kubectl get configmap kubesphere-config -n kubesphere-system -o yaml | \
#	    sed -e 's/tag: v0.48.1/tag: v1.1.0/' | \
#	    kubectl apply -f - -n kubesphere-system
# 重启ks-controller-manager
#kubectl rollout restart deploy ks-controller-manager -n kubesphere-system
#echo "=========================Done.============================="


echo "==========================修复argocd out of sync问题============================"
# cert-manager Certificate duration和renewBefore不识别导致out of sync
kubectl patch -n argocd configmap argocd-cm --type=json -p='[{"op": "add", "path": "/data/resource.customizations.ignoreDifferences.cert-manager.io_Certificate", "value": "jsonPointers:\n- /spec/duration\n- /spec/renewBefore\n"}]'
echo "===============================Done.============================================"


echo "=========================创建代理configmap修复github访问========================"
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: kube-system
  name: proxy-config
  annotations:
    reflector.v1.k8s.emberstack.com/reflection-allowed: "true"
    reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces: "kubesphere-devops-system,kubesphere-devops-worker,argocd"
    reflector.v1.k8s.emberstack.com/reflection-auto-enabled: "true"
    reflector.v1.k8s.emberstack.com/reflection-auto-namespaces: "kubesphere-devops-system,kubesphere-devops-worker,argocd"
data:
  http_proxy: "http://10.0.0.102:7890"
  HTTP_PROXY: "http://10.0.0.102:7890"
  https_proxy: "http://10.0.0.102:7890"
  HTTPS_PROXY: "http://10.0.0.102:7890"
  all_proxy: "http://10.0.0.102:7890"
  ALL_PROXY: "http://10.0.0.102:7890"
  no_proxy: "localhost,127.0.0.0/8,10.0.0.0/16,100.233.0.0/18,100.233.64.0/18,*.xian-dev.dev,*.it.ouxxa.com"
  NO_PROXY: "localhost,127.0.0.0/8,10.0.0.0/16,100.233.0.0/18,100.233.64.0/18,*.xian-dev.dev,*.it.ouxxa.com"
EOF

# devops-argocd-repo-server需要代理访问github
kubectl patch -n argocd deployment devops-argocd-repo-server -p '{"spec": {"template": {"spec": {"containers": [{"name": "repo-server", "envFrom": [{ "configMapRef": { "name": "proxy-config" } }]}]}}}}'
kubectl patch -n kubesphere-devops-system deployment  devops-jenkins -p '{"spec": {"template": {"spec": {"containers": [{"name": "devops-jenkins", "envFrom": [{"configMapRef": {"name": "proxy-config"}}]}]}}}}'

kubectl rollout restart -n argocd deploy devops-argocd-repo-server
kubectl rollout restart -n kubesphere-devops-system deploy devops-jenkins
echo "==================================Done.========================================="


echo "===============================jenkins agent自定义镜像=========================="
# 自定义micrc镜像，并为base添加代理
kubectl get cm -n kubesphere-devops-system jenkins-casc-config -o json | jq --arg patch "`cat ./config/jenkins_user.yaml`" '.data["jenkins_user.yaml"] = $patch' | kubectl replace -f -

kubectl rollout restart -n kubesphere-devops-system deploy devops-jenkins
echo "=======================================Done.===================================="


echo "=============修改ks-console使用域名访问=============" # todo 完成逻辑
echo "创建专用eip，给一个固定地址，对于云环境，使用内部slb"
echo "kubesphere-system中创建网关 - 可以使用console gui创建，用创建出的deploy构建yaml文件，在这里自动创建"
echo "使用cert-manager创建证书"
echo "kubesphere-system中创建route(ingress)并使用证书 - 同上"
echo "=========================Done.============================="


echo "######################################"
echo "## Successful -- 完成."
echo "## 在kubesphere ‘控制台’ 的 ‘系统组件’ 确保所有组件正常运行后开始使用"
echo "######################################"
