# This file is sourced through BASH_ENV only by the promo renderer process.
# Automated UI activity must not dismiss a take, so capture mode treats the
# saver as focused and ignores the terminal's one-byte wake reads.

hyprctl() {
  if [[ ${1:-} == activewindow && ${2:-} == -j ]]; then
    printf '{"class":"org.omarchy.screensaver"}\n'
    return 0
  fi
  command /usr/bin/hyprctl "$@"
}

read() {
  local option
  for option in "$@"; do
    if [[ $option == -rsn1 ]]; then
      return 1
    fi
  done
  builtin read "$@"
}
