#!/bin/sh

set -eu

KNOWN_URLS_DIR=urls
GH_URLS_FILE=tmp/gh_urls.txt
NEW_URLS_FILE=tmp/new_urls.txt

# https://github.com/teeworlds-community/mirror-bot/issues/5
# https://github.com/cli/cli/blob/f4dff56057efabcfa38c25b3d5220065719d2b15/pkg/cmd/root/help_topic.go#L92-L96
# use local github cli config
# so this script never opens pullrequests under the wrong github user
# if the linux user wide configuration changes
export GH_CONFIG_DIR=./gh

err() {
	printf '[-][%s] %s\n' "$(date '+%F %H:%M')" "$1"
}
log() {
	printf '[*][%s] %s\n' "$(date '+%F %H:%M')" "$1"
}

# everything not in here should be passed to check_dep
# https://pubs.opengroup.org/onlinepubs/9699919799/utilities/contents.html
# https://pubs.opengroup.org/onlinepubs/009695399/idx/utilities.html
check_dep() {
	[ -x "$(command -v "$1")" ] && return
	err "Error: missing dependency $1"
	exit 1
}

check_dep gh
check_dep jq

mkdir -p tmp

:>"$GH_URLS_FILE"
:>"$NEW_URLS_FILE"
mkdir -p "$KNOWN_URLS_DIR"
[ ! -f "$KNOWN_URLS_DIR/mod.txt" ] && :>"$KNOWN_URLS_DIR/mod.txt"
[ ! -f "$KNOWN_URLS_DIR/antibot.txt" ] && :>"$KNOWN_URLS_DIR/antibot.txt"
[ ! -f "$KNOWN_URLS_DIR/config.txt" ] && :>"$KNOWN_URLS_DIR/config.txt"

assert() {
	got="$1"
	shift
	if [ "$1" != in ]
	then
		err "invalid assert operator $1"
		exit 1
	fi
	shift
	all="$*"
	while [ "$#" -gt 0 ]
	do
		[ "$1" = "$got" ] && return
		shift
	done
	err "expected '$got' to be in: $all"
	exit 1
}

get_urls_by_label() {
	issue_or_pr="$1" # pr
	assert "$issue_or_pr" in pr issue
	ddnet_label="$2" # Mod-relevant change
	assert "$ddnet_label" in "Mod-relevant change" "Antibot ABI change" "Config-breaking change"
	issue_or_pr_upcased="$(printf '%s\n' "$issue_or_pr" | tr '[:lower:]' '[:upper:]')"
	full_label="$issue_or_pr_upcased: $ddnet_label"
	gh "$issue_or_pr" list \
		--repo ddnet/ddnet \
		--label "$full_label" \
		--state all \
		--json url |
		jq '.[] | .url' -r
}
get_mod_prs() {
       get_urls_by_label pr "Mod-relevant change"
}
get_mod_issues() {
       get_urls_by_label issue "Mod-relevant change"
}
get_antibot_prs() {
       get_urls_by_label pr "Antibot ABI change"
}
get_antibot_issues() {
       get_urls_by_label issue "Antibot ABI change"
}
get_config_prs() {
       get_urls_by_label pr "Config-breaking change"
}
gh_comment_id() {
	id="$1"
	text="$2"
	gh issue comment "$id" --body "$text"
}
gh_comment_mod_prs() {
	gh_comment_id 1 "$1"
}
gh_comment_mod_issues() {
	gh_comment_id 2 "$1"
}
gh_comment_antibot_prs() {
	gh_comment_id 4 "$1"
}
gh_comment_config_prs() {
	gh_comment_id 5 "$1"
}

sort_file() {
	file_path="$1"
	if [ -f "$file_path".tmp ]
	then
		err "Error: failed to sort $file_path"
		err "       not overwriting $file_path.tmp"
		err "       you may want to remove that file manually"
		exit 1
	fi
	sort "$file_path" > "$file_path".tmp
	mv "$file_path".tmp "$file_path"
}

new_mod_url() {
	url="$1"
	log "new mod url=$url"
	printf '%s\n' "$url" >> "$KNOWN_URLS_DIR/mod.txt"
	if printf '%s\n' "$url" | grep 'issues'
	then
		gh_comment_mod_issues "$url"
	else
		gh_comment_mod_prs "$url"
	fi
}

new_antibot_url() {
	url="$1"
	log "new antibot url=$url"
	printf '%s\n' "$url" >> "$KNOWN_URLS_DIR/antibot.txt"
	if printf '%s\n' "$url" | grep 'issues'
	then
		err "antibot issue not supported $url"
	else
		gh_comment_antibot_prs "$url"
	fi
}

new_config_url() {
	url="$1"
	log "new config url=$url"
	printf '%s\n' "$url" >> "$KNOWN_URLS_DIR/config.txt"
	if printf '%s\n' "$url" | grep 'issues'
	then
		err "config issue not supported $url"
	else
		gh_comment_config_prs "$url"
	fi
}

check_for_new() {
	label="$1" # mod
	assert "$label" in mod antibot config

	get_${label}_prs > "$GH_URLS_FILE"
	get_${label}_issues >> "$GH_URLS_FILE"
	sort_file "$GH_URLS_FILE"
	sort_file "$KNOWN_URLS_DIR/$label.txt"
	comm -23 "$GH_URLS_FILE" "$KNOWN_URLS_DIR/$label.txt" > "$NEW_URLS_FILE"

	got_new=0
	while read -r new
	do
		new_${label}_url "$new"
		got_new=1
	done < "$NEW_URLS_FILE"
	if [ "$got_new" = "1" ]
	then
		git add "$KNOWN_URLS_DIR/$label.txt" && git commit -m "New url" && git push
	fi
}

while :
do
	check_for_new mod
	check_for_new antibot
	check_for_new config
	log "sleeping for 5 minutes ..."
	sleep 5m
done

