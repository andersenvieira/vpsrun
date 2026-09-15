// Package core reúne utilidades transversais (caminhos, versão).
package core

import (
	"os"
	"path/filepath"
)

// Version é a versão do vpsrun.
const Version = "0.1.0"

// VaultPath devolve o caminho padrão do cofre (~/.config/vpsrun/vault.json).
func VaultPath() string {
	if p := os.Getenv("VPSRUN_VAULT"); p != "" {
		return p
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "vault.json"
	}
	return filepath.Join(home, ".config", "vpsrun", "vault.json")
}

// ScriptsDir localiza o diretório de Executores Bash.
// Ordem: $VPSRUN_SCRIPTS, ./scripts, ~/Documents/VPSRUN (legado), diretório atual.
func ScriptsDir() string {
	if p := os.Getenv("VPSRUN_SCRIPTS"); p != "" {
		return p
	}
	candidates := []string{"scripts"}
	if home, err := os.UserHomeDir(); err == nil {
		candidates = append(candidates, filepath.Join(home, "Documents", "VPSRUN", "scripts"))
		candidates = append(candidates, filepath.Join(home, "Documents", "VPSRUN"))
	}
	for _, c := range candidates {
		if st, err := os.Stat(c); err == nil && st.IsDir() {
			return c
		}
	}
	return "scripts"
}

// AnsibleDir localiza o diretório dos playbooks Ansible.
// Ordem: $VPSRUN_ANSIBLE, ./ansible, ~/Documents/VPSRUN/ansible, diretório atual.
func AnsibleDir() string {
	if p := os.Getenv("VPSRUN_ANSIBLE"); p != "" {
		return p
	}
	candidates := []string{"ansible"}
	if home, err := os.UserHomeDir(); err == nil {
		candidates = append(candidates, filepath.Join(home, "Documents", "VPSRUN", "ansible"))
	}
	for _, c := range candidates {
		if st, err := os.Stat(c); err == nil && st.IsDir() {
			return c
		}
	}
	return "ansible"
}

// VaultExists indica se já há um cofre criado.
func VaultExists() bool {
	_, err := os.Stat(VaultPath())
	return err == nil
}

// AuditScopePath é o arquivo do Escopo_Autorizado da edição standalone.
func AuditScopePath() string {
	if p := os.Getenv("VPSRUN_AUDIT_SCOPE"); p != "" {
		return p
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "audit-scope.txt"
	}
	return filepath.Join(home, ".config", "vpsrun", "audit-scope.txt")
}

// AuditLogPath é a trilha de auditoria da edição standalone.
func AuditLogPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "audit-log.txt"
	}
	return filepath.Join(home, ".config", "vpsrun", "audit-log.txt")
}
