#!/bin/bash

set -e

sudo apt update
sudo apt install -y unzip

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
chmod +x kubectl
mkdir -p ~/.local/bin
mv ./kubectl ~/.local/bin/kubectl

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh

sudo snap install microk8s --classic --channel=1.33

sudo usermod -a -G microk8s $USER
mkdir -p ~/.kube
chmod 0700 ~/.kube

sudo microk8s enable dns
sudo microk8s enable hostpath-storage

sudo microk8s config > ~/.kube/config

git clone https://github.com/dmirandam/k8s-finops-multicloud-operator.git
cd k8s-finops-multicloud-operator

sudo microk8s kubectl apply -f https://storage.googleapis.com/tekton-releases/operator/latest/release.yaml
sudo microk8s kubectl wait --for=condition=Available=True --timeout=300s deployment/tekton-operator -n tekton-operator

sudo microk8s kubectl apply -f https://raw.githubusercontent.com/tektoncd/operator/main/config/crs/kubernetes/config/all/operator_v1alpha1_config_cr.yaml

timeout 120 bash -c 'until sudo microk8s kubectl get namespace tekton-pipelines >/dev/null 2>&1; do sleep 5; done'
timeout 800 bash -c 'until sudo microk8s kubectl get deployment tekton-dashboard -n tekton-pipelines >/dev/null 2>&1; do sleep 5; done'

sudo microk8s kubectl wait --for=condition=Available=True --timeout=300s deployment/tekton-dashboard -n tekton-pipelines

cat <<EOF | sudo microk8s kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: tekton-dashboard-nodeport
  namespace: tekton-pipelines
spec:
  type: NodePort
  selector:
    app.kubernetes.io/component: dashboard
  ports:
    - name: http
      port: 9097
      targetPort: 9097
      nodePort: 30097
EOF


sudo microk8s kubectl apply -f k8s-finops-multicloud-operator/tekton/AWS/tasks.yaml
sudo microk8s kubectl apply -f k8s-finops-multicloud-operator/tekton/AWS/pipeline.yaml