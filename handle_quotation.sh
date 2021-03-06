#!/usr/bin/env bash

work_dir="$(pwd)"
tools_dir="$(cd "$(dirname "$0")" && pwd)"
source "$tools_dir/common.sh"

logfile="$log_dir/handle_quotation.log"

lock_key=''

while unlock "$lock_key" && read -r tweet
do
  owner="$(echo "$tweet" | jq -r .user.screen_name)"
  id="$(echo "$tweet" | jq -r .id_str)"
  url="https://twitter.com/$owner/status/$id"

  lock_key="quotation.$id"
  try_lock_until_success "$lock_key"

  log '=============================================================='
  log "Quoted by $owner at $url"

  if [ "$owner" = "$MY_SCREEN_NAME" ]
  then
    log " => ignored, because this is my activity"
    continue
  fi

  if echo "$tweet" | expired_by_seconds $((30 * 60))
  then
    log " => ignored, because this is tweeted 30 minutes or more ago"
    continue
  fi

  if is_already_replied "$id"
  then
    log '  => already responded'
    continue
  fi

  body="$(echo "$tweet" | "$tweet_sh" body)"
  me="$(echo "$tweet" | jq -r .quoted_status.user.screen_name)"
  log " me: $me"
  log " body    : $body"

  is_reply=$(echo "$tweet" | is_reply && echo 1)
  log " is_reply: $is_reply"

  export SCREEN_NAME="$owner"
  responses="$(echo "$body" | "$responder")"

  if [ "$responses" = '' ]
  then
    # Don't follow, favorite, and reply to the tweet
    # if it is a "don't respond" case.
    log " no response"
    continue
  fi

  echo "$body" | cache_body "$id"

  if is_true "$FOLLOW_ON_QUOTED"
  then
    echo "$tweet" | follow_owner
  fi
  if is_true "$FAVORITE_QUOTATIONS"
  then
    echo "$tweet" | favorite
  fi

  is_protected=$(echo "$tweet" | is_protected_tweet && echo 1)

  # Don't RT protected user's tweet!
  if [ "$is_protected" != '1' ] && is_true "$RETWEET_QUOTATIONS"
  then
    echo "$tweet" | retweet
  fi

  if is_true "$RESPOND_TO_QUOTATIONS"
  then
    if echo "$body" | grep "^@$me" > /dev/null
    then
      log "Seems to be a reply."
      # regenerate responses with is_reply parameter
      responses="$(echo "$body" | env IS_REPLY=$is_reply "$responder")"
      log " response: $response"
      other_replied_people="$(echo "$body" | other_replied_people)"
      echo "$responses" |
        # make response body a mention
        sed "s/^/@$owner $other_replied_people/" |
        post_replies "$id" "@$owner $other_replied_people"
    elif echo "$body" | egrep "^[\._,:;]?@$me" > /dev/null
    then
      log "Seems to be a mention but for public."
      log " response: $response"
      other_replied_people="$(echo "$body" | other_replied_people)"
      echo "$responses" |
        # make response body a mention
        sed "s/^/.@$owner $other_replied_people/" |
        post_replies "$id" "@$owner $other_replied_people"
    elif [ "$is_protected" != '1' ] # Don't quote protected tweet!
    then
      log "Seems to be an RT with quotation."
      # Don't post default questions as quotation!
      responses="$(echo "$body" | env NO_QUESTION=1 "$responder")"
      if [ $? != 0 -o "$responses" = '' ]
      then
        log " => don't quote case"
      else
        echo "$responses" |
          post_quotation "$owner" "$id"
      fi
    fi
  fi
done
