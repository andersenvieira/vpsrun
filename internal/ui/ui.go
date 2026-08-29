// Package ui implementa a interface de terminal (TUI) do vpsrun com Bubble Tea.
package ui

import (
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/andersenvieira/vpsrun/internal/core"
	"github.com/andersenvieira/vpsrun/internal/resolvers"
	"github.com/andersenvieira/vpsrun/internal/runner"
	"github.com/andersenvieira/vpsrun/internal/vault"
)

// estados da TUI
const (
	stMenu = iota
	stOutput
	stMaster
	stVault
	stReveal
)

var (
	titleStyle    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("81")).Padding(0, 1)
	subtitleStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	selStyle      = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("0")).Background(lipgloss.Color("81")).Padding(0, 1)
	itemStyle     = lipgloss.NewStyle().Padding(0, 1)
	helpStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("240")).Padding(1, 1)
	errStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("203"))
	okStyle       = lipgloss.NewStyle().Foreground(lipgloss.Color("120"))
	boxStyle      = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("240")).Padding(0, 1)
)

type node struct {
	title    string
	children []*node
	action   func(m *model) tea.Cmd
}

type actionResultMsg struct {
	title  string
	output string
	err    error
}

type model struct {
	scriptsDir string
	runner     *runner.Runner

	path   []*node
	cursor []int

	state   int
	message string

	outputTitle string
	output      string

	// cofre
	input       string
	afterUnlock int
	v           *vault.Vault
	entries     []vault.Entry
	vCursor     int
	reveal      string

	width, height int
}

// New cria o modelo inicial da TUI.
func New() tea.Model {
	sd := core.ScriptsDir()
	root := buildMenu()
	return &model{
		scriptsDir: sd,
		runner:     runner.New(sd),
		path:       []*node{root},
		cursor:     []int{0},
		state:      stMenu,
	}
}

func (m *model) Init() tea.Cmd { return nil }

func (m *model) cur() *node       { return m.path[len(m.path)-1] }
func (m *model) curCursor() int   { return m.cursor[len(m.cursor)-1] }
func (m *model) setCursor(i int)  { m.cursor[len(m.cursor)-1] = i }

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, nil

	case actionResultMsg:
		m.outputTitle = msg.title
		if msg.err != nil {
			m.output = errStyle.Render("erro: "+msg.err.Error()) + "\n\n" + msg.output
		} else {
			m.output = msg.output
		}
		m.state = stOutput
		return m, nil

	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m *model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Encerrar sempre disponível.
	if msg.Type == tea.KeyCtrlC {
		return m, tea.Quit
	}

	switch m.state {
	case stMaster:
		return m.keyMaster(msg)
	case stOutput:
		if k := msg.String(); k == "esc" || k == "enter" || k == "q" {
			m.state = stMenu
		}
		return m, nil
	case stReveal:
		if k := msg.String(); k == "esc" || k == "enter" || k == "q" {
			m.reveal = ""
			m.state = stVault
		}
		return m, nil
	case stVault:
		return m.keyVault(msg)
	default:
		return m.keyMenu(msg)
	}
}

func (m *model) keyMenu(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	items := m.cur().children
	switch msg.String() {
	case "q":
		return m, tea.Quit
	case "up", "k":
		if c := m.curCursor(); c > 0 {
			m.setCursor(c - 1)
		}
	case "down", "j":
		if c := m.curCursor(); c < len(items)-1 {
			m.setCursor(c + 1)
		}
	case "esc", "backspace", "left", "h":
		if len(m.path) > 1 {
			m.path = m.path[:len(m.path)-1]
			m.cursor = m.cursor[:len(m.cursor)-1]
		}
	case "enter", "right", "l":
		if len(items) == 0 {
			return m, nil
		}
		sel := items[m.curCursor()]
		if sel.action != nil {
			m.message = ""
			return m, sel.action(m)
		}
		m.path = append(m.path, sel)
		m.cursor = append(m.cursor, 0)
	}
	return m, nil
}

func (m *model) keyMaster(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyEsc:
		m.input = ""
		m.state = stMenu
		return m, nil
	case tea.KeyEnter:
		return m.unlockVault()
	case tea.KeyBackspace:
		if len(m.input) > 0 {
			m.input = m.input[:len(m.input)-1]
		}
		return m, nil
	case tea.KeySpace:
		m.input += " "
		return m, nil
	case tea.KeyRunes:
		m.input += string(msg.Runes)
		return m, nil
	}
	return m, nil
}

