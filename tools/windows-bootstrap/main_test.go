package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
)

func runtimeZip(t *testing.T, entries map[string]string) ([]byte, string) {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for name, body := range entries {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := io.WriteString(w, body); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(buf.Bytes())
	return buf.Bytes(), hex.EncodeToString(sum[:])
}

func TestEnsureRuntimeDownloadsVerifiesExtractsAndCaches(t *testing.T) {
	archive, hash := runtimeZip(t, map[string]string{
		engineName:                              "fake-engine",
		"Godot_v4.7.2-stable_win64_console.exe": "fake-console",
	})
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		_, _ = w.Write(archive)
	}))
	defer srv.Close()

	dir := t.TempDir()
	cfg := runtimeConfig{URL: srv.URL, SHA256: hash, Engine: engineName, Client: srv.Client()}
	got, err := ensureRuntime(context.Background(), dir, cfg)
	if err != nil {
		t.Fatalf("ensureRuntime first call: %v", err)
	}
	if got != filepath.Join(dir, engineName) {
		t.Fatalf("unexpected engine path: %s", got)
	}
	if data, err := os.ReadFile(got); err != nil || string(data) != "fake-engine" {
		t.Fatalf("extracted engine mismatch: %q err=%v", data, err)
	}

	if _, err := ensureRuntime(context.Background(), dir, cfg); err != nil {
		t.Fatalf("ensureRuntime cached call: %v", err)
	}
	if hits.Load() != 1 {
		t.Fatalf("runtime should download once, got %d requests", hits.Load())
	}
}

func TestEnsureRuntimeUsesExistingEngineWithoutNetwork(t *testing.T) {
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		http.Error(w, "should not download", http.StatusInternalServerError)
	}))
	defer srv.Close()

	dir := t.TempDir()
	enginePath := filepath.Join(dir, engineName)
	if err := os.WriteFile(enginePath, []byte("bundled-engine"), 0o755); err != nil {
		t.Fatal(err)
	}
	cfg := runtimeConfig{URL: srv.URL, SHA256: strings.Repeat("0", 64), Engine: engineName, Client: srv.Client()}
	got, err := ensureRuntime(context.Background(), dir, cfg)
	if err != nil {
		t.Fatalf("ensureRuntime with bundled engine: %v", err)
	}
	if got != enginePath {
		t.Fatalf("unexpected engine path: %s", got)
	}
	if hits.Load() != 0 {
		t.Fatalf("bundled runtime must skip download, got %d requests", hits.Load())
	}
}

func TestEnsureRuntimeDoesNotDownloadWhenEnginePathExistsButIsInvalid(t *testing.T) {
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		http.Error(w, "should not download", http.StatusInternalServerError)
	}))
	defer srv.Close()

	dir := t.TempDir()
	enginePath := filepath.Join(dir, engineName)
	if err := os.Mkdir(enginePath, 0o755); err != nil {
		t.Fatal(err)
	}
	cfg := runtimeConfig{URL: srv.URL, SHA256: strings.Repeat("0", 64), Engine: engineName, Client: srv.Client()}
	if _, err := ensureRuntime(context.Background(), dir, cfg); err == nil {
		t.Fatal("expected invalid existing engine path to fail")
	}
	if hits.Load() != 0 {
		t.Fatalf("runtime download must only happen when engine is missing, got %d requests", hits.Load())
	}
}

func TestEnsureRuntimeRejectsBadHash(t *testing.T) {
	archive, _ := runtimeZip(t, map[string]string{engineName: "fake-engine"})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write(archive)
	}))
	defer srv.Close()

	dir := t.TempDir()
	cfg := runtimeConfig{URL: srv.URL, SHA256: string(make([]byte, 64)), Engine: engineName, Client: srv.Client()}
	if _, err := ensureRuntime(context.Background(), dir, cfg); err == nil {
		t.Fatal("expected checksum mismatch")
	}
	if _, err := os.Stat(filepath.Join(dir, engineName)); !os.IsNotExist(err) {
		t.Fatalf("engine should not exist after checksum failure, err=%v", err)
	}
}

func TestExtractZipRejectsTraversal(t *testing.T) {
	archive, _ := runtimeZip(t, map[string]string{"../escape.exe": "bad"})
	zipPath := filepath.Join(t.TempDir(), "bad.zip")
	if err := os.WriteFile(zipPath, archive, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := extractZip(zipPath, t.TempDir()); err == nil {
		t.Fatal("expected zip traversal rejection")
	}
}


func TestResolvePiExecutablePrefersExplicitOverride(t *testing.T) {
	calls := []string{}
	lookup := func(name string) (string, error) {
		calls = append(calls, name)
		if name == `C:\\tools\\pi.cmd` {
			return name, nil
		}
		return "", os.ErrNotExist
	}
	got, err := resolvePiExecutable(`C:\\tools\\pi.cmd`, lookup)
	if err != nil {
		t.Fatalf("explicit GAMESMITH_PI_BIN should resolve: %v", err)
	}
	if got != `C:\\tools\\pi.cmd` {
		t.Fatalf("unexpected explicit Pi path: %q", got)
	}
	if len(calls) != 1 || calls[0] != `C:\\tools\\pi.cmd` {
		t.Fatalf("explicit override must be checked directly, calls=%v", calls)
	}
}

func TestResolvePiExecutableUsesGlobalNpmPath(t *testing.T) {
	lookup := func(name string) (string, error) {
		if name == "pi" {
			return `C:\\Users\\tester\\AppData\\Roaming\\npm\\pi.cmd`, nil
		}
		return "", os.ErrNotExist
	}
	got, err := resolvePiExecutable("", lookup)
	if err != nil {
		t.Fatalf("global npm Pi should resolve from PATH: %v", err)
	}
	if !strings.HasSuffix(strings.ToLower(got), `\\npm\\pi.cmd`) {
		t.Fatalf("expected npm global shim, got %q", got)
	}
}

func TestResolvePiExecutableMissingHasInstallGuidance(t *testing.T) {
	lookup := func(string) (string, error) { return "", os.ErrNotExist }
	_, err := resolvePiExecutable("", lookup)
	if err == nil {
		t.Fatal("missing Pi should produce startup guidance")
	}
	message := err.Error()
	for _, want := range []string{
		"npm install -g @earendil-works/pi-coding-agent@1.0.0",
		"GAMESMITH_PI_BIN",
	} {
		if !strings.Contains(message, want) {
			t.Fatalf("missing Pi guidance should mention %q: %s", want, message)
		}
	}
}
