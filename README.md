# fzf-gcloud

## Summary
`fzf-gcloud` is a [`zsh`](https://en.wikipedia.org/wiki/Z_shell) script lets you browse the [`gcloud`](https://cloud.google.com/sdk/gcloud/) CLI api with [`fzf`](https://github.com/junegunn/fzf).

It adds a keybinding on `CTRL-P` to browse the currently installed `gcloud` CLI API with `fzf`, to help navigate the many commands quickly:
![Usage preview](usage_preview.gif)

## Requirements
- `fzf` (`brew install fzf`)
- `gcloud` (`brew install --cask google-cloud-sdk`)
- `sqlite3` (`brew install sqlite`)

## Installation

### Manual Installation
1. Download the shell functions from this repo:
```zsh
curl https://raw.githubusercontent.com/mbhynes/fzf-gcloud/main/gcloud-fzf.zsh > $HOME/.fzf-gcloud.zsh
```
2. Add the following lines in your `~/.zshrc` to source the functions to source them:
```zsh
[ -f ~/.fzf-gcloud.zsh ] && source ~/.fzf-gcloud.zsh
```
### zsh Packge Manager Installation
Something like this probably works?
```zsh
zgen load 'mbhynes/fzf-gcloud'
```

### Usage
- The widget is by default bound to the keybinding `CTRL-P` (`'^P'`)
- You can alter this by changing the `bindkey` line in the `.fzf-gcloud.zsh` file (or whatever you named it), as noted below:
```zsh
fzf-gcloud-widget() {
  # ==========================================================================
  # Bind the gcloud fzf helper to CTRL-P
  # ==========================================================================
  LBUFFER="$(__gcloud_sel)"
  local ret=$?
  zle reset-prompt
  return $ret
}
zle     -N   fzf-gcloud-widget
bindkey '^P' fzf-gcloud-widget # <--- change if you prefer a different keybinding
```

## Implementation

### Summary
The `gcloud` completion mechanism works in the following way:
- we create a local cache (`sqlite` database) of `gcloud` commands for use with `fzf`
- when the keybinding is invoked, the commands in this cache are piped into `fzf` with a `--preview` option to display each command's `--help` docs

### Caching the `gcloud` signature
The local `sqlite` database is populated is a notably not-fancy way:
- we determine the `google-cloud-sdk` root directory from the `gcloud` path (for `brew` users this will be: `"$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk`
- the signature of each `gcloud` command is inferred from the python filenames and directory structure in the `lib/surface` of the `google-cloud-sdk`
- we detect whether the `alpha` or `beta` release track flags are required in each file, and use this to update the `gcloud` invocation, as appropriate
- the cache is saved to `"$HOME/.gcloud_cmd_cache.db"`, which database contains only 1 simple table with schema:
```sql
    create table GCLOUD_CMD_CACHE(
      api_source_file         text
    , gcloud_cmd_invocation   text
    );
```
- If you're interested, you may browse/update the contents of this cache:
```bash
sqlite3 $HOME/.gcloud_cmd_cache.db "select * from gcloud_cmd_cache where gcloud_cmd_invocation like '%alpha%' order by api_source_file limit 5;"
```
```
/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/lib/surface/access_approval/__init__.py|gcloud alpha access-approval
/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/lib/surface/access_context_manager/cloud_bindings/__init__.py|gcloud alpha access-context-manager cloud-bindings
/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/lib/surface/access_context_manager/cloud_bindings/create.py|gcloud alpha access-context-manager cloud-bindings create
/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/lib/surface/access_context_manager/cloud_bindings/update.py|gcloud alpha access-context-manager cloud-bindings update
/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/lib/surface/admin_service_cluster/__init__.py|gcloud alpha admin-service-cluster
```

Please note: there's probably a better way to do this. But this works, is very directly understandable, and only takes about a minute to populate ¯\_(ツ)_/¯.

### Updating the Cache
There's no magic here. After sourcing the functions, just re-run:
```zsh
__gcloud_cmd_cache
```
