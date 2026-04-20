package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/watch"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

const (
	labelSelector = "yolean.se/module-part=y-kustomize"
	// Secret name convention: y-kustomize.{group}.{name}
	// Served at: /v1/{group}/{name}/{key}
	secretPrefix = "y-kustomize."
)

type server struct {
	mu       sync.RWMutex
	// path -> content
	files    map[string][]byte
	client   kubernetes.Interface
	ns       string
}

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/health" {
		w.WriteHeader(http.StatusOK)
		return
	}

	s.mu.RLock()
	content, ok := s.files[r.URL.Path]
	s.mu.RUnlock()

	if !ok {
		http.NotFound(w, r)
		return
	}

	w.Header().Set("Content-Type", "application/x-yaml")
	w.Write(content)
}

// secretToFiles converts a secret's data keys to URL paths.
// Secret name y-kustomize.blobs.setup-bucket-job with key base-for-annotations.yaml
// becomes /v1/blobs/setup-bucket-job/base-for-annotations.yaml
func secretToFiles(name string, data map[string][]byte) map[string][]byte {
	if !strings.HasPrefix(name, secretPrefix) {
		return nil
	}
	suffix := strings.TrimPrefix(name, secretPrefix)
	// suffix = "blobs.setup-bucket-job" -> path = "blobs/setup-bucket-job"
	pathBase := "/v1/" + strings.Replace(suffix, ".", "/", 1)

	files := make(map[string][]byte)
	for key, val := range data {
		files[pathBase+"/"+key] = val
	}
	return files
}

func (s *server) syncAll(ctx context.Context) error {
	secrets, err := s.client.CoreV1().Secrets(s.ns).List(ctx, metav1.ListOptions{
		LabelSelector: labelSelector,
	})
	if err != nil {
		return fmt.Errorf("list secrets: %w", err)
	}

	files := make(map[string][]byte)
	for _, sec := range secrets.Items {
		for path, content := range secretToFiles(sec.Name, sec.Data) {
			files[path] = content
			log.Printf("serving %s (%d bytes)", path, len(content))
		}
	}

	s.mu.Lock()
	s.files = files
	s.mu.Unlock()
	return nil
}

func (s *server) watchSecrets(ctx context.Context) {
	for {
		log.Printf("starting secret watch (label=%s, ns=%s)", labelSelector, s.ns)
		watcher, err := s.client.CoreV1().Secrets(s.ns).Watch(ctx, metav1.ListOptions{
			LabelSelector: labelSelector,
		})
		if err != nil {
			log.Printf("watch error: %v, retrying in 5s", err)
			select {
			case <-ctx.Done():
				return
			default:
			sleepCtx(ctx, 5*time.Second)
			}
			continue
		}

		for event := range watcher.ResultChan() {
			switch event.Type {
			case watch.Added, watch.Modified:
				if err := s.syncAll(ctx); err != nil {
					log.Printf("sync error on %s: %v", event.Type, err)
				}
			case watch.Deleted:
				if err := s.syncAll(ctx); err != nil {
					log.Printf("sync error on delete: %v", err)
				}
			case watch.Error:
				log.Printf("watch error event, restarting watch")
			}
		}
		log.Printf("watch channel closed, restarting")
	}
}

func sleepCtx(ctx context.Context, d time.Duration) {
	select {
	case <-ctx.Done():
	case <-time.After(d):
	}
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8787"
	}

	ns := os.Getenv("NAMESPACE")
	if ns == "" {
		// Try in-cluster namespace
		data, err := os.ReadFile("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
		if err == nil {
			ns = strings.TrimSpace(string(data))
		} else {
			ns = "ystack"
		}
	}

	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatalf("in-cluster config: %v", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("kubernetes client: %v", err)
	}

	s := &server{
		files:  make(map[string][]byte),
		client: clientset,
		ns:     ns,
	}

	ctx := context.Background()

	// Initial sync
	if err := s.syncAll(ctx); err != nil {
		log.Printf("initial sync: %v (will retry via watch)", err)
	}

	// Start watching for changes
	go s.watchSecrets(ctx)

	log.Printf("y-kustomize listening on :%s (ns=%s, label=%s)", port, ns, labelSelector)
	if err := http.ListenAndServe(":"+port, s); err != nil {
		log.Fatal(err)
	}
}
