#!/bin/sh
#
# Copyright (c) 2005 Linus Torvalds
# Copyright (c) 2006 Junio C Hamano

USAGE='[-a] [-s] [-v] [--no-verify] [-m <message> | -F <logfile> | (-C|-c) <commit>] [-u] [--amend] [-e] [--author <author>] [[-i | -o] <path>...]'
SUBDIRECTORY_OK=Yes
. git-sh-setup

git-rev-parse --verify HEAD >/dev/null 2>&1 || initial_commit=t
branch=$(GIT_DIR="$GIT_DIR" git-symbolic-ref HEAD)

case "$0" in
*status)
	status_only=t
	unmerged_ok_if_status=--unmerged ;;
*commit)
	status_only=
	unmerged_ok_if_status= ;;
esac

refuse_partial () {
	echo >&2 "$1"
	echo >&2 "You might have meant to say 'git commit -i paths...', perhaps?"
	exit 1
}

THIS_INDEX="$GIT_DIR/index"
NEXT_INDEX="$GIT_DIR/next-index$$"
rm -f "$NEXT_INDEX"
save_index () {
	cp "$THIS_INDEX" "$NEXT_INDEX"
}

report () {
  header="#
# $1:
#   ($2)
#
"
  trailer=""
  while read status name newname
  do
    printf '%s' "$header"
    header=""
    trailer="#
"
    case "$status" in
    M ) echo "#	modified: $name";;
    D*) echo "#	deleted:  $name";;
    T ) echo "#	typechange: $name";;
    C*) echo "#	copied: $name -> $newname";;
    R*) echo "#	renamed: $name -> $newname";;
    A*) echo "#	new file: $name";;
    U ) echo "#	unmerged: $name";;
    esac
  done
  printf '%s' "$trailer"
  [ "$header" ]
}

run_status () {
    (
	# We always show status for the whole tree.
	cd "$TOP"

	IS_INITIAL="$initial_commit"
	REFERENCE=HEAD
	case "$amend" in
	t)
		# If we are amending the initial commit, there
		# is no HEAD^1.
		if git-rev-parse --verify "HEAD^1" >/dev/null 2>&1
		then
			REFERENCE="HEAD^1"
			IS_INITIAL=
		else
			IS_INITIAL=t
		fi
		;;
	esac

	# If TMP_INDEX is defined, that means we are doing
	# "--only" partial commit, and that index file is used
	# to build the tree for the commit.  Otherwise, if
	# NEXT_INDEX exists, that is the index file used to
	# make the commit.  Otherwise we are using as-is commit
	# so the regular index file is what we use to compare.
	if test '' != "$TMP_INDEX"
	then
	    GIT_INDEX_FILE="$TMP_INDEX"
	    export GIT_INDEX_FILE
	elif test -f "$NEXT_INDEX"
	then
	    GIT_INDEX_FILE="$NEXT_INDEX"
	    export GIT_INDEX_FILE
	fi

	case "$branch" in
	refs/heads/master) ;;
	*)  echo "# On branch $branch" ;;
	esac

	if test -z "$IS_INITIAL"
	then
	    git-diff-index -M --cached --name-status \
		--diff-filter=MDTCRA $REFERENCE |
	    sed -e '
		    s/\\/\\\\/g
		    s/ /\\ /g
	    ' |
	    report "Updated but not checked in" "will commit"
	    committable="$?"
	else
	    echo '#
# Initial commit
#'
	    git-ls-files |
	    sed -e '
		    s/\\/\\\\/g
		    s/ /\\ /g
		    s/^/A /
	    ' |
	    report "Updated but not checked in" "will commit"

	    committable="$?"
	fi

	git-diff-files  --name-status |
	sed -e '
		s/\\/\\\\/g
		s/ /\\ /g
	' |
	report "Changed but not updated" \
	    "use git-update-index to mark for commit"

        option=""
        if test -z "$untracked_files"; then
            option="--directory --no-empty-directory"
        fi
	if test -f "$GIT_DIR/info/exclude"
	then
	    git-ls-files -z --others $option \
		--exclude-from="$GIT_DIR/info/exclude" \
		--exclude-per-directory=.gitignore
	else
	    git-ls-files -z --others $option \
		--exclude-per-directory=.gitignore
	fi |
	perl -e '$/ = "\0";
	    my $shown = 0;
	    while (<>) {
		chomp;
		s|\\|\\\\|g;
		s|\t|\\t|g;
		s|\n|\\n|g;
		s/^/#	/;
		if (!$shown) {
		    print "#\n# Untracked files:\n";
		    print "#   (use \"git add\" to add to commit)\n";
		    print "#\n";
		    $shown = 1;
		}
		print "$_\n";
	    }
	'

	if test -n "$verbose" -a -z "$IS_INITIAL"
	then
	    git-diff-index --cached -M -p --diff-filter=MDTCRA $REFERENCE
	fi
	case "$committable" in
	0)
		case "$amend" in
		t)
			echo "# No changes" ;;
		*)
			echo "nothing to commit" ;;
		esac
		exit 1 ;;
	esac
	exit 0
    )
}

