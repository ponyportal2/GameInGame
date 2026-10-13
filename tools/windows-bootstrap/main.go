package main

import (
	"archive/zip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	runtimeURL    = "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip"
	runtimeSHA256 = "731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953"
	engineName    = "Godot_v4.7.2-stable_win64.exe"
	packName      = "GameSmith.pck"
)

type runtimeConfig struct {
	URL    string
	SHA256 string
	Engine string
	Client *http.Client
}

func main() {
	exePath, err := os.Executable()
	if err != nil {
		fatalf("Unable to locate GameSmith.exe: %v", err)
		return
	}
	baseDir := filepath.Dir(exePath)
	packPath := filepath.Join(baseDir, packName)
	if _, err := os.Stat(packPath); err != nil {
		fatalf("%s is missing next to GameSmith.exe.", packName)
		return
	}

	runtimeDir := filepath.Join(baseDir, "runtime")
	enginePath := filepath.Join(runtimeDir, engineName)
	if _, err := os.Stat(enginePath); errors.Is(err, os.ErrNotExist) {
		infof("GameSmith needs the official Godot 4.7.2 x64 runtime. It will be downloaded once (about 86 MB), verified, and cached in the runtime folder.")
	}

	cfg := runtimeConfig{
		URL:    runtimeURL,
		SHA256: runtimeSHA256,
		Engine: engineName,
		Client: &http.Client{Timeout: 10 * time.Minute},
	}
	enginePath, err = ensureRuntime(context.Background(), runtimeDir, cfg)
	if err != nil {
		fatalf("Unable to prepare the Godot runtime:\n\n%v\n\nYou can also manually place %s in the runtime folder.", err, engineName)
		return
	}

	if _, err := exec.LookPath("git.exe"); err != nil {
		warningf("Git for Windows was not found on PATH. GameSmith will open, but creating or editing generated games requires Git. Install Git for Windows and restart GameSmith.")
	}
	if !hasAgentHarness(os.Getenv("GAMESMITH_PI_BIN"), os.Getenv("GAMESMITH_COMMAND_CODE_BIN"), os.Getenv("GAMESMITH_OPENCODE_BIN"), os.Getenv("GAMESMITH_CODEX_BIN"), os.Getenv("GAMESMITH_CLINE_BIN"), os.Getenv("GAMESMITH_CURSOR_BIN"), os.Getenv("GAMESMITH_GROK_BUILD_BIN"), os.Getenv("GAMESMITH_AGY_BIN"), os.Getenv("GAMESMITH_KIMI_BIN"), os.Getenv("GAMESMITH_KIRO_BIN"), os.Getenv("GAMESMITH_KILO_BIN"), os.Getenv("GAMESMITH_COPILOT_BIN"), os.Getenv("GAMESMITH_CRUSH_BIN"), exec.LookPath) {
		warningf("No coding harness was found. GameSmith will open; install Pi, Command-code, OpenCode, Codex, Cline, Cursor, Grok Build, experimental AGY, Kimi Code, Kiro CLI, Kilo CLI, Copilot CLI, or Crush CLI to build or edit games.\n\nPi: npm install -g @earendil-works/pi-coding-agent@1.0.0\nCommand-code: npm install -g command-code\nOpenCode: npm install -g opencode-ai\nCodex: npm install -g @openai/codex\nCline: npm install -g cline\nCursor Agent CLI: https://cursor.com/docs/cli/installation\nGrok Build: https://docs.x.ai/build\nAGY (experimental): https://antigravity.google/docs/cli/installation\nKimi Code: https://moonshotai.github.io/kimi-code/\nKiro CLI: https://kiro.dev/docs/cli/\nKilo CLI: npm install -g @kilocode/cli\nCopilot CLI: npm install -g @github/copilot\nCrush CLI: winget install charmbracelet.crush\n\nThen restart GameSmith and choose the installed harness when creating a game.")
	}

	args := append([]string{"--main-pack", packPath}, os.Args[1:]...)
	cmd := exec.Command(enginePath, args...)
	cmd.Dir = baseDir
	if err := cmd.Start(); err != nil {
		fatalf("Unable to launch GameSmith:\n\n%v", err)
		return
	}
}

