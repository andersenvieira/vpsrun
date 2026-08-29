// Package runner chama os Executores Bash/Ansible de forma segura.
//
// Argumentos são sempre passados como slice (sem interpolação de string),
// evitando injeção de comando. A saída é capturada para exibição na TUI.
package runner

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

// Runner executa scripts a partir de um diretório base (scripts/).
type Runner struct {
	ScriptsDir string
}

// New cria um Runner apontando para o diretório de scripts.
func New(scriptsDir string) *Runner { return &Runner{ScriptsDir: scriptsDir} }

// RunScript executa `bash <ScriptsDir>/<name> [args...]` com timeout.
// env são variáveis extras (não são logadas).
func (r *Runner) RunScript(name string, args []string, env map[string]string, timeout time.Duration) (string, error) {
	path := filepath.Join(r.ScriptsDir, name)
	if _, err := os.Stat(path); err != nil {
		return "", fmt.Errorf("script não encontrado: %s", path)
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	full := append([]string{path}, args...)
	cmd := exec.CommandContext(ctx, "bash", full...)
	cmd.Env = os.Environ()
	for k, v := range env {
		cmd.Env = append(cmd.Env, k+"="+v)
	}
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return buf.String(), fmt.Errorf("tempo esgotado após %s", timeout)
	}
	return buf.String(), err
}

// RunCommand executa um comando arbitrário (args como slice) com timeout.
func RunCommand(timeout time.Duration, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Run()
	return buf.String(), err
}
