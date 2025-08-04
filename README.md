# Packet Capture Kubernetes Controller

A Kubernetes controller that runs as a DaemonSet on Linux nodes to capture network packets based on custom resource configurations. The system provides distributed packet capture capabilities across Kubernetes clusters with flexible filtering, multiple output formats, and automated file management.

## Overview

This system consists of two main components:
1. **Controller**: A Kubernetes deployment that watches `PacketCaptureConfig` CRDs and coordinates packet captures across the cluster
2. **Agent**: A DaemonSet that runs on each Linux node and performs the actual packet capture using HTTP API communication

The controller communicates with agents using HTTP REST API to initiate, monitor, and stop packet captures across multiple nodes simultaneously.

## Key Features

### Core Functionality
- **Cluster-Scoped CRD**: PacketCaptureConfig resources are cluster-scoped for global packet capture management
- **Distributed Architecture**: Controller manages captures across multiple nodes via HTTP API
- **Multi-Architecture Support**: Docker images support both AMD64 and ARM64 architectures
- **Agent DaemonSet**: Runs on all Linux nodes with privileged access for packet capture execution
- **BPF Filtering**: Uses Berkeley Packet Filter (BPF) for efficient kernel-level packet filtering
- **Fallback Filtering**: Python-based filtering when BPF is not available

### Capture Capabilities
- **IP-based Filtering**: Capture packets to/from specific IP addresses
- **Pod-based Filtering**: Automatically resolve and capture traffic for specific Kubernetes pods
- **Port Filtering**: Filter packets by TCP/UDP port numbers
- **Custom BPF Filters**: Support for additional custom tcpdump-style filter expressions
- **Multi-Interface Capture**: Captures from all network interfaces including container interfaces
- **Duration Control**: Configurable capture duration with automatic timeout
- **Packet Limits**: Configurable maximum packet count per capture

### Output Formats
- **PCAP Format**: Standard packet capture format for analysis with Wireshark, tcpdump, etc.
- **Text Format**: Human-readable text output with detailed packet information
- **Stdout Format**: Real-time packet logging to agent pod logs for live monitoring

### File Management
- **Automatic Compression**: Completed capture files are automatically compressed using gzip
- **Periodic Cleanup**: Automatic cleanup every 60 seconds to maintain file count limits
- **Configurable Limits**: Maximum file count and size limits per node
- **Uncompressed Latest**: Most recent capture file kept uncompressed for immediate access
- **Storage Location**: Files stored at `/var/lib/packet-captures/` on each node

### Configuration & Monitoring
- **ConfigMap-based Configuration**: All settings configurable via Kubernetes ConfigMaps
- **Configurable Logging**: Debug/Info/Warning log levels with third-party log suppression
- **Configurable Ports**: Agent port configurable via ConfigMap (default: 8080)
- **Status Tracking**: Real-time status updates in CRD with file paths and capture progress
- **Event Generation**: Kubernetes events for capture lifecycle and error conditions
- **Retry Logic**: Automatic retry for failed captures with exponential backoff

## Installation

### Prerequisites

- **Kubernetes cluster** (v1.19+)
- **cert-manager** (for webhook TLS certificates)
- **libpcap-dev** installed in agent containers for BPF filtering
- **Privileged access** for agent pods to capture network traffic
- **Host network access** for capturing pod-to-pod traffic

### Install cert-manager

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
```

### Deploy the CRD

```bash
kubectl apply -f crd/packet_capture_config_crd.yaml
```

### Manual Deployment

```bash
# Deploy CRD
kubectl apply -f crd/packet_capture_config_crd.yaml

# Deploy RBAC
kubectl apply -f manifests/rbac.yaml

# Deploy Configuration
kubectl apply -f manifests/config.yaml

# Deploy Controller
kubectl apply -f manifests/controller/deployment.yaml

# Deploy Agent DaemonSet
kubectl apply -f manifests/agent/daemonset.yaml

# Deploy Webhook (optional, requires cert-manager)
kubectl apply -f manifests/webhook.yaml
```

## Usage

Create a `PacketCaptureConfig` resource to start capturing packets:

```bash
kubectl apply -f manifests/sample-config.yaml
```

### PacketCaptureConfig Specification

| Field | Type | Description | Required | Default |
|-------|------|-------------|----------|---------|
| targetIPs | array of strings | IP addresses to capture | Yes* | - |
| podSelector | object | Pod-based capture configuration | Yes* | - |
| podSelector.pods | array of objects | List of pods to capture | Yes | - |
| podSelector.pods[].podName | string | Name of the pod to capture | Yes | - |
| podSelector.pods[].namespace | string | Namespace of the pod | Yes |  |
| targetPorts | array of integers | Ports to capture | No | [] |
| duration | integer | Duration in seconds | No | 60 |
| maxPackets | integer | Maximum number of packets | No | 1000 |
| outputFormat | string | Output format (pcap, text, or stdout) | No | pcap |
| filter | string | Additional tcpdump filter expression | No | "" |

*At least one of `targetIPs` or `podSelector` must be specified. Both can be used together.

### Examples

#### IP-based Capture
```yaml
apiVersion: networking.packet.io/v1
kind: PacketCaptureConfig
metadata:
  name: ip-capture
