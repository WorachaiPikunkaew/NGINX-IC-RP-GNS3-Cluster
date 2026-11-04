Install NGINX ingress controller from helm.
```
helm install nginx-ingress oci://ghcr.io/nginx/charts/nginx-ingress \
--version 2.8.0 -n nginx-ingress --create-namespace -f helm-values.yaml
```
Install cert-manager using helm.
```
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true
```
Apply ``` pki-setup.yaml ``` with kubectl.
Use ``` genbackend-crt.sh ``` to export certificates for backends.
Modify and apply ``` web1.yaml ```.
