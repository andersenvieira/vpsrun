#!/usr/bin/env bash
###############################################################################
# tuning-cpu.sh — governor de CPU (idempotente e reversível)
#
#   show    : governor atual de cada núcleo [padrão]
#   apply   : define 'performance' (backup antes)
#   revert  : restaura o governor salvo
#
# Em VPS o cpufreq pode não estar disponível; nesse caso o script informa.
###############################################################################
set -uo pipefail

BACKUP=/var/backups/vpsrun-tuning/cpu.governor.txt
ACTION="${1:-show}"
GLOB=/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

has_cpufreq() { compgen -G "$GLOB" >/dev/null 2>&1; }

show() {
  echo "== CPU =="
  echo "modelo: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
  echo "nucleos: $(nproc)"
  if has_cpufreq; then
    echo "governors por nucleo:"
    for f in $GLOB; do echo "  $f = $(cat "$f")"; done
    avail=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null)
    echo "disponiveis: ${avail:-?}"
  else
    echo "cpufreq indisponivel nesta VPS (governor gerenciado pelo host)."
  fi
}

apply() {
  [ "$(id -u)" -eq 0 ] || { echo "apply requer root"; exit 1; }
  has_cpufreq || { echo "cpufreq indisponivel; nada a aplicar."; exit 0; }
  mkdir -p "$(dirname "$BACKUP")"
  [ -f "$BACKUP" ] || cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor > "$BACKUP"
  for f in $GLOB; do echo performance > "$f" 2>/dev/null || true; done
  echo "governor 'performance' aplicado (backup: $BACKUP)."
}

revert() {
  [ "$(id -u)" -eq 0 ] || { echo "revert requer root"; exit 1; }
  has_cpufreq || { echo "cpufreq indisponivel."; exit 0; }
  local g="ondemand"; [ -f "$BACKUP" ] && g="$(cat "$BACKUP")"
  for f in $GLOB; do echo "$g" > "$f" 2>/dev/null || true; done
  echo "governor restaurado para '$g'."
}

case "$ACTION" in
  show) show ;; apply) apply ;; revert) revert ;;
  *) echo "uso: $0 [show|apply|revert]"; exit 2 ;;
esac
