curl -s https://raw.githubusercontent.com/karmada-io/karmada/master/hack/install-cli.sh | sudo bash
curl -s https://raw.githubusercontent.com/karmada-io/karmada/master/hack/install-cli.sh | sudo bash -s kubectl-karmada

mkdir -p ~/.kube
chmod 0700 ~/.kube
sudo microk8s config > ~/.kube/config
sudo kubectl karmada init --kubeconfig="/home/ubuntu/.kube/config"

# After initializing Karmada, set up kubeconfig for EKS cluster and join it to Karmada 

aws eks update-kubeconfig --region us-west-2 --name tekton-karpenter-a3 --kubeconfig /home/ubuntu/.kube/eks-1
aws eks update-kubeconfig --region us-west-2 --name tekton-karpenter-a4 --kubeconfig /home/ubuntu/.kube/eks-2

# Push mode

sudo karmadactl join member1 --kubeconfig="/etc/karmada/karmada-apiserver.config" --cluster-kubeconfig="/home/ubuntu/.kube/eks-1"
sudo karmadactl join member2 --kubeconfig="/etc/karmada/karmada-apiserver.config" --cluster-kubeconfig="/home/ubuntu/.kube/eks-2"

# Pull mode

sudo karmadactl token create --print-register-command --kubeconfig /etc/karmada/karmada-apiserver.config
sudo karmadactl register 10.10.x.x:32443 --token t2jgtm.EXAMPLE --discovery-token-ca-cert-hash sha256:f5a5a43869bb44577dba582e794c3e3750f2EXAMPLEoEXAMPLE


#Get Clusters

sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusters


export KUBECONFIG="/home/ubuntu/.kube/eks-1"

#EFS SG

export AWS_REGION=us-west-2
export AWS_DEFAULT_REGION=us-west-2




#Grafana
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo