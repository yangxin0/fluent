#!/bin/sh
# Each app keeps its own cache of the installed input sources (sandboxed apps
# one each, under DARWIN_USER_CACHE_DIR), which records where every input
# method lives. A cache that still lists Fluent somewhere other than where it
# is installed now (Fluent.app before the rename to Fluent-Input.app) can't
# find it: in that app Fluent can't be picked at all. This removes those
# caches; macOS rebuilds each one the next time its app starts.
# Usage: forget-stale-input-caches.sh "<installed Fluent-Input.app path>"
installed="$1"
cache="${CACHE_DIR:-$(getconf DARWIN_USER_CACHE_DIR)}"
[ -n "$installed" ] && [ -d "$cache" ] || exit 0

stale=0
for kbdx in "$cache"/com.apple.IntlDataCache.le.kbdx "$cache"/*/com.apple.IntlDataCache.le.kbdx; do
	[ -f "$kbdx" ] || continue
	if strings "$kbdx" | grep -E '/Input Methods/Fluent[-A-Za-z]*\.app$' | grep -qvxF "$installed"; then
		dir=$(dirname "$kbdx")
		rm -f "$dir/com.apple.IntlDataCache.le" "$kbdx"
		echo "Forgot a stale input-source cache: $(basename "$dir")"
		stale=$((stale + 1))
	fi
done
if [ "$stale" -gt 0 ]; then
	echo "Quit and reopen any app where Fluent can't be picked; it rebuilds its cache on launch."
fi