func (m *model) keyVault(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc", "q", "backspace":
		m.state = stMenu
	case "up", "k":
		if m.vCursor > 0 {
			m.vCursor--
		}
	case "down", "j":
		if m.vCursor < len(m.entries)-1 {
			m.vCursor++
		}
	case "enter":
		if len(m.entries) == 0 {
			return m, nil
		}
		e := m.entries[m.vCursor]
		if e.Mode == vault.ModeDynamic && e.Source != nil {
			val, err := resolvers.ResolveWithTimeout(*e.Source, 8*time.Second)
			if err != nil {
				m.reveal = errStyle.Render("erro ao resolver: " + err.Error())
			} else {
				m.reveal = okStyle.Render("[dinâmico · lido ao vivo]") + "\n" + val
			}
		} else {
			val, err := m.v.RevealStatic(e.ID)
			if err != nil {
				m.reveal = errStyle.Render("erro: " + err.Error())
			} else {
				m.reveal = okStyle.Render("[estático · decifrado]") + "\n" + val
			}
		}
		m.state = stReveal
	}
	return m, nil
}

func (m *model) unlockVault() (tea.Model, tea.Cmd) {
	pass := m.input
	m.input = ""
	path := core.VaultPath()
	var v *vault.Vault
	var err error
	if core.VaultExists() {
		v, err = vault.Open(path, pass)
	} else {
		v, err = vault.Create(path, pass)
	}
	if err != nil {
		m.outputTitle = "Cofre"
		m.output = errStyle.Render("Falha ao abrir o cofre: " + err.Error())
		m.state = stOutput
		return m, nil
	}
	m.v = v
	m.entries = v.List()
	m.vCursor = 0
	m.state = stVault
	return m, nil
}

func (m *model) View() string {
	switch m.state {
	case stMaster:
		return m.viewMaster()
	case stOutput:
		return m.viewOutput()
	case stReveal:
		return m.viewReveal()
	case stVault:
		return m.viewVault()
	default:
		return m.viewMenu()
	}
}

func header() string {
	return titleStyle.Render("vpsrun") + subtitleStyle.Render("  assistente de VPS  ·  v"+core.Version)
}

func (m *model) viewMenu() string {
	var b strings.Builder
	b.WriteString(header() + "\n\n")
	// trilha de navegação
	var trail []string
	for _, n := range m.path {
		trail = append(trail, n.title)
	}
	b.WriteString(subtitleStyle.Render(strings.Join(trail, " › ")) + "\n\n")

	for i, it := range m.cur().children {
		line := it.title
		if it.action == nil {
			line += "  ›"
		}
		if i == m.curCursor() {
			b.WriteString(selStyle.Render("➤ "+line) + "\n")
		} else {
			b.WriteString(itemStyle.Render("  "+line) + "\n")
		}
	}
	if m.message != "" {
		b.WriteString("\n" + subtitleStyle.Render(m.message) + "\n")
	}
	b.WriteString(helpStyle.Render("↑/↓ navegar · enter selecionar · esc voltar · q sair"))
	return b.String()
}

func (m *model) viewMaster() string {
	var b strings.Builder
	b.WriteString(header() + "\n\n")
	action := "Abrir cofre"
	if !core.VaultExists() {
		action = "Criar novo cofre (defina a senha master)"
	}
	b.WriteString(titleStyle.Render("🔒 "+action) + "\n\n")
	b.WriteString("Senha master: " + strings.Repeat("•", len(m.input)) + "▌\n")
	b.WriteString(helpStyle.Render("enter confirmar · esc cancelar"))
	return b.String()
}

func (m *model) viewVault() string {
	var b strings.Builder
	b.WriteString(header() + "\n\n")
	b.WriteString(titleStyle.Render("🔒 Cofre de Credenciais") + "  " + subtitleStyle.Render(m.v.Path()) + "\n\n")
	if len(m.entries) == 0 {
		b.WriteString(subtitleStyle.Render("Cofre vazio. Adicione entradas via CLI ou nas próximas versões da UI.") + "\n")
	}
	for i, e := range m.entries {
		tag := "estático"
		if e.Mode == vault.ModeDynamic {
			tag = "dinâmico"
		}
		line := fmt.Sprintf("%-10s %-14s %-14s %s", e.Group, e.App, e.Type, e.Label)
		line += subtitleStyle.Render("  [" + tag + "]")
		if i == m.vCursor {
			b.WriteString(selStyle.Render("➤ "+line) + "\n")
		} else {
			b.WriteString(itemStyle.Render("  "+line) + "\n")
		}
	}
	b.WriteString(helpStyle.Render("↑/↓ navegar · enter revelar/resolver · esc voltar"))
	return b.String()
}

func (m *model) viewReveal() string {
	var b strings.Builder
	b.WriteString(header() + "\n\n")
	b.WriteString(titleStyle.Render("Valor") + "\n\n")
	b.WriteString(boxStyle.Render(m.reveal) + "\n")
	b.WriteString(helpStyle.Render("enter/esc voltar"))
	return b.String()
}

func (m *model) viewOutput() string {
	var b strings.Builder
	b.WriteString(header() + "\n\n")
	b.WriteString(titleStyle.Render(m.outputTitle) + "\n\n")
	out := m.output
	if m.height > 0 {
		lines := strings.Split(out, "\n")
		max := m.height - 8
		if max > 3 && len(lines) > max {
			lines = lines[:max]
			lines = append(lines, subtitleStyle.Render("… (saída truncada)"))
		}
		out = strings.Join(lines, "\n")
	}
	b.WriteString(boxStyle.Render(out) + "\n")
	b.WriteString(helpStyle.Render("enter/esc voltar"))
	return b.String()
}

