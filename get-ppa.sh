#!/bin/bash -e

# Repo configuration
CODENAMES="wheezy jessie"
WHEEZY_MANUAL_UPDATES="da-mkdeps-wheezy"
JESSIE_MANUAL_UPDATES="da-mkdeps-jessie jessie-linux-rt"

####################################################
# Utility functions

# Print debug messages
debugmsg() {
    test -n "$DEBUG" || return 0
    echo "DEBUG:  $*" >&2
}

# Print info messages
msg() {
    ! ${QUIET} || return 0
    echo -e "$@" >&2
}

usage() {
    set +x
    test -z "$1" || msg "$1"
    msg "Usage:"
    msg "    $0 [ -c CODENAME ] [ -d ] [ -m ] \\"
    msg "	[ -u | -U | -l | -i | -r REPREPO ARGS... ]"
    msg "    $0 -k"
    msg "	-c  CODENAME (wheezy, jessie, etc.)"
    msg "	-d  enable debug output"
    msg "	-m  run manual updates"
    msg "	-u  check for updates"
    msg "	-U  pull updates"
    msg "	-l  list packages"
    msg "	-i  init configs"
    msg "	-r  run reprepro with following args; must be last argument"
    msg "	-k  dump gpg package signing public key"
    exit 1
}

####################################################
# Variable initialization

# Verbose arg given to reprepro
# This may be reduced by one '-v'
REPREPRO_VERBOSE=-vv

# Don't run manual updates by default
RUN_MANUAL_UPDATES=false

# Quiet mode for cronjobs
QUIET=false

# Some commands don't need reprepro config initialized
INIT=true

# Where these scripts live
SCRIPTSDIR=$(readlink -f $(dirname $0))
# Where the templates live
TEMPLATEDIR=${SCRIPTSDIR}/reprepro-templates

# Where the data lives
BASEDIR=/opt/aptrepo
REPODIR=${BASEDIR}/repo
CONFIGDIR=$REPODIR/conf

# gpg keys
GNUPGHOME=/opt/aptrepo-keys

# GPG handling
if test -n "$GNUPGHOME"; then
    export GNUPGHOME
    GPG_ARG="--gnupghome $GNUPGHOME"
fi

# Force debug logging
#DEBUG=1

####################################################
# Read command line opts

# Process command line args
ORIG_ARGS="$@"
while getopts c:luUirdkmq ARG; do
    case $ARG in
        c) CODENAME="$OPTARG" ;;
	u) COMMAND=checkupdates ;;
	U) COMMAND=update ;;
	l) COMMAND=list-archive ;;
	i) COMMAND=render_archive_config ;;
	r) COMMAND=run-reprepro; break ;;
	d) DEBUG=1; REPREPRO_VERBOSE=-VV ;;
	m) RUN_MANUAL_UPDATES=true ;;
	q) QUIET=true; REPREPRO_VERBOSE=-s ;;
	k) COMMAND=print_gpg_key ;;
	*) usage
    esac
done
shift $((OPTIND-1))

####################################################
# Utility functions

run-reprepro() {
    # reprepro command
    REPREPRO="reprepro $REPREPRO_VERBOSE $GPG_ARG -b $REPODIR \
	--confdir +b/conf --dbdir +b/db"
    debugmsg running:  ${REPREPRO} $*
    ${REPREPRO} "$@"
}

init() {
    # Create any missing directories
    if ! test -f $CONFIGDIR; then
	debugmsg "Creating configuration directory $CONFIGDIR"
	mkdir -p $CONFIGDIR
    fi
}

check-codename() {
    # check -c option is valid
    test -n "$CODENAME" || usage "No codename specified"
    test "$CODENAMES" != "${CODENAMES/${CODENAME}}" || \
	usage "Valid codenames are:  ${CODENAMES}"
    debugmsg "Validated codename:  ${CODENAME}"
}

gpg-fingerprint() {
    gpg --list-secret-keys --fingerprint | awk '/fingerprint/ { print $12 $13 }'
}

print_gpg_key() {
    gpg --export --armor $(gpg-fingerprint)
}

lock() {
    # Lock
    LOCKDIR=${REPODIR}/get-ppa.lock
    if ! mkdir $LOCKDIR 2>/dev/null; then
	echo "$0 exiting:  lock directory exists: '${LOCKDIR}'" >&2
	exit 1
    fi
    trap "rmdir $LOCKDIR; exit" INT TERM EXIT
}

####################################################
# render templates

# set up distributions and updates files
render_archive_config() {
    local CONFIG
    for CONFIG in distributions updates; do
	local DST_CONFIG=$CONFIGDIR/$CONFIG
	local SRC_CONFIG=tmpl.$CONFIG
	debugmsg "Rendering config file:  ${DST_CONFIG}"
	debugmsg "    from source template:  ${SRC_CONFIG}"

	if ! ${RUN_MANUAL_UPDATES}; then
	    JESSIE_MANUAL_UPDATES=''
	    WHEEZY_MANUAL_UPDATES=''
	fi

	# render SRC_CONFIG into DST_CONFIG
	sed $TEMPLATEDIR/$SRC_CONFIG \
	    -e "s,@WHEEZY_MANUAL_UPDATES@,${WHEEZY_MANUAL_UPDATES},g" \
	    -e "s,@JESSIE_MANUAL_UPDATES@,${JESSIE_MANUAL_UPDATES},g" \
	    -e "s,@PACKAGE_SIGNING_KEY@,$(gpg-fingerprint),g" \
	    > $DST_CONFIG
    done
}

####################################################
# reprepro functions

# List Debian archive
list-archive() {
    for c in ${CODENAME:-${CODENAMES}}; do
	run-reprepro -C main list $c
    done
}

# Testing:  see what updates would be pulled
checkupdates() {
    render_archive_config
    run-reprepro --noskipold checkupdate $CODENAME
}

# Pull updates
update() {
    render_archive_config
    echo "Updating archive at $(date -R)" 1>&2
    run-reprepro --noskipold update $CODENAME
}

####################################################
# Main program

if test -n "$COMMAND"; then
    if ${INIT}; then
	lock
	init
    fi    
    $COMMAND "$@"
else
    usage
fi