spec:
  targetIPs:
    - 10.0.0.1
    - 10.0.0.2
  targetPorts:
    - 80
    - 443
  duration: 120
  maxPackets: 2000
  outputFormat: pcap
  filter: "tcp"
```

#### Pod-based Capture
```yaml
apiVersion: networking.packet.io/v1
kind: PacketCaptureConfig
metadata:
  name: pod-capture
spec:
  podSelector:
    pods:
      - podName: my-app-pod
        namespace: default
      - podName: my-other-pod
        namespace: kube-system
  targetPorts:
    - 80
    - 443
  duration: 120
  maxPackets: 2000
  outputFormat: text
```

#### Combined IP and Pod Capture
```yaml
apiVersion: networking.packet.io/v1
kind: PacketCaptureConfig
metadata:
  name: combined-capture
spec:
  targetIPs:
    - 10.0.0.1
    - 10.0.0.2
  podSelector:
    pods:
      - podName: my-app-pod
        namespace: default
  targetPorts:
    - 80
    - 443
  duration: 120
  maxPackets: 2000
  outputFormat: pcap
```

#### Stdout Format (Real-time Logging)
```yaml
apiVersion: networking.packet.io/v1
kind: PacketCaptureConfig
metadata:
  name: realtime-capture
spec:
  targetIPs:
    - 192.168.1.100
  targetPorts:
    - 80
    - 443
  duration: 300
  maxPackets: 1000
  outputFormat: stdout
```

## Architecture

```
┌─────────────────┐   HTTP API   ┌─────────────────┐
│   Controller    │◄───────────► │  Agent (Node 1) │
│  (Deployment)   │              │   (DaemonSet)   │
│                 │              │  Port: 8080     │
└─────────────────┘              └─────────────────┘
         │                               │
         │ Watches CRDs                  │ BPF Packet Capture
         │ Cluster-Scoped               │ Multi-Interface
         │                              │ /var/lib/packet-captures/
         ▼                               ▼
┌─────────────────┐              ┌─────────────────┐
│ PacketCapture   │              │  Agent (Node N) │
│     Config      │              │   (DaemonSet)   │
│   (Cluster CRD) │              │  Privileged     │
└─────────────────┘              └─────────────────┘
```

### Component Details

- **Controller**: Watches cluster-scoped PacketCaptureConfig CRDs, resolves pod IPs, and coordinates captures across nodes
- **Agent**: Runs on each node with privileged access, performs BPF-based packet capture on all network interfaces
- **Communication**: HTTP REST API between controller and agents (configurable port)
- **Storage**: Captures stored locally on each node with automatic compression and cleanup
- **Monitoring**: Real-time status updates and Kubernetes events for capture lifecycle

## Configuration

The system can be configured using the ConfigMap in `manifests/config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: packet-capture-config
  namespace: kube-system
data:
  # Maximum number of capture files to keep per node (default: 5)
  MAX_CAPTURE_FILES: "5"
  
  # Maximum size of each capture file in MB (default: 10)
  MAX_CAPTURE_FILE_SIZE_MB: "10"
  
  # Log level for controller (DEBUG, INFO, WARNING, ERROR)
  LOG_LEVEL: "INFO"
  
  # Agent port (default: 8080)
  AGENT_PORT: "8080"
```

### Configuration Options

| Setting | Description | Default | Impact |
|---------|-------------|---------|--------|
| `MAX_CAPTURE_FILES` | Maximum files per node | 5 | Older files auto-deleted |
| `MAX_CAPTURE_FILE_SIZE_MB` | Max file size in MB | 10 | Capture stops when reached |
| `LOG_LEVEL` | Controller log level | INFO | DEBUG shows all logs |
| `AGENT_PORT` | Agent HTTP API port | 8080 | Must match firewall rules |

## File Management

- **Automatic Compression**: Completed capture files are automatically compressed using gzip (except latest file)
- **Periodic Cleanup**: Cleanup runs every 60 seconds to maintain file count limits
- **File Rotation**: Old files are automatically removed when `MAX_CAPTURE_FILES` limit is exceeded
- **Size Limits**: Captures stop automatically when `MAX_CAPTURE_FILE_SIZE_MB` is reached
- **Latest File Uncompressed**: Most recent capture file kept uncompressed for immediate access
- **Storage Location**: Files stored at `/var/lib/packet-captures/` on each node
- **Stdout Format**: No files created when `outputFormat: stdout` is used

## Accessing Capture Results

Packet captures are stored on each node at `/var/lib/packet-captures/` as compressed files (`.pcap.gz` or `.txt.gz`). The controller creates ConfigMaps with capture results and metadata.

### Checking Capture Status

To view the status and file paths of packet captures:

```bash
# List all packet capture configs with status
kubectl get packetcaptureconfigs

