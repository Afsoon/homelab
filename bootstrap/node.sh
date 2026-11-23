#!/usr/bin/env bash
# Node-level setup for the homelab — state that lives OUTSIDE the cluster's
# control plane, so ArgoCD cannot manage it. The repo's contract for such
# state: versioned here, applied by hand, idempotent so it can be re-run
# after a node rebuild. Run ON THE NODE:
#
#   bash bootstrap/node.sh
#
# Cluster-side equivalent: kubectl apply -f bootstrap/root-app.yaml

set -euo pipefail

TRAEFIK_IP=$(kubectl get svc -n kube-system traefik -o jsonpath='{.spec.clusterIP}')

# 1. kubelet image pulls resolve registry hostnames via the NODE's DNS, not
#    CoreDNS. Public DNS points registry.lab.saidatr.dev at the tailnet
#    proxy, which the node cannot reach. Pointing the name at in-cluster
#    Traefik gives kubelet the same wildcard cert and the same Host header,
#    without the tailnet dependency. (Pod-level processes keep using the
#    CoreDNS rewrite in apps/registry/manifests/configmap-coredns.yaml —
#    the two mechanisms cover different layers.)
if ! grep -q "registry.lab.saidatr.dev" /etc/hosts; then
  echo "$TRAEFIK_IP registry.lab.saidatr.dev" | sudo tee -a /etc/hosts
  echo "added registry.lab.saidatr.dev -> $TRAEFIK_IP to /etc/hosts"
else
  echo "/etc/hosts: registry entry already present"
fi

# 2. firewalld: the pod bridge must be trusted, or nftables rejects
#    direct pod-to-pod traffic with admin-prohibited while iptables-save
#    shows nothing (see the Linear document).
sudo firewall-cmd --zone=trusted --change-interface=cni0 --permanent \
  || sudo firewall-cmd --zone=trusted --add-interface=cni0 --permanent
sudo firewall-cmd --reload
