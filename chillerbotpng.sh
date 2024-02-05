#!/bin/sh

KNOWN_URLS_FILE=urls.txt
GH_URLS_FILE=tmp/gh_urls.txt
NEW_URLS_FILE=tmp/new_urls.txt

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
[ ! -f "$KNOWN_URLS_FILE" ] && :>"$KNOWN_URLS_FILE"

get_mod_urls() {
	issue_or_pr="$1"
	issue_or_pr_upcased="$(printf '%s\n' "$issue_or_pr" | tr '[:lower:]' '[:upper:]')"
	label="$issue_or_pr_upcased: Mod-relevant change"
	gh "$issue_or_pr" list \
		--repo ddnet/ddnet \
		--label "$label" \
		--state all \
		--json url |
		jq '.[] | .url' -r
}
get_prs() {
	get_mod_urls pr
}
get_issues() {
	get_mod_urls issue
}
gh_comment_id() {
	id="$1"
	text="$2"
	gh issue comment "$id" --body "$text"
}
gh_comment_prs() {
	gh_comment_id 1 "$1"
}
gh_comment_issues() {
	gh_comment_id 2 "$1"
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

new_url() {
	url="$1"
	log "new url=$url"
	printf '%s\n' "$url" >> "$KNOWN_URLS_FILE"
	if printf '%s\n' "$url" | grep 'issues'
	then
		gh_comment_issues "$url"
	else
		gh_comment_prs "$url"
	fi
}

check_for_new() {
	get_prs > "$GH_URLS_FILE"
	get_issues >> "$GH_URLS_FILE"
	sort_file "$GH_URLS_FILE"
	sort_file "$KNOWN_URLS_FILE"
	comm -23 "$GH_URLS_FILE" "$KNOWN_URLS_FILE" > "$NEW_URLS_FILE"

	got_new=0
	while read -r new
	do
		new_url "$new"
		got_new=1
	done < "$NEW_URLS_FILE"
	if [ "$got_new" = "1" ]
	then
		git add . && git commit -m "New url" && git push
	fi
}

while :
do
	check_for_new
	log "sleeping for 5 minutes ..."
	sleep 5m
done

