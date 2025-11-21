# Roles


### Cluster (ok)

- eksctl-santiago-karpenter-demo-template-ServiceRole-QtcJFKDy5Sn4 (service-role-%s) ok

### NodeGroup (ok)

- eksctl-santiago-karpenter-demo-tem-NodeInstanceRole-gczmHBV9um7y (node-role-%s) ok

### aws-auth configmap

- KarpenterNodeRole-santiago-karpenter-demo-template (karpenter-node-role-%s)
- eksctl-santiago-karpenter-demo-tem-NodeInstanceRole-gczmHBV9um7y (node-role-%s)

### Addon CNI (ok)

- eksctl-santiago-karpenter-demo-template-addon-Role1-9SOAwCjpJRVb (addon-role-%s) ok

## Access

### IAM access entries

- aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS ---
- eksctl-santiago-karpenter-demo-tem-NodeInstanceRole-gczmHBV9um7y (node-role-%s) ok
- user/CLI-admin ---

### Pod Identity associations (ok)

- santiago-karpenter-demo-template-karpenter (karpenter-controller-role-%s) ok