// ---- ações ----

func runScriptAction(title, script string, args ...string) func(*model) tea.Cmd {
	return func(m *model) tea.Cmd {
		m.outputTitle = title
		m.output = "Executando…"
		m.state = stOutput
		return func() tea.Msg {
			out, err := m.runner.RunScript(script, args, nil, 3*time.Minute)
			return actionResultMsg{title: title, output: out, err: err}
		}
	}
}

func runCmdAction(title, name string, args ...string) func(*model) tea.Cmd {
	return func(m *model) tea.Cmd {
		m.outputTitle = title
		m.output = "Executando…"
		m.state = stOutput
		return func() tea.Msg {
			out, err := runner.RunCommand(30*time.Second, name, args...)
			return actionResultMsg{title: title, output: out, err: err}
		}
	}
}

func openVaultAction(m *model) tea.Cmd {
	m.input = ""
	m.afterUnlock = stVault
	m.state = stMaster
	return nil
}

func tuningHelp(m *model) tea.Cmd {
	m.outputTitle = "Tuning — aplicar e reverter"
	m.output = "As telas acima só MOSTRAM o estado (seguro).\n\n" +
		"Para aplicar ou reverter (altera o sistema, exige root):\n\n" +
		okStyle.Render("  sudo vpsrun tuning rede apply") + "\n" +
		okStyle.Render("  sudo vpsrun tuning ram  apply") + "\n" +
		okStyle.Render("  sudo vpsrun tuning cpu  apply") + "\n\n" +
		"Cada apply faz backup dos valores atuais; 'revert' restaura.\n" +
		"Áreas: rede (BBR/fq/buffers), ram (swappiness/cache), cpu (governor)."
	m.state = stOutput
	return nil
}

func placeholder(desc string) func(*model) tea.Cmd {
	return func(m *model) tea.Cmd {
		m.outputTitle = "Em construção"
		m.output = "Este módulo será ligado ao executor:\n\n  " + okStyle.Render(desc) +
			"\n\nA fundação (TUI, cofre, resolvers, runner) já está funcional;\n" +
			"as ações de sistema entram nas próximas tarefas da spec."
		m.state = stOutput
		return nil
	}
}

func buildMenu() *node {
	return &node{title: "Menu principal", children: []*node{
		{title: "1 · Instalação & Provisionamento", children: []*node{
			{title: "Stack base (nginx · PHP-FPM · MariaDB · Docker)", action: placeholder("scripts/setup-vps.sh")},
			{title: "Acesso remoto XRDP (perfis mobile/PC)", action: placeholder("scripts/setup-vps.sh (bloco XRDP)")},
			{title: "WhatsApp — API Oficial Meta", action: placeholder("módulo meta (tokens no cofre)")},
			{title: "Chatwoot (opcional · canal Meta)", action: placeholder("módulo chatwoot")},
			{title: "Replicar esta VPS", action: runScriptAction("Replicar VPS (dry-run)", "setup-vps.sh", "--help")},
		}},
		{title: "2 · Cofre de Credenciais 🔒", action: openVaultAction},
		{title: "3 · Monitoramento (Zabbix + Ansible)", children: []*node{
			{title: "Instalar Zabbix (server/frontend/db)", action: placeholder("ansible/zabbix")},
			{title: "Grafana (opcional)", action: placeholder("ansible/grafana")},
			{title: "Descoberta de rede + agentes", action: placeholder("ansible/discovery")},
		}},
		{title: "4 · Backup & Restauração", children: []*node{
			{title: "Rodar backup agora", action: runScriptAction("Backup", "backup-vps.sh")},
			{title: "Testar restauração (schema temp)", action: runScriptAction("Teste de restauração", "testar-restauracao.sh")},
		}},
		{title: "5 · Tuning & Performance", children: []*node{
			{title: "Uso de disco", action: runCmdAction("Disco", "df", "-h", "/")},
			{title: "Memória / zram (mostrar)", action: runScriptAction("Tuning RAM", "tuning-ram.sh", "show")},
			{title: "Rede / BBR (mostrar)", action: runScriptAction("Tuning Rede", "tuning-rede.sh", "show")},
			{title: "CPU / governor (mostrar)", action: runScriptAction("Tuning CPU", "tuning-cpu.sh", "show")},
			{title: "Limpeza — relatório de espaço", action: runScriptAction("Limpeza (relatório)", "limpeza-relatorio.sh")},
			{title: "Como aplicar (apply/revert)", action: tuningHelp},
		}},
		{title: "6 · Updates Guiados", action: placeholder("módulo updates (inventário)")},
		{title: "7 · Saúde do Sistema", action: runScriptAction("Saúde do Sistema", "verificar-saude.sh")},
	}}
}