# Get detailed status including file paths
kubectl get packetcaptureconfig <name> -o yaml
```

The status includes:
- `phase`: Current capture phase (Starting, Running, Completed, Failed)
- `message`: Descriptive status message
- `captureFiles`: File paths and details for each node

### Example Status Output

#### File-based Capture
```yaml
status:
  phase: Completed
  message: "Packet capture completed on all nodes"
  captureFiles:
    "10.0.1.100":
      status: completed
      output_file: "/var/lib/packet-captures/sample-capture-20231201-143022.pcap"
      file_size: 2048576
    "10.0.1.101":
      status: completed
      output_file: "/var/lib/packet-captures/sample-capture-20231201-143022.txt"
      file_size: 1536000
```

#### Stdout Format Capture
```yaml
status:
  phase: Completed
  message: "Packet capture completed on all nodes"
  captureFiles:
    "10.0.1.100":
      status: completed
      output_file: "Packet capture logs are in stdout format"
      file_size: 0
    "10.0.1.101":
      status: completed
      output_file: "Packet capture logs are in stdout format"
      file_size: 0
```

### Viewing Stdout Format Captures

For captures with `outputFormat: stdout`, view the agent logs:

```bash
# View logs from all agent pods
kubectl logs -f daemonset/packet-capture-agent -n kube-system

# View logs from specific node
kubectl logs -f daemonset/packet-capture-agent -n kube-system --field-selector spec.nodeName=<node-name>

# Filter for packet logs only
kubectl logs daemonset/packet-capture-agent -n kube-system | grep "PACKET:"
```

## Management Commands

### Using Makefile
```bash
# Show all available commands
make help

# Check deployment status
make status

# View controller logs
make logs-controller

# View agent logs
make logs-agent

# Restart components
make restart

# Clean up everything
make destroy
```

### Manual Commands
```bash
# List all packet capture configs
kubectl get packetcaptureconfigs

# Get detailed status
kubectl get packetcaptureconfig <name> -o yaml

# Delete a capture config
kubectl delete packetcaptureconfig <name>

# Check agent pod status
kubectl get pods -n kube-system -l app=packet-capture-agent
```

## Troubleshooting

### Common Issues

1. **No packets captured**: Check if target IPs/pods are correct and generating traffic
2. **Permission denied**: Ensure agent pods have privileged security context
3. **BPF filter errors**: libpcap-dev not installed or invalid filter syntax
4. **Pod IP resolution fails**: Check if pods exist and are running
5. **Agent communication fails**: Verify agent port configuration and network policies

### Debug Steps

```bash
# Enable debug logging
kubectl patch configmap packet-capture-config -n kube-system --patch '{"data":{"LOG_LEVEL":"DEBUG"}}'

# Restart controller to apply debug logging
kubectl rollout restart deployment/packet-capture-controller -n kube-system

# Check agent health
kubectl exec -it daemonset/packet-capture-agent -n kube-system -- curl localhost:8080/health

# Verify network interfaces
kubectl exec -it daemonset/packet-capture-agent -n kube-system -- ls /sys/class/net/
```

## Advanced Usage

### Custom BPF Filters

```yaml
apiVersion: networking.packet.io/v1
kind: PacketCaptureConfig
metadata:
  name: custom-filter-capture
spec:
  targetIPs:
    - 10.0.0.1
  filter: "tcp and (port 80 or port 443) and not icmp"
  duration: 300
  outputFormat: pcap
```

### High-Volume Capture

```yaml
apiVersion: networking.packet.io/v1
kind: PacketCaptureConfig
metadata:
  name: high-volume-capture
spec:
  targetIPs:
    - 10.0.0.0/24
  maxPackets: 10000
  duration: 1800  # 30 minutes
  outputFormat: pcap
```

## Performance Considerations

- **BPF Filtering**: More efficient than Python filtering, reduces CPU usage
- **File Compression**: Automatic gzip compression saves disk space
- **Multi-Interface**: Captures from all interfaces including container networks
- **Configurable Limits**: Prevent disk space exhaustion with file size/count limits
- **Privileged Access**: Required for low-level packet capture but increases security risk

## Security Considerations

- **Privileged Pods**: Agent pods run with privileged security context
- **Host Network**: Agent pods use host network for comprehensive packet capture
- **File Access**: Capture files stored on host filesystem
- **Network Visibility**: Can capture sensitive network traffic
- **RBAC**: Proper RBAC controls access to PacketCaptureConfig resources

## License

MIT License - see [LICENSE](LICENSE.md) file for details
