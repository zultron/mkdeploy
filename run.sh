#!/bin/bash -e

TOPDIR=$(readlink -f $(dirname "$0")/..)
DEPLOYDIR=${TOPDIR}/mkdeploy
cd "$TOPDIR"

REPODIR=~/aptrepo
GPGDIR=~/aptrepo-keys
IMAGE=mkdeploy
CONTAINER=mkdeploy
CMD=$1; shift || true

build() {
    docker build -t ${IMAGE} ${DEPLOYDIR}/docker
}

run() {
    set -x
    if docker ps -a | grep -q ' deploy *$'; then
	docker start ${CONTAINER}
    else
	docker run \
	    -d \
	    -v ${TOPDIR}:/opt/mkdocker:ro \
	    -v ${TOPDIR}/log:/opt/mkdocker/log \
	    -v ${REPODIR}:/opt/aptrepo \
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
	    -v ${TOPDIR}:/opt/mkdocker:ro \
	    -v ${REPODIR}:/opt/aptrepo \
	    -v ${GPGDIR}:/opt/aptrepo-keys \
	    ${IMAGE} /opt/mkdocker/mkdeploy/run.sh init
    else
	# Run inside container

	# Fix directory ownership
	chown aptrepo:aptrepo /opt/aptrepo

	# Create log directory for supervisord, rsyslogd, apache2
	mkdir -p /opt/aptrepo/log
	chown aptrepo:aptrepo /opt/aptrepo/log

	# Set up SSH keys
	if ! test -d /opt/aptrepo/.ssh; then
	    install -d -o aptrepo -g aptrepo -m 700 /opt/aptrepo/.ssh
	    ssh-keygen -N '' -C 'mkdeploy' -f /opt/aptrepo/.ssh/id_rsa
	    cp /opt/aptrepo/.ssh/id_rsa.pub /opt/aptrepo/.ssh/authorized_keys
	    chown -R aptrepo:aptrepo /opt/aptrepo/.ssh
	fi

	# Set up GNUPGHOME
	chmod 700 /opt/aptrepo-keys
	if ! test -f /opt/aptrepo-keys/secring.gpg; then
	    env GNUPGHOME=/opt/aptrepo-keys gpg --gen-key
	fi
	chown -R aptrepo:aptrepo /opt/aptrepo-keys

	# Set up repo directory
	if ! test -d /opt/aptrepo/repo; then
	    install -d -o aptrepo -g aptrepo -m 755 /opt/aptrepo/repo
	fi
	su aptrepo -c "${DEPLOYDIR}/get-ppa.sh -c all -i"
    fi
}

repo() {
    if test "${MKDOCKER_CONTAINER}" != 1; then
	# Outiside container; re-run inside
	docker run --rm \
	    -v ${TOPDIR}:/opt/mkdocker:ro \
	    -v ${REPODIR}:/opt/aptrepo \
	    -v ${GPGDIR}:/opt/aptrepo-keys \
	    -u aptrepo:aptrepo \
	    ${IMAGE} /opt/mkdocker/mkdeploy/run.sh repo "$@"
    else
	# Inside container
	${DEPLOYDIR}/get-ppa.sh "$@"
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
