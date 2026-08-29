// Package vault implementa o Cofre de Credenciais do vpsrun.
//
// Modelo de segurança:
//   - A Senha_Master nunca é persistida. Ela deriva uma chave de 32 bytes via
//     argon2id (KDF resistente a força bruta).
//   - Segredos estáticos são cifrados em repouso com AES-256-GCM (autenticado).
//   - Um "verifier" cifrado valida se a Senha_Master informada está correta.
//   - Entradas dinâmicas não guardam valor: apenas a fonte de onde ler ao vivo
//     (resolvida por outro pacote), refletindo sempre o estado real do sistema.
package vault

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"

	"golang.org/x/crypto/argon2"
)

// ErrBadMaster indica Senha_Master incorreta ao abrir o cofre.
var ErrBadMaster = errors.New("senha master incorreta")

const (
	verifierPlain = "vpsrun-vault-v1"
	saltLen       = 16
	keyLen        = 32

	// Modos de entrada.
	ModeStatic  = "static"
	ModeDynamic = "dynamic"
)

// KDFParams são os parâmetros do argon2id.
type KDFParams struct {
	Memory  uint32 `json:"m"`
	Time    uint32 `json:"t"`
	Threads uint8  `json:"p"`
}

// DefaultKDFParams: 64 MiB, 3 iterações, 4 threads.
func DefaultKDFParams() KDFParams { return KDFParams{Memory: 64 * 1024, Time: 3, Threads: 4} }

// KDF descreve como a chave é derivada.
type KDF struct {
	Algo   string    `json:"algo"`
	Salt   string    `json:"salt"` // base64
	Params KDFParams `json:"params"`
}

// Source aponta de onde um valor dinâmico é lido ao vivo.
type Source struct {
	Kind string `json:"kind"`           // dotenv | docker | nginx | file | command
	Path string `json:"path,omitempty"` // caminho do arquivo (dotenv/file/nginx)
	Key  string `json:"key,omitempty"`  // chave (dotenv)
	Ref  string `json:"ref,omitempty"`  // referência (container, comando)
	Expr string `json:"expr,omitempty"` // regex/format
}

// Entry é uma credencial ou nota categorizada.
type Entry struct {
	ID       string  `json:"id"`
	Group    string  `json:"group"`
	App      string  `json:"app"`
	Type     string  `json:"type"`
	Label    string  `json:"label"`
	Mode     string  `json:"mode"`
	ValueEnc string  `json:"value_enc,omitempty"` // AES-256-GCM (base64) — só static
	Source   *Source `json:"source,omitempty"`    // só dynamic
}

// file é a estrutura serializada em disco.
type file struct {
	Version  int     `json:"version"`
	KDF      KDF     `json:"kdf"`
	Verifier string  `json:"verifier"`
	Entries  []Entry `json:"entries"`
}

// Vault é o cofre aberto em memória.
type Vault struct {
	path string
	key  []byte
	data file
}

func deriveKey(master string, salt []byte, p KDFParams) []byte {
	return argon2.IDKey([]byte(master), salt, p.Time, p.Memory, p.Threads, keyLen)
}

func encrypt(key, plaintext []byte) (string, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return "", err
	}
	ct := gcm.Seal(nonce, nonce, plaintext, nil)
	return base64.StdEncoding.EncodeToString(ct), nil
}

func decrypt(key []byte, b64 string) ([]byte, error) {
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	if len(raw) < gcm.NonceSize() {
		return nil, errors.New("ciphertext muito curto")
	}
	nonce, ct := raw[:gcm.NonceSize()], raw[gcm.NonceSize():]
	return gcm.Open(nil, nonce, ct, nil)
}

func newID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// Create cria um novo cofre no caminho dado, protegido pela Senha_Master.
func Create(path, master string) (*Vault, error) {
	salt := make([]byte, saltLen)
	if _, err := rand.Read(salt); err != nil {
		return nil, err
	}
	params := DefaultKDFParams()
	key := deriveKey(master, salt, params)
	verifier, err := encrypt(key, []byte(verifierPlain))
	if err != nil {
		return nil, err
	}
	v := &Vault{
		path: path,
		key:  key,
		data: file{
			Version:  1,
			KDF:      KDF{Algo: "argon2id", Salt: base64.StdEncoding.EncodeToString(salt), Params: params},
			Verifier: verifier,
			Entries:  []Entry{},
		},
	}
	return v, v.Save()
}