trap '
	test -z "$TMP_INDEX" || {
		test -f "$TMP_INDEX" && rm -f "$TMP_INDEX"
	}
	rm -f "$NEXT_INDEX"
' 0

################################################################
# Command line argument parsing and sanity checking

all=
also=
only=
logfile=
use_commit=
amend=
edit_flag=
no_edit=
log_given=
log_message=
verify=t
verbose=
signoff=
force_author=
only_include_assumed=
untracked_files=
while case "$#" in 0) break;; esac
do
  case "$1" in
  -F|--F|-f|--f|--fi|--fil|--file)
      case "$#" in 1) usage ;; esac
      shift
      no_edit=t
      log_given=t$log_given
      logfile="$1"
      shift
      ;;
  -F*|-f*)
      no_edit=t
      log_given=t$log_given
      logfile=`expr "z$1" : 'z-[Ff]\(.*\)'`
      shift
      ;;
  --F=*|--f=*|--fi=*|--fil=*|--file=*)
      no_edit=t
      log_given=t$log_given
      logfile=`expr "z$1" : 'z-[^=]*=\(.*\)'`
      shift
      ;;
  -a|--a|--al|--all)
      all=t
      shift
      ;;
  --au=*|--aut=*|--auth=*|--autho=*|--author=*)
      force_author=`expr "z$1" : 'z-[^=]*=\(.*\)'`
      shift
      ;;
  --au|--aut|--auth|--autho|--author)
      case "$#" in 1) usage ;; esac
      shift
      force_author="$1"
      shift
      ;;
  -e|--e|--ed|--edi|--edit)
      edit_flag=t
      shift
      ;;
  -i|--i|--in|--inc|--incl|--inclu|--includ|--include)
      also=t
      shift
      ;;
  -o|--o|--on|--onl|--only)
      only=t
      shift
      ;;
  -m|--m|--me|--mes|--mess|--messa|--messag|--message)
      case "$#" in 1) usage ;; esac
      shift
      log_given=m$log_given
      if test "$log_message" = ''
      then
          log_message="$1"
      else
          log_message="$log_message

$1"
      fi
      no_edit=t
      shift
      ;;
  -m*)
      log_given=m$log_given
      if test "$log_message" = ''
      then
          log_message=`expr "z$1" : 'z-m\(.*\)'`
      else
          log_message="$log_message

`expr "z$1" : 'z-m\(.*\)'`"
      fi
      no_edit=t
      shift
      ;;
  --m=*|--me=*|--mes=*|--mess=*|--messa=*|--messag=*|--message=*)
      log_given=m$log_given
      if test "$log_message" = ''
      then
          log_message=`expr "z$1" : 'z-[^=]*=\(.*\)'`
      else
          log_message="$log_message

