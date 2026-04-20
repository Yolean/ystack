package main

import (
	"testing"
)

func TestSecretToFiles(t *testing.T) {
	tests := []struct {
		name string
		data map[string][]byte
		want map[string][]byte
	}{
		{
			name: "y-kustomize.blobs.setup-bucket-job",
			data: map[string][]byte{
				"base-for-annotations.yaml": []byte("apiVersion: v1\nkind: Secret"),
			},
			want: map[string][]byte{
				"/v1/blobs/setup-bucket-job/base-for-annotations.yaml": []byte("apiVersion: v1\nkind: Secret"),
			},
		},
		{
			name: "y-kustomize.kafka.setup-topic-job",
			data: map[string][]byte{
				"base-for-annotations.yaml": []byte("apiVersion: batch/v1\nkind: Job"),
			},
			want: map[string][]byte{
				"/v1/kafka/setup-topic-job/base-for-annotations.yaml": []byte("apiVersion: batch/v1\nkind: Job"),
			},
		},
		{
			name: "unrelated-secret",
			data: map[string][]byte{"key": []byte("value")},
			want: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := secretToFiles(tt.name, tt.data)
			if tt.want == nil {
				if got != nil {
					t.Errorf("expected nil, got %v", got)
				}
				return
			}
			for path, content := range tt.want {
				if string(got[path]) != string(content) {
					t.Errorf("path %s: got %q, want %q", path, got[path], content)
				}
			}
		})
	}
}
