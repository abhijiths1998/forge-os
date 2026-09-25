# forge-os default shell config: Oh My Zsh + autosuggestions + syntax
# highlighting. Feel free to change ZSH_THEME (see /usr/share/oh-my-zsh/themes/
# for the full list, or install powerlevel10k for something fancier).
export ZSH="/usr/share/oh-my-zsh"
ZSH_THEME="agnoster"

plugins=(git sudo)

source "$ZSH/oh-my-zsh.sh"

# Arch-packaged plugins (not managed through Oh My Zsh's own custom/ dir).
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fpath+=(/usr/share/zsh/site-functions)
