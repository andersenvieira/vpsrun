// Package resolvers lê valores dinâmicos ao vivo das fontes do sistema.
//
// É isto que torna o cofre "não-estático": em vez de guardar a senha do banco,
// guardamos de onde lê-la (ex.: o .env do app). Quando a fonte muda, a próxima
// consulta reflete o valor novo, sem edição manual e sem depender de IA.
package resolvers

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"github.com/andersenvieira/vpsrun/internal/vault"
)

// allowedCommands limita quais binários o resolver "command" pode executar.
var allowedCommands = map[string]bool{
	"docker": true, "systemctl": true, "wp": true, "php": true,
}

// Resolve lê o valor ao vivo conforme o tipo da fonte.
func Resolve(s vault.Source) (string, error) {
	switch s.Kind {
	case "dotenv":
		return resolveDotenv(s.Path, s.Key)
	case "file":
		return resolveFileRegex(s.Path, s.Expr)
	case "docker":
		return resolveDocker(s.Ref, s.Expr)
	case "nginx":
		return resolveNginxServerName(s.Path)
	case "command":
		return resolveCommand(s.Ref, s.Expr)
	default:
		return "", fmt.Errorf("tipo de fonte desconhecido: %q", s.Kind)
	}
}

// resolveDotenv extrai KEY=VALUE de um arquivo .env, removendo aspas.
func resolveDotenv(path, key string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		eq := strings.IndexByte(line, '=')
		if eq < 0 {
			continue
		}
		k := strings.TrimSpace(line[:eq])
		if k != key {
			continue
		}
		val := strings.TrimSpace(line[eq+1:])
		val = strings.Trim(val, `"'`)
		return val, nil
	}
	if err := sc.Err(); err != nil {
		return "", err
	}
	return "", fmt.Errorf("chave %q não encontrada em %s", key, path)
}

// resolveFileRegex aplica um regex e devolve o 1º grupo de captura.
func resolveFileRegex(path, expr string) (string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	re, err := regexp.Compile(expr)
	if err != nil {
		return "", err
	}
	m := re.FindSubmatch(raw)
	if len(m) < 2 {
		return "", fmt.Errorf("regex sem captura em %s", path)
	}
	return string(m[1]), nil
}

// resolveDocker roda `docker inspect --format <expr> <ref>`.
func resolveDocker(ref, format string) (string, error) {
	if ref == "" {
		return "", fmt.Errorf("docker: ref (container) vazio")
	}
	if format == "" {
		format = "{{.State.Status}}"
	}
	return runCmd("docker", "inspect", "--format", format, ref)
}

// resolveNginxServerName extrai o primeiro server_name de um arquivo de config.
func resolveNginxServerName(path string) (string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	re := regexp.MustCompile(`(?m)^\s*server_name\s+([^;]+);`)
	m := re.FindSubmatch(raw)
	if len(m) < 2 {
		return "", fmt.Errorf("server_name não encontrado em %s", path)
	}
	return strings.TrimSpace(string(m[1])), nil
}

// resolveCommand executa um comando da allowlist. Ref = binário, Expr = args (por espaço).
func resolveCommand(ref, args string) (string, error) {
	if !allowedCommands[ref] {
		return "", fmt.Errorf("comando não permitido: %q", ref)
	}
	var a []string
	if args != "" {
		a = strings.Fields(args)
	}
	return runCmd(ref, a...)
}

func runCmd(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%s: %w: %s", name, err, strings.TrimSpace(string(out)))
	}
	return strings.TrimSpace(string(out)), nil
}

// ResolveWithTimeout evita travar a UI se uma fonte demorar.
func ResolveWithTimeout(s vault.Source, d time.Duration) (string, error) {
	type res struct {
		val string
		err error
	}
	ch := make(chan res, 1)
	go func() {
		v, err := Resolve(s)
		ch <- res{v, err}
	}()
	select {
	case r := <-ch:
		return r.val, r.err
	case <-time.After(d):
		return "", fmt.Errorf("timeout ao resolver fonte %s", s.Kind)
	}
}
