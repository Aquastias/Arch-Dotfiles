for file in ~/.zsh/env/*.zsh; do
  [[ -f "$file" ]] && source "$file"
done  