`expr "z$1" : 'zq-[^=]*=\(.*\)'`"
      fi
      no_edit=t
      shift
      ;;
  -n|--n|--no|--no-|--no-v|--no-ve|--no-ver|--no-veri|--no-verif|--no-verify)
      verify=
      shift
      ;;
  --a|--am|--ame|--amen|--amend)
      amend=t
      log_given=t$log_given
      use_commit=HEAD
      shift
      ;;
  -c)
      case "$#" in 1) usage ;; esac
      shift
      log_given=t$log_given
      use_commit="$1"
      no_edit=
      shift
      ;;
  --ree=*|--reed=*|--reedi=*|--reedit=*|--reedit-=*|--reedit-m=*|\
  --reedit-me=*|--reedit-mes=*|--reedit-mess=*|--reedit-messa=*|\
  --reedit-messag=*|--reedit-message=*)
      log_given=t$log_given
      use_commit=`expr "z$1" : 'z-[^=]*=\(.*\)'`
      no_edit=
      shift
      ;;
  --ree|--reed|--reedi|--reedit|--reedit-|--reedit-m|--reedit-me|\
  --reedit-mes|--reedit-mess|--reedit-messa|--reedit-messag|--reedit-message)
      case "$#" in 1) usage ;; esac
      shift
      log_given=t$log_given
      use_commit="$1"
      no_edit=
      shift
      ;;
  -C)
      case "$#" in 1) usage ;; esac
      shift
      log_given=t$log_given
      use_commit="$1"
      no_edit=t
      shift
      ;;
  --reu=*|--reus=*|--reuse=*|--reuse-=*|--reuse-m=*|--reuse-me=*|\
  --reuse-mes=*|--reuse-mess=*|--reuse-messa=*|--reuse-messag=*|\
  --reuse-message=*)
      log_given=t$log_given
      use_commit=`expr "z$1" : 'z-[^=]*=\(.*\)'`
      no_edit=t
      shift
      ;;
  --reu|--reus|--reuse|--reuse-|--reuse-m|--reuse-me|--reuse-mes|\
  --reuse-mess|--reuse-messa|--reuse-messag|--reuse-message)
      case "$#" in 1) usage ;; esac
      shift
      log_given=t$log_given
      use_commit="$1"
      no_edit=t
      shift
      ;;
  -s|--s|--si|--sig|--sign|--signo|--signof|--signoff)
      signoff=t
      shift
      ;;
  -v|--v|--ve|--ver|--verb|--verbo|--verbos|--verbose)
      verbose=t
      shift
      ;;
  -u|--u|--un|--unt|--untr|--untra|--untrac|--untrack|--untracke|--untracked|\
  --untracked-|--untracked-f|--untracked-fi|--untracked-fil|--untracked-file|\
  --untracked-files)
      untracked_files=t
      shift
      ;;
  --)
      shift
      break
      ;;
  -*)
      usage
      ;;
  *)
      break
      ;;
  esac
done
case "$edit_flag" in t) no_edit= ;; esac

################################################################
# Sanity check options

case "$amend,$initial_commit" in
t,t)
  die "You do not have anything to amend." ;;
t,)
  if [ -f "$GIT_DIR/MERGE_HEAD" ]; then
    die "You are in the middle of a merge -- cannot amend."
  fi ;;
esac

case "$log_given" in
tt*)
  die "Only one of -c/-C/-F can be used." ;;
*tm*|*mt*)
  die "Option -m cannot be combined with -c/-C/-F." ;;
esac

case "$#,$also,$only,$amend" in
*,t,t,*)
  die "Only one of --include/--only can be used." ;;
0,t,,* | 0,,t,)
  die "No paths with --include/--only does not make sense." ;;
0,,t,t)
  only_include_assumed="# Clever... amending the last one with dirty index." ;;
0,,,*)
  ;;
*,,,*)
  only_include_assumed="# Explicit paths specified without -i nor -o; assuming --only paths..."
  also=
  ;;
esac
unset only
case "$all,$also,$#" in
t,t,*)
	die "Cannot use -a and -i at the same time." ;;
t,,[1-9]*)
	die "Paths with -a does not make sense." ;;
,t,0)
	die "No paths with -i does not make sense." ;;
esac

################################################################
# Prepare index to have a tree to be committed

TOP=`git-rev-parse --show-cdup`
if test -z "$TOP"
then
	TOP=./
fi

case "$all,$also" in
t,)
	save_index &&
	(
		cd "$TOP"
		GIT_INDEX_FILE="$NEXT_INDEX"
		export GIT_INDEX_FILE
		git-diff-files --name-only -z |
		git-update-index --remove -z --stdin
	)
	;;
,t)
	save_index &&
	git-ls-files --error-unmatch -- "$@" >/dev/null || exit

	git-diff-files --name-only -z -- "$@"  |
	(
		cd "$TOP"
		GIT_INDEX_FILE="$NEXT_INDEX"
		export GIT_INDEX_FILE
		git-update-index --remove -z --stdin
	)
	;;
,)
	case "$#" in
	0)
	    ;; # commit as-is
	*)
	    if test -f "$GIT_DIR/MERGE_HEAD"
	    then
		refuse_partial "Cannot do a partial commit during a merge."
	    fi
	    TMP_INDEX="$GIT_DIR/tmp-index$$"
	    if test -z "$initial_commit"
	    then
		# make sure index is clean at the specified paths, or
		# they are additions.
		dirty_in_index=`git-diff-index --cached --name-status \
			--diff-filter=DMTU HEAD -- "$@"`
		test -z "$dirty_in_index" ||
		refuse_partial "Different in index and the last commit:
