# ==========================================================================
# Google Cloud SDK fzf helper functions
# ==========================================================================
{
export GCLOUD_CMD_CACHE_DB="$HOME/.fzf-gcloud-cmd_cache.db"

__gcloud_cmd_cache() {
  # ==========================================================================
  # Create a sqlite database file storing the gcloud API commands.
  #
  # This function will:
  # - create a sqllite database of `gcloud` commands for use with fzf
  # - use the google-cloud-sdk lib/surface subdirectory paths to infer the api
  # - populate the api signatures in the database
  #
  # This function should not be called on each shell startup; rather it
  # should be populated infrequently with updates to the installed SDK.
  # ==========================================================================

  if ! which sqlite3 >/dev/null; then
    echo "Could not find sqlite3 in PATH; please ensure sqlite3 is installed." 1>&2
    return 1
  fi
  if ! which gcloud >/dev/null; then
    echo "Could not find gcloud in PATH; please ensure this is installed." 1>&2
    return 1
  fi

  # create a staging db to populate
  staging_db="$(mktemp -t $(basename "$GCLOUD_CMD_CACHE_DB").XXXXXX)"
  if [ ! $? ]; then
    echo "Error: could not create a temporary staging cachefile." 1>&2
    return 1
  fi

  echo "Rebuilding gcloud command cache in '$GCLOUD_CMD_CACHE_DB'" 1>&2
  sqlite3 "$staging_db" <<eof
    drop table if exists GCLOUD_CMD_CACHE;
    create table GCLOUD_CMD_CACHE(
      api_source_file         text
    , gcloud_cmd_invocation   text
    );
eof

# Determine the path to the gcloud binary, resolving any symlinks with realpath
gcloud_bin_path=$(realpath $(whence -p gcloud))

# Extract the root directory of the gcloud installation
gcloud_root=$(dirname $(dirname "$gcloud_bin_path"))

# Define the path to the gcloud docs folder
gcloud_docs_root="$gcloud_root/lib/surface"

# Check if the gcloud docs folder exists
if [[ ! -d "$gcloud_docs_root" ]]; then
  echo "Could not find a valid gcloud docs folder at: '$gcloud_docs_root'."
  return 1
fi

  for api_source_file in $(find "$gcloud_docs_root" -name '*.py' -o -name '*.yaml'); do
    cmd=$(sed -e "s:/__init__\.py:: ; s:\.yaml:: ; s:\.py:: ; s:$gcloud_docs_root:: ; s:^:gcloud: ; s:_:-:g ; s:/: :g" <<<"$api_source_file")
    is_alpha=0
    is_beta=0

    # Determine the release track of the command, to add the `alpha` or `beta` signature
    if [[ "${api_source_file##*.}" == 'py' ]]; then
      if grep -q 'ReleaseTrack.BETA' "$api_source_file"; then
        is_beta=1
      elif grep -q 'ReleaseTrack.ALPHA' "$api_source_file"; then
        is_alpha=1
      fi
    elif [[ "${api_source_file##*.}" == 'yaml' ]]; then
      if grep -iq 'release_tracks.*beta' "$api_source_file"; then
        is_beta=1
      elif grep -iq 'release_tracks.*alpha' "$api_source_file"; then
        is_alpha=1
      fi
    fi

    # insert the alpha/beta signatures
    if ((is_beta)); then
      cmd=$(sed -e 's:gcloud:gcloud beta:; s:beta beta: beta:' <<<"$cmd")
    elif ((is_alpha)); then
      cmd=$(sed -e 's:gcloud:gcloud alpha:; s:alpha alpha:alpha:' <<<"$cmd")
    fi

    # Populate the local gcloud command database
    echo "Adding invocation for '$cmd' (build from $api_source_file)" 1>&2
    sqlite3 "$staging_db" "insert into GCLOUD_CMD_CACHE values('$api_source_file', '$cmd');"
  done

  # Swap the staging db file into the production file
  mv "$staging_db" "$GCLOUD_CMD_CACHE_DB"
  return 0
}

__gcloud_sel() {
  # ==========================================================================
  # Create a fzf-ified list of `gcloud` commands to for google SDK CLI usage.
  #
  # This function will:
  # - select * from a sqllite database of `gcloud` commands
  # - pipe the commands into `fzf`, with a preview window
  #
  # Please note that if the local database will be populated if it is not found,
  # which can take 1--2 minutes.
  # ==========================================================================
  local selected num
  setopt localoptions noglobsubst noposixbuiltins pipefail no_aliases 2> /dev/null

  if [ ! -r "$GCLOUD_CMD_CACHE_DB" ]; then
    echo "No gcloud command cache db found; trying to repopulate." 1>&2
    __gcloud_cmd_cache
    if [ ! $? ]; then
      echo "An error occurred caching the gcloud api; exiting." 1>&2
      return 1
    fi
  fi

  # Determine the path to the gcloud binary, resolving any symlinks with realpath
  gcloud_bin_path=$(realpath $(whence -p gcloud))
  gcloud_bin_root=$(dirname "$gcloud_bin_path")
  if [ -z "$gcloud_bin_root" ]; then
    echo "An error occurred; could not find the gcloud bin directory." 1>&2
    return 1
  fi

  local cmd="sqlite3 '$GCLOUD_CMD_CACHE_DB' 'select gcloud_cmd_invocation from GCLOUD_CMD_CACHE;'"
  eval "$cmd" | FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS -n2..,.. --tiebreak=index --bind=ctrl-r:toggle-sort,ctrl-z:ignore $FZF_CTRL_R_OPTS --query=${(qqq)LBUFFER} +m" $(__fzfcmd) --preview="eval '$gcloud_bin_root/{} --help'" | while read item; do
    echo -n "${item} "
  done
  local ret=$?
  echo
  return $ret
}

fzf-gcloud-widget() {
  # ==========================================================================
  # Create the fzf-gcloud widget
  # ==========================================================================
  LBUFFER="$(__gcloud_sel)"
  local ret=$?
  zle reset-prompt
  return $ret
}
# Bind the gcloud fzf helper to CTRL-I
zle     -N   fzf-gcloud-widget
bindkey '^k' fzf-gcloud-widget

} always {
  eval $__fzf_key_bindings_options
  'unset' '__fzf_key_bindings_options'
}
