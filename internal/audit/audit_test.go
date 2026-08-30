package audit

import (
	"path/filepath"
	"testing"
	"time"
)

func TestScopeAllows(t *testing.T) {
	s := NewScope()
	if err := s.Add("10.0.0.0/24"); err != nil {
		t.Fatal(err)
	}
	if err := s.Add("192.168.1.5"); err != nil {
		t.Fatal(err)
	}
	cases := map[string]bool{
		"10.0.0.7":     true,
		"10.0.1.7":     false,
		"192.168.1.5":  true,
		"192.168.1.6":  false,
		"8.8.8.8":      false,
	}
	for ip, want := range cases {
		if got := s.Allows(ip); got != want {
			t.Errorf("Allows(%s)=%v, queria %v", ip, got, want)
		}
	}
}

func TestScopeRejectsInvalid(t *testing.T) {
	s := NewScope()
	if err := s.Add("nao-e-ip"); err == nil {
		t.Fatal("deveria rejeitar entrada inválida")
	}
}

func TestScopeEmpty(t *testing.T) {
	s := NewScope()
	if !s.Empty() {
		t.Fatal("escopo novo deve ser vazio (nenhuma varredura permitida)")
	}
	_ = s.Add("127.0.0.1")
	if s.Empty() {
		t.Fatal("escopo com entrada não é vazio")
	}
}

func TestLoadAndAppendScope(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "scope.txt")
	if err := AppendScope(path, "127.0.0.1"); err != nil {
		t.Fatal(err)
	}
	if err := AppendScope(path, "10.1.0.0/16"); err != nil {
		t.Fatal(err)
	}
	s, err := LoadScope(path)
	if err != nil {
		t.Fatal(err)
	}
	if !s.Allows("127.0.0.1") || !s.Allows("10.1.2.3") {
		t.Fatal("escopo carregado não permite o esperado")
	}
	if s.Allows("172.16.0.1") {
		t.Fatal("escopo permitiu fora da faixa")
	}
}

func TestScanTCPLocalhostClosedPort(t *testing.T) {
	// Porta improvável de estar aberta; valida que o scan não trava e retorna vazio.
	res := ScanTCP("localhost", "127.0.0.1", []int{1}, 300*time.Millisecond)
	if len(res.Open) != 0 {
		t.Logf("porta 1 aberta? incomum, mas não é erro do teste: %v", res.Open)
	}
}
