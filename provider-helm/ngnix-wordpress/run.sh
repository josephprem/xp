#!/bin/bash

# Helper script to deploy crossplane and helm-provider on top of k3d

cluster_name=xp-helm-demo

echo "Deleting $cluster_name"
k3d cluster delete $cluster_name || echo "Cluster $cluster_name not found"

echo "Creating $cluster_name"
k3d cluster create $cluster_name --wait --timeout 3m -p "8081:80@loadbalancer"

echo "Add crossplane helm repo"
helm repo add crossplane-stable https://charts.crossplane.io/stable --force-update

echo "Install Crossplane"
helm install crossplane --namespace crossplane-system crossplane-stable/crossplane  --create-namespace --wait

echo "Install Helm provider"
kubectl -n crossplane-system create -f provider-helm.yml 

kubectl wait --for condition="Installed" providers provider-helm

# Ugly wait
echo "Wait for SA to be available"
timeout 5 bash -c 'while :; do kubectl -n crossplane-system get sa -o name | grep provider-helm ; sleep 1; done ' 

echo "Work with in-cluster deployments"
SA=$(kubectl -n crossplane-system get sa -o name | grep provider-helm | sed -e 's|serviceaccount\/|crossplane-system:|g')
kubectl create clusterrolebinding provider-helm-admin-binding --clusterrole cluster-admin --serviceaccount="${SA}"
kubectl apply -f https://raw.githubusercontent.com/crossplane-contrib/provider-helm/master/examples/provider-config/provider-config-incluster.yaml

echo "Deploy ingress"
kubectl apply -f nginx.yml

echo "Deploy wordpress"
kubectl apply -f wordpress.yml

echo "Wait for deployment to be ready"
sleep 10 && kubectl -n wordpress  wait --for=condition=ready pod --timeout=180s  -lapp.kubernetes.io/name=wordpress

echo "Open your browser and try http://localhost:8081"
