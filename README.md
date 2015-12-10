# Run Machinekit package deploy and distribution in Docker

The `run.sh` script wraps common Docker functions.  It create the repo
directory in `~/aptrepo`.

Build the container image:

    ./run.sh build

Initialize the `~/aptrepo` directory; must be done once before run:

	./run.sh init

Run the container; also configures the container to start at boot
time:

    ./run.sh run

Stop the container:

	./run.sh stop

Restart the container:

	./run.sh restart

Destroy the container:

	./run.sh destroy

Start an interactive shell in the running container:

	./run.sh shell

Run a command in the running container:

	./run.sh shell ps -efww

Connect through ssh:

    ssh aptrepo@localhost -p2222

# SSH `authorized_keys`

Add ssh pubkeys to `~/aptrepo/.ssh/authorized_keys`.

# APT repo initialization

The APT repo will be initialized in `~/aptrepo/repo`.

If GPG signing keys already exist, create the directory
`~/aptrepo/gnupg` and place the signing keys there.  Otherwise, new
keys will be generated at `./run.sh init`.  Do not create a passphrase
or signatures cannot run automatically.

Edit the files in `reprepro-templates`, and edit the top of
`get-ppa.sh`.  See the `reprepro(1)` man-page for details.  The
strings like `@WHEEZY_MANUAL_UPDATES@` will be replaced with the
corresponding shell variables when the manual update argument is
supplied, as in `./run.sh repo -m`.

Set up a cron job similar to that in `crontab` to run periodically and
pull updates.

# APT repo management

The repo is initialized when the container is initialized, and the
container will periodically run updates.  Mostly there should be no
maintenance.

Some utilities are available for dumping the package signing key,
listing packages, etc.  Run `./run.sh repo` for usage.  Example:

List packages in the `wheezy` distro:

    ./run.sh repo -c wheezy -l

List updates not yet pulled into the repo:

    ./run.sh repo -u

Pull all updates into repo, including "manual" updates:

    ./run.sh repo -m -U