func hasAgentHarness(piConfigured, commandConfigured, openCodeConfigured, codexConfigured, clineConfigured, cursorConfigured, grokConfigured, agyConfigured, kimiConfigured, kiroConfigured, kiloConfigured, copilotConfigured, crushConfigured string, lookPath func(string) (string, error)) bool {
	if _, err := resolvePiExecutable(piConfigured, lookPath); err == nil {
		return true
	}
	if strings.TrimSpace(cursorConfigured) == "" {
		standard := filepath.Join(os.Getenv("LOCALAPPDATA"), "cursor-agent", "cursor-agent.cmd")
		if info, err := os.Stat(standard); err == nil && !info.IsDir() {
			return true
		}
	}
	if strings.TrimSpace(grokConfigured) == "" {
		standard := filepath.Join(os.Getenv("USERPROFILE"), ".grok", "bin", "grok.exe")
		if info, err := os.Stat(standard); err == nil && !info.IsDir() {
			return true
		}
	}
	if strings.TrimSpace(agyConfigured) == "" {
		standard := filepath.Join(os.Getenv("LOCALAPPDATA"), "agy", "bin", "agy.exe")
		if info, err := os.Stat(standard); err == nil && !info.IsDir() {
			return true
		}
	}
	if strings.TrimSpace(kimiConfigured) == "" {
		standard := filepath.Join(os.Getenv("USERPROFILE"), ".kimi-code", "bin", "kimi.exe")
		if info, err := os.Stat(standard); err == nil && !info.IsDir() {
			return true
		}
	}
	if strings.TrimSpace(kiroConfigured) == "" {
		standard := filepath.Join(os.Getenv("LOCALAPPDATA"), "Kiro-Cli", "kiro-cli.exe")
		if info, err := os.Stat(standard); err == nil && !info.IsDir() {
			return true
		}
	}

	for _, harness := range []struct{ configured, fallback string }{{commandConfigured, "command-code"}, {openCodeConfigured, "opencode"}, {codexConfigured, "codex"}, {clineConfigured, "cline"}, {cursorConfigured, "cursor-agent"}, {grokConfigured, "grok"}, {agyConfigured, "agy"}, {kimiConfigured, "kimi"}, {kiroConfigured, "kiro-cli"}, {kiloConfigured, "kilo"}, {copilotConfigured, "copilot"}, {crushConfigured, "crush"}} {
		command := strings.TrimSpace(harness.configured)
		if command == "" {
			command = harness.fallback
		}
		if _, err := lookPath(command); err == nil {
			return true
		}
		if info, err := os.Stat(command); err == nil && !info.IsDir() {
			return true
		}
	}
	return false
}

func resolvePiExecutable(configured string, lookPath func(string) (string, error)) (string, error) {
	target := strings.TrimSpace(configured)
	if target == "" {
		target = "pi"
	}
	resolved, err := lookPath(target)
	if err == nil {
		return resolved, nil
	}
	if strings.TrimSpace(configured) != "" {
		return "", fmt.Errorf("GAMESMITH_PI_BIN could not be resolved: %s\n\nSet it to a valid Pi executable, or install the pinned Pi build with:\n\nnpm install -g @earendil-works/pi-coding-agent@1.0.0", configured)
	}
	return "", errors.New("Install the pinned Pi coding agent with:\n\nnpm install -g @earendil-works/pi-coding-agent@1.0.0\n\nThen restart GameSmith. If Pi is installed outside PATH, set GAMESMITH_PI_BIN to the Pi executable.")
}

