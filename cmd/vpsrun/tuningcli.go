package main

import (
	"fmt"
	"os"
	"time"

	"github.com/andersenvieira/vpsrun/internal/core"
	"github.com/andersenvieira/vpsrun/internal/runner"
)

// runTuningCLI trata `vpsrun tuning <area> [show|apply|revert]`.
//
// show é seguro (read-only). apply/revert alteram o sistema e exigem root:
//   sudo vpsrun tuning rede apply
func runTuningCLI(args []string) int {
	if len(args) == 0 {
		fmt.Println(`uso: vpsrun tuning <area> [acao]
  area : rede | ram | cpu
  acao : show (padrao) | apply | revert
apply/revert exigem root:  sudo vpsrun tuning rede apply`)
		return 2
	}
	area := args[0]
	action := "show"
	if len(args) > 1 {
		action = args[1]
	}
	var script string
	switch area {
	case "rede":
		script = "tuning-rede.sh"
	case "ram":
		script = "tuning-ram.sh"
	case "cpu":
		script = "tuning-cpu.sh"
	default:
		fmt.Fprintln(os.Stderr, "area desconhecida:", area)
		return 2
	}
	switch action {
	case "show", "apply", "revert":
	default:
		fmt.Fprintln(os.Stderr, "acao desconhecida:", action)
		return 2
	}
	r := runner.New(core.ScriptsDir())
	out, err := r.RunScript(script, []string{action}, nil, 60*time.Second)
	fmt.Print(out)
	if err != nil {
		fmt.Fprintln(os.Stderr, "erro:", err)
		return 1
	}
	return 0
}
