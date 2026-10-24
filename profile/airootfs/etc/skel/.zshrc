# forge-os default shell config: Oh My Zsh for its plugins, with a quiet
# Forge Glass prompt instead of a theme:   you ~/Projects main ›
export ZSH="/usr/share/oh-my-zsh"
ZSH_THEME=""

plugins=(git sudo)

source "$ZSH/oh-my-zsh.sh"

# Arch-packaged plugins (not managed through Oh My Zsh's own custom/ dir).
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fpath+=(/usr/share/zsh/site-functions)

# Prompt: user in the theme's accent, path in grey, git branch in a softer
# accent; the chevron turns rose when the last command failed. Truecolour
# where the terminal supports it; zsh approximates on the TTY.
#
# The colours are the Forge theme's (forge-theme-sync writes theme.sh), read
# again whenever that file changes, so open terminals follow a new theme at
# their next prompt. Until then: stock Forge Glass.
FORGE_ACCENT='#8A9BF7' FORGE_ACCENT_SOFT='#C3B7EE' FORGE_DIM='#8B90B0' FORGE_ERROR='#F28B9B'
zmodload -F zsh/stat b:zstat 2>/dev/null
typeset -g _forge_theme_file=${XDG_CONFIG_HOME:-$HOME/.config}/forge/theme.sh _forge_theme_mtime=0
_forge_theme() {
    local -a mtime
    zstat -A mtime +mtime -- $_forge_theme_file 2>/dev/null || return 0
    (( mtime[1] == _forge_theme_mtime )) && return 0
    _forge_theme_mtime=$mtime[1]
    source $_forge_theme_file
    zstyle ':vcs_info:git:*' formats " %F{$FORGE_ACCENT_SOFT}%b%f"
}

autoload -Uz vcs_info
zstyle ':vcs_info:git:*' formats " %F{$FORGE_ACCENT_SOFT}%b%f"
precmd_functions+=(_forge_theme vcs_info)
setopt PROMPT_SUBST
PROMPT='%F{$FORGE_ACCENT}%n%f %F{$FORGE_DIM}%~%f${vcs_info_msg_0_} %(?.%F{$FORGE_ACCENT}.%F{$FORGE_ERROR})›%f '
RPROMPT=''