func ensureRuntime(ctx context.Context, runtimeDir string, cfg runtimeConfig) (string, error) {
	if cfg.Client == nil {
		cfg.Client = http.DefaultClient
	}
	if cfg.Engine == "" || cfg.URL == "" || cfg.SHA256 == "" {
		return "", errors.New("invalid runtime configuration")
	}

	enginePath := filepath.Join(runtimeDir, cfg.Engine)
	st, statErr := os.Stat(enginePath)
	if statErr == nil {
		if st.IsDir() {
			return "", fmt.Errorf("Godot runtime path is a directory, expected a file: %s", enginePath)
		}
		return enginePath, nil
	}
	if !errors.Is(statErr, os.ErrNotExist) {
		return "", fmt.Errorf("check Godot runtime path: %w", statErr)
	}

	if err := os.MkdirAll(runtimeDir, 0o755); err != nil {
		return "", fmt.Errorf("create runtime directory: %w", err)
	}

	zipPath := filepath.Join(runtimeDir, "godot-runtime.download.zip")
	_ = os.Remove(zipPath)
	if err := downloadFile(ctx, cfg.Client, cfg.URL, zipPath); err != nil {
		return "", err
	}
	defer os.Remove(zipPath)

	gotHash, err := fileSHA256(zipPath)
	if err != nil {
		return "", err
	}
	if !strings.EqualFold(gotHash, cfg.SHA256) {
		return "", fmt.Errorf("Godot runtime checksum mismatch: got %s", gotHash)
	}

	if err := extractZip(zipPath, runtimeDir); err != nil {
		return "", fmt.Errorf("extract Godot runtime: %w", err)
	}
	if st, err := os.Stat(enginePath); err != nil || st.IsDir() {
		return "", fmt.Errorf("verified archive did not contain %s", cfg.Engine)
	}
	return enginePath, nil
}

func downloadFile(ctx context.Context, client *http.Client, url, dst string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("prepare runtime download: %w", err)
	}
	req.Header.Set("User-Agent", "GameSmith-Windows-Bootstrap/1.0")

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("download Godot runtime: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("download Godot runtime: HTTP %s", resp.Status)
	}

	f, err := os.Create(dst)
	if err != nil {
		return fmt.Errorf("create runtime archive: %w", err)
	}
	ok := false
	defer func() {
		_ = f.Close()
		if !ok {
			_ = os.Remove(dst)
		}
	}()
	if _, err := io.Copy(f, resp.Body); err != nil {
		return fmt.Errorf("save runtime archive: %w", err)
	}
	if err := f.Sync(); err != nil {
		return fmt.Errorf("flush runtime archive: %w", err)
	}
	ok = true
	return nil
}

func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open runtime archive for checksum: %w", err)
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", fmt.Errorf("hash runtime archive: %w", err)
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func extractZip(zipPath, dstDir string) error {
	zr, err := zip.OpenReader(zipPath)
	if err != nil {
		return err
	}
	defer zr.Close()

	root, err := filepath.Abs(dstDir)
	if err != nil {
		return err
	}
	for _, zf := range zr.File {
		cleanName := filepath.Clean(filepath.FromSlash(zf.Name))
		if cleanName == "." || filepath.IsAbs(cleanName) || cleanName == ".." || strings.HasPrefix(cleanName, ".."+string(os.PathSeparator)) {
			return fmt.Errorf("unsafe archive path %q", zf.Name)
		}
		outPath := filepath.Join(root, cleanName)
		rel, err := filepath.Rel(root, outPath)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
			return fmt.Errorf("unsafe archive path %q", zf.Name)
		}

		if zf.FileInfo().IsDir() {
			if err := os.MkdirAll(outPath, 0o755); err != nil {
				return err
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(outPath), 0o755); err != nil {
			return err
		}
		src, err := zf.Open()
		if err != nil {
			return err
		}
		dst, err := os.OpenFile(outPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o755)
		if err != nil {
			src.Close()
			return err
		}
		_, copyErr := io.Copy(dst, src)
		closeDstErr := dst.Close()
		closeSrcErr := src.Close()
		if copyErr != nil {
			return copyErr
		}
		if closeDstErr != nil {
			return closeDstErr
		}
		if closeSrcErr != nil {
			return closeSrcErr
		}
	}
	return nil
}
