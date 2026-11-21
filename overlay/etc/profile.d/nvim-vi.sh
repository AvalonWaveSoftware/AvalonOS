# AvalonOS: vi is neovim (ADR 0013)
# Interactive shells only. /usr/bin/vi stays vim-minimal's (RPMs must not
# replace another package's file or own /usr/local); EDITOR/VISUAL cover tools.
alias vi=nvim
export EDITOR=nvim
export VISUAL=nvim