// Open abre um cofre existente e valida a Senha_Master.
func Open(path, master string) (*Vault, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var d file
	if err := json.Unmarshal(raw, &d); err != nil {
		return nil, err
	}
	salt, err := base64.StdEncoding.DecodeString(d.KDF.Salt)
	if err != nil {
		return nil, err
	}
	key := deriveKey(master, salt, d.KDF.Params)
	plain, err := decrypt(key, d.Verifier)
	if err != nil || string(plain) != verifierPlain {
		return nil, ErrBadMaster
	}
	return &Vault{path: path, key: key, data: d}, nil
}

// Save grava o cofre de forma atômica com permissão 0600.
func (v *Vault) Save() error {
	if err := os.MkdirAll(filepath.Dir(v.path), 0o700); err != nil {
		return err
	}
	raw, err := json.MarshalIndent(v.data, "", "  ")
	if err != nil {
		return err
	}
	tmp := v.path + ".tmp"
	if err := os.WriteFile(tmp, raw, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, v.path)
}

// AddStatic adiciona um segredo estático (cifrado).
func (v *Vault) AddStatic(group, app, typ, label, value string) (string, error) {
	enc, err := encrypt(v.key, []byte(value))
	if err != nil {
		return "", err
	}
	id := newID()
	v.data.Entries = append(v.data.Entries, Entry{
		ID: id, Group: group, App: app, Type: typ, Label: label,
		Mode: ModeStatic, ValueEnc: enc,
	})
	return id, v.Save()
}

// AddDynamic adiciona uma entrada dinâmica (só a fonte, sem valor).
func (v *Vault) AddDynamic(group, app, typ, label string, src Source) (string, error) {
	id := newID()
	s := src
	v.data.Entries = append(v.data.Entries, Entry{
		ID: id, Group: group, App: app, Type: typ, Label: label,
		Mode: ModeDynamic, Source: &s,
	})
	return id, v.Save()
}

// List devolve uma cópia das entradas (metadados; valores estáticos ficam cifrados).
func (v *Vault) List() []Entry {
	out := make([]Entry, len(v.data.Entries))
	copy(out, v.data.Entries)
	return out
}

// Get devolve a entrada pelo ID.
func (v *Vault) Get(id string) (Entry, bool) {
	for _, e := range v.data.Entries {
		if e.ID == id {
			return e, true
		}
	}
	return Entry{}, false
}

// RevealStatic decifra o valor de um segredo estático.
func (v *Vault) RevealStatic(id string) (string, error) {
	e, ok := v.Get(id)
	if !ok {
		return "", errors.New("entrada não encontrada")
	}
	if e.Mode != ModeStatic {
		return "", errors.New("entrada não é estática")
	}
	b, err := decrypt(v.key, e.ValueEnc)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// ChangeMaster re-cifra o cofre com uma nova Senha_Master.
func (v *Vault) ChangeMaster(newMaster string) error {
	// Decifra todos os estáticos com a chave atual.
	plain := make(map[string]string)
	for _, e := range v.data.Entries {
		if e.Mode == ModeStatic {
			b, err := decrypt(v.key, e.ValueEnc)
			if err != nil {
				return err
			}
			plain[e.ID] = string(b)
		}
	}
	// Nova salt + chave.
	salt := make([]byte, saltLen)
	if _, err := rand.Read(salt); err != nil {
		return err
	}
	params := DefaultKDFParams()
	newKey := deriveKey(newMaster, salt, params)
	verifier, err := encrypt(newKey, []byte(verifierPlain))
	if err != nil {
		return err
	}
	// Re-cifra estáticos.
	for i, e := range v.data.Entries {
		if e.Mode == ModeStatic {
			enc, err := encrypt(newKey, []byte(plain[e.ID]))
			if err != nil {
				return err
			}
			v.data.Entries[i].ValueEnc = enc
		}
	}
	v.key = newKey
	v.data.KDF = KDF{Algo: "argon2id", Salt: base64.StdEncoding.EncodeToString(salt), Params: params}
	v.data.Verifier = verifier
	return v.Save()
}

// Path devolve o caminho do arquivo do cofre.
func (v *Vault) Path() string { return v.path }
