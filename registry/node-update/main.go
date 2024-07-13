package main

import (
	"bufio"
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"time"

	"github.com/containernetworking/plugins/pkg/ns"
	"github.com/txn2/txeh"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

const (
	nodeNameEnvName         = "NODE_NAME"
	prodRegistryHost        = "prod-registry.ystack.svc.cluster.local"
	buildsRegistryHost      = "builds-registry.ystack.svc.cluster.local"
	prodRegistryIpEnvName   = "PROD_REGISTRY_PORT_80_TCP_ADDR"
	buildsRegsitryIpEnvName = "BUILDS_REGISTRY_PORT_80_TCP_ADDR"
	containerdConfigPath    = "/etc/containerd/config.toml"
	containerdTargetPid     = 1
)

func main() {
	context := context.TODO()

	nodeName := os.Getenv(nodeNameEnvName)
	prodRegistryIp := os.Getenv(prodRegistryIpEnvName)
	buildsRegistryIp := os.Getenv(buildsRegsitryIpEnvName)

	hosts, err := txeh.NewHostsDefault()
	if err != nil {
		panic(err)
	}
	hosts.AddHost(buildsRegistryIp, buildsRegistryHost)
	hosts.AddHost(prodRegistryIp, prodRegistryHost)
	hosts.AddHost("127.99.99.99", "ystack-temp-test-host")
	hosts.Save()
	fmt.Printf("host added %s %s\n", buildsRegistryIp, buildsRegistryHost)
	fmt.Printf("host added %s %s\n", prodRegistryIp, prodRegistryHost)

	config, err := os.OpenFile(containerdConfigPath, os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		panic(err.Error())
	}
	defer config.Close()
	configwrite := bufio.NewWriter(config)
	_, err = configwrite.WriteString(`
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."builds-registry.ystack.svc.cluster.local"]
  endpoint = ["http://builds-registry.ystack.svc.cluster.local"]
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."prod-registry.ystack.svc.cluster.local"]
  endpoint = ["http://prod-registry.ystack.svc.cluster.local"]
`)
	if err != nil {
		panic(err.Error())
	}
	err = configwrite.Flush()
	if err != nil {
		panic(err.Error())
	}
	fmt.Printf("containerd config updated\n")

	fmt.Printf("containerd restart\n")
	if err = ns.WithNetNSPath(fmt.Sprintf("/proc/%d/ns/mnt", containerdTargetPid), func(_ ns.NetNS) error {
		// Code to run inside the namespace
		cmd := exec.Command("systemctl", "restart", "containerd")
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			log.Fatalf("Failed to run command in namespace: %v", err)
		}
		return nil
	}); err != nil {
		log.Fatalf("Failed to enter namespaces: %v", err)
	}
	fmt.Printf("containerd restarted\n")

	clientconfig, err := rest.InClusterConfig()
	if err != nil {
		panic(err.Error())
	}
	clientset, err := kubernetes.NewForConfig(clientconfig)
	if err != nil {
		panic(err.Error())
	}

	node, err := clientset.CoreV1().Nodes().Get(context, nodeName, metav1.GetOptions{})
	if err != nil {
		fmt.Printf("Error retrieving node: %v\n", err)
		return
	}

	for _, taint := range node.Spec.Taints {
		fmt.Printf("Existing taint: %s=%s:%s", taint.Key, taint.Value, taint.Effect)
	}

	// TODO
	// clientset.CoreV1().Nodes().Patch()

	// TODO
	// nsenter --mount=/proc/1/ns/mnt -- containerd config dump

	// TODO initcontainer or not?
	time.Sleep(10 * time.Hour)
}
