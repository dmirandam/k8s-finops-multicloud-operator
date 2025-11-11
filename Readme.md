
helm install crossplane \
--namespace crossplane-system \
--create-namespace crossplane-stable/crossplane


k apply -f functions.yaml
k apply -f secret.yaml
k apply -f providers.yaml 
k apply -f provider_config.yaml -n crossplane-system
k apply -f XRD.yaml
k apply -f XR.yaml


apply -f composition_iam.yaml