$dirty_in_index"
	    fi
	    commit_only=`git-ls-files --error-unmatch -- "$@"` || exit

	    # Build the temporary index and update the real index
	    # the same way.
	    if test -z "$initial_commit"
	    then
		cp "$THIS_INDEX" "$TMP_INDEX"
		GIT_INDEX_FILE="$TMP_INDEX" git-read-tree -m HEAD
	    else
		    rm -f "$TMP_INDEX"
	    fi || exit

	    echo "$commit_only" |
	    GIT_INDEX_FILE="$TMP_INDEX" \
	    git-update-index --add --remove --stdin &&

	    save_index &&
	    echo "$commit_only" |
	    (
		GIT_INDEX_FILE="$NEXT_INDEX"
		export GIT_INDEX_FILE
		git-update-index --remove --stdin
	    ) || exit
	    ;;
	esac
	;;
esac

################################################################
# If we do as-is commit, the index file will be THIS_INDEX,
# otherwise NEXT_INDEX after we make this commit.  We leave
# the index as is if we abort.

if test -f "$NEXT_INDEX"
then
	USE_INDEX="$NEXT_INDEX"
else
	USE_INDEX="$THIS_INDEX"
fi

GIT_INDEX_FILE="$USE_INDEX" \
    git-update-index -q $unmerged_ok_if_status --refresh || exit

################################################################
# If the request is status, just show it and exit.

case "$0" in
*status)
	run_status
	exit $?
esac

################################################################
# Grab commit message, write out tree and make commit.

if test t = "$verify" && test -x "$GIT_DIR"/hooks/pre-commit
then
	if test "$TMP_INDEX"
	then
		GIT_INDEX_FILE="$TMP_INDEX" "$GIT_DIR"/hooks/pre-commit
	else
		GIT_INDEX_FILE="$USE_INDEX" "$GIT_DIR"/hooks/pre-commit
	fi || exit
fi

if test "$log_message" != ''
then
	echo "$log_message"
elif test "$logfile" != ""
then
	if test "$logfile" = -
	then
		test -t 0 &&
		echo >&2 "(reading log message from standard input)"
		cat
	else
		cat <"$logfile"
	fi
elif test "$use_commit" != ""
then
	git-cat-file commit "$use_commit" | sed -e '1,/^$/d'
elif test -f "$GIT_DIR/MERGE_HEAD" && test -f "$GIT_DIR/MERGE_MSG"
then
	cat "$GIT_DIR/MERGE_MSG"
elif test -f "$GIT_DIR/SQUASH_MSG"
then
	cat "$GIT_DIR/SQUASH_MSG"
fi | git-stripspace >"$GIT_DIR"/COMMIT_EDITMSG

case "$signoff" in
t)
	{
		echo
		git-var GIT_COMMITTER_IDENT | sed -e '
			s/>.*/>/
			s/^/Signed-off-by: /
		'
	} >>"$GIT_DIR"/COMMIT_EDITMSG
	;;
esac

if test -f "$GIT_DIR/MERGE_HEAD" && test -z "$no_edit"; then
	echo "#"
	echo "# It looks like you may be committing a MERGE."
	echo "# If this is not correct, please remove the file"
	echo "#	$GIT_DIR/MERGE_HEAD"
	echo "# and try again"
	echo "#"
fi >>"$GIT_DIR"/COMMIT_EDITMSG

# Author
if test '' != "$force_author"
then
	GIT_AUTHOR_NAME=`expr "z$force_author" : 'z\(.*[^ ]\) *<.*'` &&
	GIT_AUTHOR_EMAIL=`expr "z$force_author" : '.*\(<.*\)'` &&
	test '' != "$GIT_AUTHOR_NAME" &&
	test '' != "$GIT_AUTHOR_EMAIL" ||
	die "malformatted --author parameter"
	export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL
elif test '' != "$use_commit"
then
	pick_author_script='
	/^author /{
		s/'\''/'\''\\'\'\''/g
		h
		s/^author \([^<]*\) <[^>]*> .*$/\1/
		s/'\''/'\''\'\'\''/g
		s/.*/GIT_AUTHOR_NAME='\''&'\''/p

		g
		s/^author [^<]* <\([^>]*\)> .*$/\1/
		s/'\''/'\''\'\'\''/g
		s/.*/GIT_AUTHOR_EMAIL='\''&'\''/p

		g
		s/^author [^<]* <[^>]*> \(.*\)$/\1/
		s/'\''/'\''\'\'\''/g
		s/.*/GIT_AUTHOR_DATE='\''&'\''/p

		q
	}
	'
	set_author_env=`git-cat-file commit "$use_commit" |
	LANG=C LC_ALL=C sed -ne "$pick_author_script"`
	eval "$set_author_env"
	export GIT_AUTHOR_NAME
	export GIT_AUTHOR_EMAIL
	export GIT_AUTHOR_DATE
