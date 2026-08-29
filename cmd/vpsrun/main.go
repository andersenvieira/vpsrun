// Command vpsrun é o assistente de terminal para provisionar, operar e
// replicar VPS Debian. Edição "server".
package main

import (
	"flag"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/andersenvieira/vpsrun/internal/core"
	"github.com/andersenvieira/vpsrun/internal/ui"
)

func main() {
	// Subcomandos não-interativos (antes do flag.Parse).
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "vault":
			os.Exit(runVaultCLI(os.Args[2:]))
		case "tuning":
			os.Exit(runTuningCLI(os.Args[2:]))
		}
	}

	var (
		showVersion = flag.Bool("version", false, "mostra a versão e sai")
		selfcheck   = flag.Bool("selfcheck", false, "valida o ambiente (não-interativo) e sai")
	)
	flag.Parse()

	if *showVersion {
		fmt.Println("vpsrun v" + core.Version)
		return
	}

	if *selfcheck {
		runSelfcheck()
		return
	}

	// TUI exige terminal. Sem TTY, orienta o uso em vez de travar.
	if !isTerminal(os.Stdout) {
		fmt.Println("vpsrun v" + core.Version)
		fmt.Println("Esta é uma aplicação interativa (TUI). Rode num terminal.")
		fmt.Println("Diagnóstico não-interativo: vpsrun --selfcheck")
		return
	}

	p := tea.NewProgram(ui.New(), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "erro na TUI:", err)
		os.Exit(1)
	}
}

func isTerminal(f *os.File) bool {
	st, err := f.Stat()
	if err != nil {
		return false
	}
	return (st.Mode() & os.ModeCharDevice) != 0
}

func runSelfcheck() {
	fmt.Println("vpsrun v" + core.Version + " — selfcheck")
	fmt.Println("scripts dir :", core.ScriptsDir())
	if core.VaultExists() {
		fmt.Println("cofre       :", core.VaultPath(), "(existe)")
	} else {
		fmt.Println("cofre       :", core.VaultPath(), "(ainda não criado)")
	}
	fmt.Println("status      : OK")
}
