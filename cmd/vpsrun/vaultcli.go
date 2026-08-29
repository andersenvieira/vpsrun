package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"golang.org/x/term"

	"github.com/andersenvieira/vpsrun/internal/core"
	"github.com/andersenvieira/vpsrun/internal/resolvers"
	"github.com/andersenvieira/vpsrun/internal/vault"
)

// runVaultCLI trata `vpsrun vault <subcomando> ...` de forma não-interativa,
// permitindo popular e consultar o cofre sem TUI (útil para automação e testes).
//
// A Senha_Master vem de $VPSRUN_MASTER (automação) ou de prompt oculto (TTY).
func runVaultCLI(args []string) int {
	if len(args) == 0 {
		vaultUsage()
		return 2
	}
	switch args[0] {
	case "ls":
		return vaultLs()
	case "add":
		return vaultAdd(args[1:])
	case "reveal":
		return vaultReveal(args[1:])
	case "change-master":
		return vaultChangeMaster()
	case "-h", "--help", "help":
		vaultUsage()
		return 0
	default:
		fmt.Fprintln(os.Stderr, "subcomando desconhecido:", args[0])
		vaultUsage()
		return 2
	}
}

func vaultUsage() {
	fmt.Println(`uso: vpsrun vault <subcomando>

  ls                         lista as entradas (metadados)
  add ...                    adiciona entrada (ver flags abaixo)
  reveal <id>                revela/resolve o valor de uma entrada
  change-master              troca a senha master (re-cifra o cofre)

flags de 'add':
  --group G --app A --type T --label L
  estático:  --value SEGREDO
  dinâmico:  --dyn KIND [--path P] [--key K] [--ref R] [--expr E]
             KIND ∈ dotenv|docker|nginx|file|command

Senha master: definida em $VPSRUN_MASTER ou solicitada de forma oculta.`)
}

func readMaster(confirm bool) (string, error) {
	if m := os.Getenv("VPSRUN_MASTER"); m != "" {
		return m, nil
	}
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		return "", fmt.Errorf("sem TTY: defina $VPSRUN_MASTER")
	}
	fmt.Fprint(os.Stderr, "Senha master: ")
	b, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Fprintln(os.Stderr)
	if err != nil {
		return "", err
	}
	pass := string(b)
	if confirm {
		fmt.Fprint(os.Stderr, "Confirme a senha master: ")
		b2, err := term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Fprintln(os.Stderr)
		if err != nil {
			return "", err
		}
		if string(b2) != pass {
			return "", fmt.Errorf("as senhas não conferem")
		}
	}
	return pass, nil
}

// openOrCreate abre o cofre; se não existir, cria (confirmando a senha).
func openOrCreate() (*vault.Vault, error) {
	path := core.VaultPath()
	if core.VaultExists() {
		m, err := readMaster(false)
		if err != nil {
			return nil, err
		}
		return vault.Open(path, m)
	}
	fmt.Fprintln(os.Stderr, "Cofre não existe — criando novo em", path)
	m, err := readMaster(true)
	if err != nil {
		return nil, err
	}
	return vault.Create(path, m)
}

func vaultLs() int {
	v, err := openOrCreate()
	if err != nil {
		fmt.Fprintln(os.Stderr, "erro:", err)
		return 1
	}
	entries := v.List()
	if len(entries) == 0 {
		fmt.Println("(cofre vazio)")
		return 0
	}
	fmt.Printf("%-16s %-10s %-16s %-14s %-8s %s\n", "ID", "GRUPO", "APP", "TIPO", "MODO", "LABEL")
	for _, e := range entries {
		fmt.Printf("%-16s %-10s %-16s %-14s %-8s %s\n", e.ID, e.Group, e.App, e.Type, e.Mode, e.Label)
	}
	return 0
}

