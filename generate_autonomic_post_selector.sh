#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"

echo 'Generating autonomic post selector script...' 1>&2
echo "  sources: $TWEET_BASE_DIR/scheduled" 1>&2
echo "  output : $autonomic_post_selector" 1>&2

cat << FIN > "$autonomic_post_selector"
#!/usr/bin/env bash
#
# This file is generated by "generate_autonomic_post_selector.sh".
# Do not modify this file manually.

base_dir="\$(cd "\$(dirname "\$0")" && pwd)"

choose_random_one() {
  local input="\$(cat)"
  local n_lines="\$(echo "\$input" | wc -l)"
  local index=\$(((\$RANDOM % \$n_lines) + 1))
  echo "\$input" | sed -n "\${index}p"
}

extract_response() {
  local source="\$1"
  if [ ! -f "\$source" ]
  then
    echo ""
    return 0
  fi

  local responses="\$(cat "\$source")"

  [ "\$responses" = '' ] && return 1

  echo "\$responses" | choose_random_one
}

FIN

cd "$TWEET_BASE_DIR"

if [ -d ./scheduled ]
then
  for group in all morning noon afternoon evening night midnight
  do
    messages_file="$status_dir/scheduled_$group.txt"
    echo '' > "${messages_file}.tmp"
    ls ./scheduled/$group* |
      sort |
      while read path
    do
      # convert CR+LF => LF for safety.
      nkf -Lu "$path" >> "${messages_file}.tmp"
      echo '' >> "$messages_file"
    done
    egrep -v "^#|^[$whitespaces]*$" "${messages_file}.tmp" > "$messages_file"
    rm -rf "${messages_file}.tmp"
  done

  cat << FIN >> "$autonomic_post_selector"
[ "\$DEBUG" != '' ] && echo "Choosing message from \"$status_dir/all.txt\"" 1>&2
extract_response "$status_dir/all.txt"
exit \$?
FIN
fi

cat << FIN >> "$autonomic_post_selector"

exit 1
FIN

chmod +x "$autonomic_post_selector"
