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

extract_message_from_group() {
  local group="\$1"
  (cd "$TWEET_BASE_DIR"; ls ./monologues/\$group* |
     while read path
     do
       read_messages "\$path"
     done | shuf -n 1)
}

echo_with_probability() {
  if [ \$((\$RANDOM % 100)) -lt \$1 ]
  then
    cat
  fi
}

time_to_minutes() {
  local hours minutes
  read hours minutes <<< "\$(cat | \$esed 's/^0?([0-9]+):0?([0-9]+)\$/\1 \2/')"
  echo \$(( \$hours * 60 + \$minutes ))
}

date_matcher='0*([0-9]+|\*).0*([0-9]+|\*).0*([0-9]+|\*)'

date_to_serial() {
  local month year day
  read year month day <<< "\$(cat | \$esed "s/^\$date_matcher\$/\1 \2 \3/")"

  local current_year current_month current_day
  read current_year current_month current_day <<< "\$(date +'%Y %m %d')"

  [ "\$year" = '*' ] && year=\$(echo "\$current_year" | \$esed 's/^0+//')
  [ "\$month" = '*' ] && month=\$(echo "\$current_month" | \$esed 's/^0+//')
  [ "\$day" = '*' ] && day=\$(echo "\$current_day" | \$esed 's/^0+//')

  echo \$(( (\$year * 10000) + (\$month * 100) + \$day ))
}

read_messages() {
  local path="\$1"

  while read directive
  do
    local date_span="\$(echo "\$directive" | \$esed 's/^#[^:]+:[^0-9*]*//')"
    if [ "\$date_span" != '' ]
    then
      local start="\$(echo "\$date_span" | \$esed "s/\$date_matcher-\$date_matcher/\1.\2.\3/" | date_to_serial)"
      local end="\$(echo "\$date_span" | \$esed "s/\$date_matcher-\$date_matcher/\4.\5.\6/" | date_to_serial)"
      local today="\$(echo "\$(date +%Y.%m.%d)" | date_to_serial)"
      [ \$start -gt \$today ] && return 0
      [ \$end -lt \$today ] && return 0
    fi
  done < <(egrep '^# *date:' "\$path")
  #NOTE: This must be done with a process substitution instead of
  #      simple pipeline, because we need to execute the loop in
  #      the same process, not a sub process.
  #      ("return" in a sub-process loop produced by "egrep | while read..."
  #       cannot return actually.)

  # convert CR+LF => LF for safety.
  nkf -Lu "\$path" |
    egrep -v '^#|^ *$'
}

now=\$1
[ "\$now" = '' ] && now="\$(date +%H:%M)"
now=\$(echo "\$now" | time_to_minutes)

FIN

cd "$TWEET_BASE_DIR"

if [ -d ./monologues ]
then
  cat << FIN >> "$monologue_selector"
[ "\$DEBUG" != '' ] && echo "Finding timely message..." 1>&2
message="\$(extract_message_from_group 'timely' | echo_with_probability $TIMELY_TOPIC_PROBABILITY)"
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
    if [ "$timespans" != "$group" ]
    then
      for timespan in $(echo "$timespans" | sed 's/,/ /g')
      do
        start="$(echo "$timespan" | cut -d '-' -f 1 | time_to_minutes)"
        end="$(echo "$timespan" | cut -d '-' -f 2 | time_to_minutes)"
        cat << FIN >> "$monologue_selector"
if [ \$now -ge $start -a \$now -le $end ]
then
  [ "\$DEBUG" != '' ] && echo "$timespan: choosing message from \"$group\"" 1>&2
  message="\$(extract_message_from_group '$group' | echo_with_probability 60)"
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
[ "\$DEBUG" != '' ] && echo "Allday case" 1>&2
extract_message_from_group 'all'
exit \$?

FIN

fi

cat << FIN >> "$monologue_selector"
exit 1
FIN

chmod +x "$monologue_selector"
