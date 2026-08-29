package vault

import (
	"path/filepath"
	"testing"
)

func TestCreateOpenRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "vault.json")

	v, err := Create(path, "senha-master-forte")
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if _, err := v.AddStatic("Bancos", "AUDIOFREAKS", "db_password", "MariaDB", "s3nh4-do-banco"); err != nil {
		t.Fatalf("AddStatic: %v", err)
	}

	// Reabrir com a senha correta.
	v2, err := Open(path, "senha-master-forte")
	if err != nil {
		t.Fatalf("Open (senha correta): %v", err)
	}
	entries := v2.List()
	if len(entries) != 1 {
		t.Fatalf("esperava 1 entrada, veio %d", len(entries))
	}
	got, err := v2.RevealStatic(entries[0].ID)
	if err != nil {
		t.Fatalf("RevealStatic: %v", err)
	}
	if got != "s3nh4-do-banco" {
		t.Fatalf("valor decifrado errado: %q", got)
	}
}

func TestOpenWrongMaster(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "vault.json")
	if _, err := Create(path, "correta"); err != nil {
		t.Fatalf("Create: %v", err)
	}
	if _, err := Open(path, "errada"); err != ErrBadMaster {
		t.Fatalf("esperava ErrBadMaster, veio %v", err)
	}
}

func TestChangeMaster(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "vault.json")
	v, err := Create(path, "antiga")
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	id, err := v.AddStatic("Meta", "WhatsApp", "api_token", "Token", "tok-123")
	if err != nil {
		t.Fatalf("AddStatic: %v", err)
	}
	if err := v.ChangeMaster("nova"); err != nil {
		t.Fatalf("ChangeMaster: %v", err)
	}
	// Senha antiga não abre mais.
	if _, err := Open(path, "antiga"); err != ErrBadMaster {
		t.Fatalf("senha antiga deveria falhar, veio %v", err)
	}
	// Nova abre e o valor continua íntegro.
	v2, err := Open(path, "nova")
	if err != nil {
		t.Fatalf("Open (nova): %v", err)
	}
	got, err := v2.RevealStatic(id)
	if err != nil {
		t.Fatalf("RevealStatic: %v", err)
	}
	if got != "tok-123" {
		t.Fatalf("valor após troca de master errado: %q", got)
	}
}

func TestDynamicEntryHasNoStoredValue(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "vault.json")
	v, err := Create(path, "m")
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	id, err := v.AddDynamic("Bancos", "APP", "db_password", "Dinâmico",
		Source{Kind: "dotenv", Path: "/tmp/x/.env", Key: "DB_PASSWORD"})
	if err != nil {
		t.Fatalf("AddDynamic: %v", err)
	}
	e, _ := v.Get(id)
	if e.ValueEnc != "" {
		t.Fatalf("entrada dinâmica não deve guardar valor cifrado")
	}
	if e.Source == nil || e.Source.Key != "DB_PASSWORD" {
		t.Fatalf("fonte dinâmica não persistida corretamente")
	}
}
