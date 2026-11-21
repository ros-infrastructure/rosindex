#!/bin/bash
SCRIPT_DIR=`dirname $( readlink -m $( type -p $0 ))`

# Ensure your SSH private key has been added to the ssh-agent as follows:
# ssh-add /home/$USER/.ssh/id_rsa

# Example Usage:
# ./run.sh make build

COMMAND=''
INTERACTIVE='-it'
if [ -z "$1" ]
then
  COMMAND="bash"
else
  COMMAND=$@
  INTERACTIVE=''
fi

DOCKER_ENV_ARGS=()
for var in GITHUB_TOKEN GITHUB_USER GITHUB_PASSWORD ROSDISTRO_RETRY_MAX; do
  if [ -n "${!var}" ]; then
    DOCKER_ENV_ARGS+=(-e "$var")
  fi
done

docker run \
  -w /home/`whoami`/rosindex \
  -v $SCRIPT_DIR/..:/home/`whoami`/rosindex:rw \
  "${DOCKER_ENV_ARGS[@]}" \
  --net=host $INTERACTIVE rosindex/rosindex $COMMAND
