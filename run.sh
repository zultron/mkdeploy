#!/bin/bash -e

SCRIPTSDIR=$(readlink -f $(dirname "$0"))
cd "$SCRIPTSDIR"

REPODIR=~/aptrepo/repo
LOGDIR=~/aptrepo/log
GPGDIR=~/aptrepo/keys
IMAGE=mkdeploy
CONTAINER=mkdeploy
CMD=$1; shift || true

build() {
    docker build -t ${IMAGE} ${SCRIPTSDIR}/docker
}

run() {
    set -x
    if docker ps -a | grep -q ' deploy *$'; then
	docker start ${CONTAINER}
    else
	docker run \
	    -d \
	    -v ${SCRIPTSDIR}:/opt/mkdeploy/scripts:ro \
	    -v ${REPODIR}:/opt/mkdeploy/repo \
	    -v ${LOGDIR}:/opt/mkdeploy/log \
	    -p 2222:22 \
	    -p 80:80 \
	    --name=${CONTAINER} \
	    --restart=always \
	    ${IMAGE}
    fi

}

shell() {
    set -x
    if test -z "$*"; then
	docker exec -it ${CONTAINER} bash -i
    else
	docker exec -it ${CONTAINER} "$@"
    fi
}

stop() {
    set -x
    docker stop ${CONTAINER}
}

restart() {
    set -x
    docker restart ${CONTAINER}
}

destroy() {
    set -x
    stop || true
    docker rm ${CONTAINER}
}

init() {
    set -x
    if test "${MKDOCKER_CONTAINER}" != 1; then
	# Run outside of container
	docker run -it --rm \
	    -v ${SCRIPTSDIR}:/opt/mkdeploy/scripts:ro \
	    -v ${REPODIR}:/opt/mkdeploy/repo \
	    -v ${GPGDIR}:/opt/mkdeploy/keys \
	    ${IMAGE} /opt/mkdeploy/scripts/run.sh init
    else
	# Run inside container

	# Fix repo directory ownership
	chown aptrepo:aptrepo /opt/mkdeploy/repo

	# Create log directory for supervisord, rsyslogd, apache2
	mkdir -p /opt/mkdeploy/log
	chown aptrepo:aptrepo /opt/mkdeploy/log

	# Set up SSH keys
	if ! test -d /opt/mkdeploy/.ssh; then
	    install -d -o aptrepo -g aptrepo -m 700 /opt/mkdeploy/.ssh
	    ssh-keygen -N '' -C 'mkdeploy' -f /opt/mkdeploy/.ssh/id_rsa
	    cp /opt/mkdeploy/.ssh/id_rsa.pub /opt/mkdeploy/.ssh/authorized_keys
	    chown -R aptrepo:aptrepo /opt/mkdeploy/.ssh
	fi

	# Set up GNUPGHOME
	chmod 700 /opt/mkdeploy/keys
	if ! test -f /opt/mkdeploy/keys/secring.gpg; then
	    env GNUPGHOME=/opt/mkdeploy/keys gpg --gen-key
	fi
	for k in /opt/mkdeploy/scripts/keys/*gpg.key; do
	    env GNUPGHOME=/opt/mkdeploy/keys gpg --import $k
	done
	chown -R aptrepo:aptrepo /opt/mkdeploy/keys

	# Set up repo directory
	if ! test -d /opt/mkdeploy/repo; then
	    install -d -o aptrepo -g aptrepo -m 755 /opt/mkdeploy/repo
	fi
	su aptrepo -c "${SCRIPTSDIR}/get-ppa.sh -c all -i"
    fi
}

repo() {
    if test "${MKDOCKER_CONTAINER}" != 1; then
	# Outiside container; re-run inside
	docker run --rm \
	    -v ${SCRIPTSDIR}:/opt/mkdeploy/scripts:ro \
	    -v ${REPODIR}:/opt/mkdeploy/repo \
	    -v ${GPGDIR}:/opt/mkdeploy/keys \
	    -u aptrepo:aptrepo \
	    ${IMAGE} /opt/mkdeploy/scripts/run.sh repo "$@"
    else
	# Inside container
	${SCRIPTSDIR}/get-ppa.sh "$@"
    fi
}

case "$CMD" in
    build) build ;;
    run) run ;;
    shell) shell "$@" ;;
    stop) stop ;;
    restart) restart ;;
    destroy) destroy ;;
    init) init ;;
    repo) repo "$@" ;;
    *) echo "Usage: $0 [ build | run | shell [cmd [arg ...]] |" \
	"stop | restart | destroy | init | repo [arg ...] ]" >&2; exit 1 ;;
esac
