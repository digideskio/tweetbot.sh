#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"

echo 'Generating monologue selector script...' 1>&2
echo "  sources: $TWEET_BASE_DIR/monologues" 1>&2
echo "  output : $monologue_selector" 1>&2

cat << FIN > "$monologue_selector"
#!/usr/bin/env bash
#
# This file is generated by "generate_monologue_selector.sh".
# Do not modify this file manually.

base_dir="\$(cd "\$(dirname "\$0")" && pwd)"

case \$(uname) in
  Darwin|*BSD|CYGWIN*)
    esed="sed -E"
    ;;
  *)
    esed="sed -r"
    ;;
esac

extract_message() {
  local source="\$1"
  if [ ! -f "\$source" ]
  then
    echo ""
    return 0
  fi

  local messages="\$(cat "\$source")"
  [ "\$messages" = '' ] && return 1
  echo "\$messages" | shuf -n 1
}

echo_with_probability() {
  if [ \$(($RANDOM % 100)) -lt \$1 ]
  then
    cat
  fi
}

time_to_minutes() {
  local now="\$1"
  local hours=\$(echo "\$now" | \$esed 's/^0?([0-9]+):.*\$/\1/')
  local minutes=\$(echo "\$now" | \$esed 's/^[^:]*:0?([0-9]+)\$/\1/')
  echo \$(( \$hours * 60 + \$minutes ))
}

date_matcher='0*([0-9*]+).0*([0-9*]+).0*([0-9*]+)'

date_to_serial() {
  local date="\$1"
  local year=\$(echo "\$date" | \$esed "s/^\$date_matcher\$/\1/")
  local month=\$(echo "\$date" | \$esed "s/^\$date_matcher\$/\2/")
  local day=\$(echo "\$date" | \$esed "s/^\$date_matcher\$/\3/")
  [ "\$year" = '*' ] && year=\$(date +%Y | \$esed 's/^0+//')
  [ "\$month" = '*' ] && month=\$(date +%m | \$esed 's/^0+//')
  [ "\$day" = '*' ] && day=\$(date +%d | \$esed 's/^0+//')
  echo \$(( (\$year * 10000) + (\$month * 100) + \$day ))
}

now=\$1
[ "\$now" = '' ] && now="\$(date +%H:%M)"
now=\$(time_to_minutes \$now)

FIN

cd "$TWEET_BASE_DIR"

if [ -d ./monologues ]
then
  cat << FIN >> "$monologue_selector"
[ "\$DEBUG" != '' ] && echo "Finding seasonal message..." 1>&2
message="\$(ls $TWEET_BASE_DIR/monologues/seasonal* |
              while read path
            do
              should_use=0

              date_span="\$(egrep '^# *date:' \$path | \$esed 's/^#[^:]+:[^0-9]*//')"
              if [ "\$date_span" != '' ]
              then
                start="\$(echo "\$date_span" | \$esed "s/\$date_matcher-\$date_matcher/\1.\2.\3/")"
                start="\$(date_to_serial "\$start")"
                end="\$(echo "\$date_span" | \$esed "s/\$date_matcher-\$date_matcher/\4.\5.\6/")"
                end="\$(date_to_serial "\$end")"
                today="\$(date_to_serial "\$(date +%Y.%m.%d)")"
                [ \$start -gt \$today ] && continue
                [ \$end -lt \$today ] && continue
                should_use=1
              fi

              [ \$should_use -eq 0 ] && continue

              # convert CR+LF => LF for safety.
              nkf -Lu "\$path" |
                grep -v '^#'
            done | echo_with_probability $SEASONAL_TOPIC_PROBABILITY)"
if [ "\$message" != '' ]
then
  echo "\$message"
  exit \$?
fi

FIN

  for group in $(echo "$MONOLOGUE_TIME_SPAN" | $esed "s/[$whitespaces]+/ /g") all
  do
    timespans="$(echo "$group" | cut -d '/' -f 2-)"
    group="$(echo "$group" | cut -d '/' -f 1)"
    messages_file="$status_dir/monologue_$group.txt"
    echo '' > "${messages_file}.tmp"
    ls ./monologues/$group* |
      sort |
      while read path
    do
      # convert CR+LF => LF for safety.
      nkf -Lu "$path" >> "${messages_file}.tmp"
      echo '' >> "$messages_file"
    done
    egrep -v "^#|^[$whitespaces]*$" "${messages_file}.tmp" |
      shuf > "$messages_file"
    rm -rf "${messages_file}.tmp"

    if [ "$timespans" != "$group" ]
    then
      for timespan in $(echo "$timespans" | sed 's/,/ /g')
      do
        start="$(echo "$timespan" | cut -d '-' -f 1)"
        start="$(time_to_minutes "$start")"
        end="$(echo "$timespan" | cut -d '-' -f 2)"
        end="$(time_to_minutes "$end")"
        cat << FIN >> "$monologue_selector"
if [ \$now -ge $start -a \$now -le $end ]
then
  [ "\$DEBUG" != '' ] && echo "$timespan: choosing message from \"$messages_file\"" 1>&2
  message="\$(extract_message "$messages_file" | echo_with_probability 60)"
  if [ "\$message" != '' ]
  then
    echo "\$message"
    exit \$?
  fi
fi

FIN
     done
    fi
  done

  cat << FIN >> "$monologue_selector"
[ "\$DEBUG" != '' ] && echo "Allday case: choosing message from \"$status_dir/monologue_all.txt\"" 1>&2
extract_message "$status_dir/monologue_all.txt"
exit \$?

FIN

fi

cat << FIN >> "$monologue_selector"
exit 1
FIN

chmod +x "$monologue_selector"
