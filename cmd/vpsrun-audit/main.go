// Command vpsrun-audit é a EDIÇÃO STANDALONE de auditoria (canivete suíço p/
// clientes, ex.: Kali). É um binário separado do vpsrun (server): não importa
// os módulos de provisionamento — só diagnóstico de rede e varredura, sempre
// limitados ao Escopo_Autorizado.
package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/andersenvieira/vpsrun/internal/audit"
	"github.com/andersenvieira/vpsrun/internal/core"
)

func main() { os.Exit(run(os.Args[1:])) }

func run(args []string) int {
	if len(args) == 0 {
		usage()
		return 2
	}
	switch args[0] {
	case "scope":
		return cmdScope(args[1:])
	case "scan":
		return cmdScan(args[1:])
	case "discover":
		return cmdDiscover(args[1:])
	case "-h", "--help", "help":
		usage()
		return 0
	case "--version":
		fmt.Println("vpsrun-audit v" + core.Version)
		return 0
	default:
		fmt.Fprintln(os.Stderr, "comando desconhecido:", args[0])
		usage()
		return 2
	}
}

func usage() {
	fmt.Println(`vpsrun-audit — suíte de auditoria (uso AUTORIZADO apenas)

  scope add <cidr|ip>     adiciona alvo ao Escopo_Autorizado
  scope list              lista o escopo
  scan <host> [--ports p1,p2,...]   varre portas (exige alvo no escopo)
  discover <cidr>         varredura leve de hosts vivos (exige escopo)

Escopo: ` + core.AuditScopePath() + `
Trilha: ` + core.AuditLogPath() + `

AVISO: só use contra sistemas que você tem autorização explícita para testar.`)
}

func cmdScope(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "uso: scope add <cidr|ip> | scope list")
		return 2
	}
	path := core.AuditScopePath()
	switch args[0] {
	case "add":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "uso: scope add <cidr|ip>")
			return 2
		}
		if err := audit.AppendScope(path, args[1]); err != nil {
			fmt.Fprintln(os.Stderr, "erro:", err)
			return 1
		}
		_ = audit.LogEvent(core.AuditLogPath(), "scope-add", args[1])
		fmt.Println("adicionado ao escopo:", args[1])
		return 0
	case "list":
		s, err := audit.LoadScope(path)
		if err != nil {
			fmt.Fprintln(os.Stderr, "erro:", err)
			return 1
		}
		if s.Empty() {
			fmt.Println("(escopo vazio — nenhuma varredura é permitida)")
			return 0
		}
		for _, e := range s.Entries() {
			fmt.Println("  " + e)
		}
		return 0
	default:
		fmt.Fprintln(os.Stderr, "subcomando de scope desconhecido:", args[0])
		return 2
	}
}

func parsePorts(args []string) []int {
	for i := 0; i < len(args); i++ {
		if args[i] == "--ports" && i+1 < len(args) {
			var ps []int
			for _, tok := range strings.Split(args[i+1], ",") {
				if n, err := strconv.Atoi(strings.TrimSpace(tok)); err == nil {
					ps = append(ps, n)
				}
			}
			if len(ps) > 0 {
				return ps
			}
		}
	}
	return audit.DefaultPorts()
}

func cmdScan(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "uso: scan <host> [--ports ...]")
		return 2
	}
	host := args[0]
	ports := parsePorts(args[1:])

	scope, err := audit.LoadScope(core.AuditScopePath())
	if err != nil {
		fmt.Fprintln(os.Stderr, "erro ao ler escopo:", err)
		return 1
	}
	if scope.Empty() {
		fmt.Fprintln(os.Stderr, "escopo vazio. Adicione o alvo: vpsrun-audit scope add <cidr|ip>")
		return 1
	}
	ip, err := audit.Resolve(host)
	if err != nil {
		fmt.Fprintln(os.Stderr, "erro:", err)
		return 1
	}
	// GATE: recusa fora do escopo.
	if !scope.Allows(ip) {
		_ = audit.LogEvent(core.AuditLogPath(), "scan-RECUSADO-fora-de-escopo", host+" ("+ip+")")
		fmt.Fprintf(os.Stderr, "RECUSADO: %s (%s) está FORA do escopo autorizado.\n", host, ip)
		return 3
	}
	_ = audit.LogEvent(core.AuditLogPath(), "scan", host+" ("+ip+")")
	res := audit.ScanTCP(host, ip, ports, 800*time.Millisecond)
	fmt.Printf("Alvo: %s (%s)  —  %d portas testadas em %s\n", res.Host, res.IP, len(ports), res.Duration.Round(time.Millisecond))
	if len(res.Open) == 0 {
		fmt.Println("  nenhuma porta aberta dentre as testadas")
	} else {
		fmt.Println("  portas ABERTAS:")
		for _, p := range res.Open {
			fmt.Printf("    %d/tcp\n", p)
		}
	}
	return 0
}

func cmdDiscover(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "uso: discover <cidr>")
		return 2
	}
	fmt.Println("descoberta ampla de rede usa nmap; para varredura pontual use 'scan'.")
	fmt.Println("garanta o CIDR no escopo e rode: nmap -sn", args[0])
	_ = audit.LogEvent(core.AuditLogPath(), "discover-hint", args[0])
	return 0
}