fi

PARENTS="-p HEAD"
if test -z "$initial_commit"
then
	if [ -f "$GIT_DIR/MERGE_HEAD" ]; then
		PARENTS="-p HEAD "`sed -e 's/^/-p /' "$GIT_DIR/MERGE_HEAD"`
	elif test -n "$amend"; then
		PARENTS=$(git-cat-file commit HEAD |
			sed -n -e '/^$/q' -e 's/^parent /-p /p')
	fi
	current=$(git-rev-parse --verify HEAD)
else
	if [ -z "$(git-ls-files)" ]; then
		echo >&2 Nothing to commit
		exit 1
	fi
	PARENTS=""
	current=
fi

if test -z "$no_edit"
then
	{
		echo ""
		echo "# Please enter the commit message for your changes."
		echo "# (Comment lines starting with '#' will not be included)"
		test -z "$only_include_assumed" || echo "$only_include_assumed"
		run_status
	} >>"$GIT_DIR"/COMMIT_EDITMSG
else
	# we need to check if there is anything to commit
	run_status >/dev/null 
fi
if [ "$?" != "0" -a ! -f "$GIT_DIR/MERGE_HEAD" -a -z "$amend" ]
then
	rm -f "$GIT_DIR/COMMIT_EDITMSG" "$GIT_DIR/SQUASH_MSG"
	run_status
	exit 1
fi

case "$no_edit" in
'')
	case "${VISUAL:-$EDITOR},$TERM" in
	,dumb)
		echo >&2 "Terminal is dumb but no VISUAL nor EDITOR defined."
		echo >&2 "Please supply the commit log message using either"
		echo >&2 "-m or -F option.  A boilerplate log message has"
		echo >&2 "been prepared in $GIT_DIR/COMMIT_EDITMSG"
		exit 1
		;;
	esac
	git-var GIT_AUTHOR_IDENT > /dev/null  || die
	git-var GIT_COMMITTER_IDENT > /dev/null  || die
	${VISUAL:-${EDITOR:-vi}} "$GIT_DIR/COMMIT_EDITMSG"
	;;
esac

case "$verify" in
t)
	if test -x "$GIT_DIR"/hooks/commit-msg
	then
		"$GIT_DIR"/hooks/commit-msg "$GIT_DIR"/COMMIT_EDITMSG || exit
	fi
esac

if test -z "$no_edit"
then
    sed -e '
        /^diff --git a\/.*/{
	    s///
	    q
	}
	/^#/d
    ' "$GIT_DIR"/COMMIT_EDITMSG
else
    cat "$GIT_DIR"/COMMIT_EDITMSG
fi |
git-stripspace >"$GIT_DIR"/COMMIT_MSG

if cnt=`grep -v -i '^Signed-off-by' "$GIT_DIR"/COMMIT_MSG |
	git-stripspace |
	wc -l` &&
   test 0 -lt $cnt
then
	if test -z "$TMP_INDEX"
	then
		tree=$(GIT_INDEX_FILE="$USE_INDEX" git-write-tree)
	else
		tree=$(GIT_INDEX_FILE="$TMP_INDEX" git-write-tree) &&
		rm -f "$TMP_INDEX"
	fi &&
	commit=$(cat "$GIT_DIR"/COMMIT_MSG | git-commit-tree $tree $PARENTS) &&
	rlogm=$(sed -e 1q "$GIT_DIR"/COMMIT_MSG) &&
	git-update-ref -m "commit: $rlogm" HEAD $commit $current &&
	rm -f -- "$GIT_DIR/MERGE_HEAD" &&
	if test -f "$NEXT_INDEX"
	then
		mv "$NEXT_INDEX" "$THIS_INDEX"
	else
		: ;# happy
	fi
else
	echo >&2 "* no commit message?  aborting commit."
	false
fi
ret="$?"
rm -f "$GIT_DIR/COMMIT_MSG" "$GIT_DIR/COMMIT_EDITMSG" "$GIT_DIR/SQUASH_MSG"
if test -d "$GIT_DIR/rr-cache"
then
	git-rerere
fi

if test -x "$GIT_DIR"/hooks/post-commit && test "$ret" = 0
then
	"$GIT_DIR"/hooks/post-commit
fi
exit "$ret"
