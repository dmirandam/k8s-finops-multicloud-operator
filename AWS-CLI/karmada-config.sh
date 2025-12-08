mkdir -p ~/.kube
chmod 0700 ~/.kube
sudo microk8s config > ~/.kube/config
sudo kubectl karmada init --kubeconfig="/home/ubuntu/.kube/config"

# After initializing Karmada, set up kubeconfig for EKS cluster and join it to Karmada 

aws eks update-kubeconfig --region us-west-2 --name tekton-karpenter574 --kubeconfig /home/ubuntu/.kube/eks-1

# Push mode

sudo karmadactl join member1 --kubeconfig="/etc/karmada/karmada-apiserver.config" --cluster-kubeconfig="/home/ubuntu/.kube/eks-1"

# Pull mode

sudo karmadactl token create --print-register-command --kubeconfig /etc/karmada/karmada-apiserver.config
sudo karmadactl register 10.10.x.x:32443 --token t2jgtm.EXAMPLE --discovery-token-ca-cert-hash sha256:f5a5a43869bb44577dba582e794c3e3750f2EXAMPLEoEXAMPLE


#Get Clusters

sudo kubectl --kubeconfig /etc/karmada/karmada-apiserver.config get clusters