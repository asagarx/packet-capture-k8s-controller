help: ## Show this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deploy: update-manifests ## Deploy to Kubernetes
	@echo "Deploying CRD..."
	@kubectl apply -f crd/packet_capture_config_crd.yaml --validate=false
	@echo "Deploying RBAC..."
	@kubectl apply -f manifests/rbac.yaml
	@echo "Deploying Configuration..."
	@kubectl apply -f manifests/config.yaml
	@echo "Deploying Controller..."
	@kubectl apply -f manifests/controller/deployment.yaml
	@echo "Deploying Agent DaemonSet..."
	@kubectl apply -f manifests/agent/daemonset.yaml
	@echo "Deployment complete!"

destroy: ## Destroy all Kubernetes resources including CRD
	@echo "Destroying packet capture controller resources..."
	@echo "Deleting webhook..."
	@kubectl delete -f manifests/webhook.yaml --ignore-not-found=true
	@echo "Deleting agent DaemonSet..."
	@kubectl delete -f manifests/agent/daemonset.yaml --ignore-not-found=true
	@echo "Deleting controller deployment..."
	@kubectl delete -f manifests/controller/deployment.yaml --ignore-not-found=true
	@echo "Deleting configuration..."
	@kubectl delete -f manifests/config.yaml --ignore-not-found=true
	@echo "Deleting RBAC..."
	@kubectl delete -f manifests/rbac.yaml --ignore-not-found=true
	@echo "Deleting all PacketCaptureConfig resources..."
	@kubectl delete packetcaptureconfigs --all --ignore-not-found=true
	@echo "Deleting CRD..."
	@kubectl delete -f crd/packet_capture_config_crd.yaml --ignore-not-found=true
	@echo "Destruction complete!"

status: ## Show status of deployed resources
	@echo "=== CRD Status ==="
	@kubectl get crd packetcaptureconfigs.networking.packet.io 2>/dev/null || echo "CRD not found"
	@echo ""
	@echo "=== Controller Status ==="
	@kubectl get deployment packet-capture-controller -n kube-system 2>/dev/null || echo "Controller not found"
	@echo ""
	@echo "=== Agent Status ==="
	@kubectl get daemonset packet-capture-agent -n kube-system 2>/dev/null || echo "Agent not found"
	@echo ""
	@echo "=== PacketCaptureConfigs ==="
	@kubectl get packetcaptureconfigs 2>/dev/null || echo "No PacketCaptureConfigs found"

.DEFAULT_GOAL := help