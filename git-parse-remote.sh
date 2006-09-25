#!/bin/sh

# git-ls-remote could be called from outside a git managed repository;
# this would fail in that case and would issue an error message.
GIT_DIR=$(git-rev-parse --git-dir 2>/dev/null) || :;

get_data_source () {
	case "$1" in
	*/*)
		# Not so fast.	This could be the partial URL shorthand...
		token=$(expr "z$1" : 'z\([^/]*\)/')
		remainder=$(expr "z$1" : 'z[^/]*/\(.*\)')
		if test "$(git-repo-config --get "remote.$token.url")"
		then
			echo config-partial
		elif test -f "$GIT_DIR/branches/$token"
		then
			echo branches-partial
		else
			echo ''
		fi
		;;
	*)
		if test "$(git-repo-config --get "remote.$1.url")"
		then
			echo config
		elif test -f "$GIT_DIR/remotes/$1"
		then
			echo remotes
		elif test -f "$GIT_DIR/branches/$1"
		then
			echo branches
		else
			echo ''
		fi ;;
	esac
}

get_remote_url () {
	data_source=$(get_data_source "$1")
	case "$data_source" in
	'')
		echo "$1" ;;
	config-partial)
		token=$(expr "z$1" : 'z\([^/]*\)/')
		remainder=$(expr "z$1" : 'z[^/]*/\(.*\)')
		url=$(git-repo-config --get "remote.$token.url")
		echo "$url/$remainder"
		;;
	config)
		git-repo-config --get "remote.$1.url"
		;;
	remotes)
		sed -ne '/^URL: */{
			s///p
			q
		}' "$GIT_DIR/remotes/$1" ;;
	branches)
		sed -e 's/#.*//' "$GIT_DIR/branches/$1" ;;
	branches-partial)
		token=$(expr "z$1" : 'z\([^/]*\)/')
		remainder=$(expr "z$1" : 'z[^/]*/\(.*\)')
		url=$(sed -e 's/#.*//' "$GIT_DIR/branches/$token")
		echo "$url/$remainder"
		;;
	*)
		die "internal error: get-remote-url $1" ;;
	esac
}

get_default_remote () {
	curr_branch=$(git-symbolic-ref HEAD | sed -e 's|^refs/heads/||')
	origin=$(git-repo-config --get "branch.$curr_branch.remote")
	echo ${origin:-origin}
}

get_remote_default_refs_for_push () {
	data_source=$(get_data_source "$1")
	case "$data_source" in
	'' | config-partial | branches | branches-partial)
		;; # no default push mapping, just send matching refs.
	config)
		git-repo-config --get-all "remote.$1.push" ;;
	remotes)
		sed -ne '/^Push: */{
			s///p
		}' "$GIT_DIR/remotes/$1" ;;
	*)
		die "internal error: get-remote-default-ref-for-push $1" ;;
	esac
}

# Subroutine to canonicalize remote:local notation.
canon_refs_list_for_fetch () {
	# If called from get_remote_default_refs_for_fetch
	# leave the branches in branch.${curr_branch}.merge alone,
	# or the first one otherwise; add prefix . to the rest
	# to prevent the secondary branches to be merged by default.
	merge_branches=
	if test "$1" = "-d"
	then
		shift ; remote="$1" ; shift
		if test "$remote" = "$(get_default_remote)"
		then
			curr_branch=$(git-symbolic-ref HEAD | \
			    sed -e 's|^refs/heads/||')
			merge_branches=$(git-repo-config \
			    --get-all "branch.${curr_branch}.merge")
		fi
	fi
	for ref
	do
		force=
		case "$ref" in
		+*)
			ref=$(expr "z$ref" : 'z+\(.*\)')
			force=+
			;;
		esac
		expr "z$ref" : 'z.*:' >/dev/null || ref="${ref}:"
		remote=$(expr "z$ref" : 'z\([^:]*\):')
		local=$(expr "z$ref" : 'z[^:]*:\(.*\)')
		dot_prefix=.
		if test -z "$merge_branches"
		then
			merge_branches=$remote
			dot_prefix=
		else
			for merge_branch in $merge_branches
			do
			    [ "$remote" = "$merge_branch" ] &&
			    dot_prefix= && break
			done
		fi
		case "$remote" in
		'') remote=HEAD ;;
		refs/heads/* | refs/tags/* | refs/remotes/*) ;;
		heads/* | tags/* | remotes/* ) remote="refs/$remote" ;;
		*) remote="refs/heads/$remote" ;;
		esac
		case "$local" in
		'') local= ;;
		refs/heads/* | refs/tags/* | refs/remotes/*) ;;
		heads/* | tags/* | remotes/* ) local="refs/$local" ;;
		*) local="refs/heads/$local" ;;
		esac

		if local_ref_name=$(expr "z$local" : 'zrefs/\(.*\)')
		then
		   git-check-ref-format "$local_ref_name" ||
		   die "* refusing to create funny ref '$local_ref_name' locally"
		fi
		echo "${dot_prefix}${force}${remote}:${local}"
	done
}

# Returns list of src: (no store), or src:dst (store)
get_remote_default_refs_for_fetch () {
	data_source=$(get_data_source "$1")
	case "$data_source" in
	'' | config-partial | branches-partial)
		echo "HEAD:" ;;
	config)
		canon_refs_list_for_fetch -d "$1" \
			$(git-repo-config --get-all "remote.$1.fetch") ;;
	branches)
		remote_branch=$(sed -ne '/#/s/.*#//p' "$GIT_DIR/branches/$1")
		case "$remote_branch" in '') remote_branch=master ;; esac
		echo "refs/heads/${remote_branch}:refs/heads/$1"
		;;
	remotes)
		canon_refs_list_for_fetch -d "$1" $(sed -ne '/^Pull: */{
						s///p
					}' "$GIT_DIR/remotes/$1")
		;;
	*)
		die "internal error: get-remote-default-ref-for-push $1" ;;
	esac
}

get_remote_refs_for_push () {
	case "$#" in
	0) die "internal error: get-remote-refs-for-push." ;;
	1) get_remote_default_refs_for_push "$@" ;;
	*) shift; echo "$@" ;;
	esac
}

get_remote_refs_for_fetch () {
	case "$#" in
	0)
	    die "internal error: get-remote-refs-for-fetch." ;;
	1)
	    get_remote_default_refs_for_fetch "$@" ;;
	*)
	    shift
	    tag_just_seen=
	    for ref
	    do
		if test "$tag_just_seen"
		then
		    echo "refs/tags/${ref}:refs/tags/${ref}"
		    tag_just_seen=
		    continue
		else
		    case "$ref" in
		    tag)
			tag_just_seen=yes
			continue
			;;
		    esac
		fi
		canon_refs_list_for_fetch "$ref"
	    done
	    ;;
	esac
}

resolve_alternates () {
	# original URL (xxx.git)
	top_=`expr "z$1" : 'z\([^:]*:/*[^/]*\)/'`
	while read path
	do
		case "$path" in
		\#* | '')
			continue ;;
		/*)
			echo "$top_$path/" ;;
		../*)
			# relative -- ugly but seems to work.
			echo "$1/objects/$path/" ;;
		*)
			# exit code may not be caught by the reader.
			echo "bad alternate: $path"
			exit 1 ;;
		esac
	done
}
