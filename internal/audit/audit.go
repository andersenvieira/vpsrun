// Package audit implementa a edição standalone (vpsrun-audit): diagnóstico de
// rede e varredura, SEMPRE limitada a um Escopo_Autorizado.
//
// Regra inegociável: nenhuma varredura ocorre contra alvo fora do escopo.
// Isso não é só ética — é proteção legal ao auditar infraestrutura de terceiros.
package audit

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// Scope é o conjunto autorizado de redes/hosts.
type Scope struct {
	nets  []*net.IPNet
	hosts map[string]bool
}

// NewScope cria um escopo vazio.
func NewScope() *Scope { return &Scope{hosts: map[string]bool{}} }

// Add aceita um CIDR (ex.: 10.0.0.0/24) ou um IP único.
func (s *Scope) Add(entry string) error {
	entry = strings.TrimSpace(entry)
	if entry == "" || strings.HasPrefix(entry, "#") {
		return nil
	}
	if strings.Contains(entry, "/") {
		_, n, err := net.ParseCIDR(entry)
		if err != nil {
			return err
		}
		s.nets = append(s.nets, n)
		return nil
	}
	if net.ParseIP(entry) == nil {
		return fmt.Errorf("entrada inválida de escopo: %q", entry)
	}
	s.hosts[entry] = true
	return nil
}

// Allows indica se um IP está dentro do escopo autorizado.
func (s *Scope) Allows(ip string) bool {
	if s.hosts[ip] {
		return true
	}
	parsed := net.ParseIP(ip)
	if parsed == nil {
		return false
	}
	for _, n := range s.nets {
		if n.Contains(parsed) {
			return true
		}
	}
	return false
}

// Empty indica se o escopo está vazio (nenhuma varredura permitida).
func (s *Scope) Empty() bool { return len(s.nets) == 0 && len(s.hosts) == 0 }

// Entries devolve as entradas legíveis do escopo.
func (s *Scope) Entries() []string {
	var out []string
	for _, n := range s.nets {
		out = append(out, n.String())
	}
	for h := range s.hosts {
		out = append(out, h)
	}
	sort.Strings(out)
	return out
}

// LoadScope lê o escopo de um arquivo (uma entrada por linha).
func LoadScope(path string) (*Scope, error) {
	s := NewScope()
	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return s, nil
		}
		return nil, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if err := s.Add(sc.Text()); err != nil {
			return nil, err
		}
	}
	return s, sc.Err()
}

// AppendScope adiciona uma entrada ao arquivo de escopo.
func AppendScope(path, entry string) error {
	// valida antes de gravar
	if err := NewScope().Add(entry); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = fmt.Fprintln(f, strings.TrimSpace(entry))
	return err
}

// ScanResult é o resultado de uma varredura de portas.
type ScanResult struct {
	Host     string
	IP       string
	Open     []int
	Duration time.Duration
}

// DefaultPorts são portas comuns de serviços.
func DefaultPorts() []int {
	return []int{21, 22, 25, 53, 80, 110, 143, 443, 3306, 3389, 5432, 6379, 8080, 8443, 9090, 10050}
}

// Resolve converte host em IP (retorna o próprio se já for IP).
func Resolve(host string) (string, error) {
	if net.ParseIP(host) != nil {
		return host, nil
	}
	ips, err := net.LookupIP(host)
	if err != nil || len(ips) == 0 {
		return "", fmt.Errorf("não resolveu %q", host)
	}
	return ips[0].String(), nil
}

// ScanTCP faz um connect-scan concorrente das portas dadas.
// PRÉ-CONDIÇÃO: o chamador já validou o escopo.
func ScanTCP(host, ip string, ports []int, timeout time.Duration) ScanResult {
	start := time.Now()
	var (
		mu   sync.Mutex
		open []int
		wg   sync.WaitGroup
	)
	sem := make(chan struct{}, 64) // limita concorrência
	for _, p := range ports {
		wg.Add(1)
		go func(port int) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			addr := net.JoinHostPort(ip, fmt.Sprintf("%d", port))
			c, err := net.DialTimeout("tcp", addr, timeout)
			if err == nil {
				c.Close()
				mu.Lock()
				open = append(open, port)
				mu.Unlock()
			}
		}(p)
	}
	wg.Wait()
	sort.Ints(open)
	return ScanResult{Host: host, IP: ip, Open: open, Duration: time.Since(start)}
}

// LogEvent registra uma linha na trilha de auditoria.
func LogEvent(path, action, target string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()
	user := os.Getenv("USER")
	_, err = fmt.Fprintf(f, "%s\t%s\t%s\t%s\n", time.Now().Format(time.RFC3339), user, action, target)
	return err
}
