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

# Prompt: user in periwinkle, path in grey, git branch in lilac; the chevron
# turns rose when the last command failed. Truecolour where the terminal
# supports it; zsh approximates on the TTY.
autoload -Uz vcs_info
zstyle ':vcs_info:git:*' formats ' %F{#C3B7EE}%b%f'
precmd_functions+=(vcs_info)
setopt PROMPT_SUBST
PROMPT='%F{#8A9BF7}%n%f %F{#8B90B0}%~%f${vcs_info_msg_0_} %(?.%F{#8A9BF7}.%F{#F28B9B})›%f '
RPROMPT=''