func vaultAdd(args []string) int {
	f := parseFlags(args)
	group, app, typ, label := f["group"], f["app"], f["type"], f["label"]
	if group == "" || app == "" || typ == "" || label == "" {
		fmt.Fprintln(os.Stderr, "faltam --group/--app/--type/--label")
		return 2
	}
	v, err := openOrCreate()
	if err != nil {
		fmt.Fprintln(os.Stderr, "erro:", err)
		return 1
	}
	var id string
	if dyn, ok := f["dyn"]; ok {
		src := vault.Source{Kind: dyn, Path: f["path"], Key: f["key"], Ref: f["ref"], Expr: f["expr"]}
		id, err = v.AddDynamic(group, app, typ, label, src)
	} else {
		val, ok := f["value"]
		if !ok {
			fmt.Fprintln(os.Stderr, "use --value (estático) ou --dyn KIND (dinâmico)")
			return 2
		}
		id, err = v.AddStatic(group, app, typ, label, val)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "erro:", err)
		return 1
	}
	fmt.Println("adicionada entrada", id)
	return 0
}

func vaultReveal(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "uso: vpsrun vault reveal <id>")
		return 2
	}
	id := args[0]
	v, err := openOrCreate()
	if err != nil {
		fmt.Fprintln(os.Stderr, "erro:", err)
		return 1
	}
	e, ok := v.Get(id)
	if !ok {
		fmt.Fprintln(os.Stderr, "entrada não encontrada:", id)
		return 1
	}
	if e.Mode == vault.ModeDynamic && e.Source != nil {
		val, err := resolvers.Resolve(*e.Source)
		if err != nil {
			fmt.Fprintln(os.Stderr, "erro ao resolver:", err)
			return 1
		}
		fmt.Println(val)
		return 0
	}
	val, err := v.RevealStatic(id)
	if err != nil {
		fmt.Fprintln(os.Stderr, "erro:", err)
		return 1
	}
	fmt.Println(val)
	return 0
}

func vaultChangeMaster() int {
	path := core.VaultPath()
	if !core.VaultExists() {
		fmt.Fprintln(os.Stderr, "não há cofre para trocar a senha")
		return 1
	}
	old, err := readMaster(false)
	if err != nil {
		fmt.Fprintln(os.Stderr, "erro:", err)
		return 1
	}
	v, err := vault.Open(path, old)
	if err != nil {
		fmt.Fprintln(os.Stderr, "erro:", err)
		return 1
	}
	fmt.Fprintln(os.Stderr, "-- nova senha --")
	var novo string
	if envNew := os.Getenv("VPSRUN_MASTER_NEW"); envNew != "" {
		novo = envNew
	} else {
		novo, err = readMasterNew()
		if err != nil {
			fmt.Fprintln(os.Stderr, "erro:", err)
			return 1
		}
	}
	if err := v.ChangeMaster(novo); err != nil {
		fmt.Fprintln(os.Stderr, "erro:", err)
		return 1
	}
	fmt.Println("senha master trocada com sucesso")
	return 0
}

func readMasterNew() (string, error) {
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		return "", fmt.Errorf("sem TTY: defina $VPSRUN_MASTER_NEW")
	}
	fmt.Fprint(os.Stderr, "Nova senha master: ")
	b, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Fprintln(os.Stderr)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// parseFlags interpreta --chave valor (e --flag booleano no fim).
func parseFlags(args []string) map[string]string {
	out := map[string]string{}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if !strings.HasPrefix(a, "--") {
			continue
		}
		key := strings.TrimPrefix(a, "--")
		if i+1 < len(args) && !strings.HasPrefix(args[i+1], "--") {
			out[key] = args[i+1]
			i++
		} else {
			out[key] = ""
		}
	}
	return out
}

// stdinLine lê uma linha (usado em prompts não sensíveis, se necessário).
func stdinLine() string {
	sc := bufio.NewScanner(os.Stdin)
	if sc.Scan() {
		return strings.TrimSpace(sc.Text())
	}
	return ""
}
