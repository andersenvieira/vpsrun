package resolvers

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/andersenvieira/vpsrun/internal/vault"
)

func TestResolveDotenv(t *testing.T) {
	dir := t.TempDir()
	env := filepath.Join(dir, ".env")
	content := "# comentario\nAPP_ENV=production\nDB_PASSWORD=\"segredo-123\"\nEMPTY=\n"
	if err := os.WriteFile(env, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	got, err := Resolve(vault.Source{Kind: "dotenv", Path: env, Key: "DB_PASSWORD"})
	if err != nil {
		t.Fatalf("Resolve: %v", err)
	}
	if got != "segredo-123" {
		t.Fatalf("esperava segredo-123, veio %q", got)
	}
}

func TestResolveDotenvMissingKey(t *testing.T) {
	dir := t.TempDir()
	env := filepath.Join(dir, ".env")
	os.WriteFile(env, []byte("A=1\n"), 0o600)
	if _, err := Resolve(vault.Source{Kind: "dotenv", Path: env, Key: "NAO_EXISTE"}); err == nil {
		t.Fatal("esperava erro para chave ausente")
	}
}

func TestResolveNginxServerName(t *testing.T) {
	dir := t.TempDir()
	conf := filepath.Join(dir, "site.conf")
	content := "server {\n  listen 80;\n  server_name exemplo.com.br www.exemplo.com.br;\n}\n"
	os.WriteFile(conf, []byte(content), 0o600)
	got, err := Resolve(vault.Source{Kind: "nginx", Path: conf})
	if err != nil {
		t.Fatalf("Resolve: %v", err)
	}
	if got != "exemplo.com.br www.exemplo.com.br" {
		t.Fatalf("server_name inesperado: %q", got)
	}
}

func TestResolveCommandNotAllowed(t *testing.T) {
	if _, err := Resolve(vault.Source{Kind: "command", Ref: "rm", Expr: "-rf /"}); err == nil {
		t.Fatal("comando fora da allowlist deveria falhar")
	}
}

func TestResolveUnknownKind(t *testing.T) {
	if _, err := Resolve(vault.Source{Kind: "xpto"}); err == nil {
		t.Fatal("tipo desconhecido deveria falhar")
	}
}
