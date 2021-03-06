#!/usr/bin/env bash
set -ex


source logging.sh
source common.sh
source sanitychecks.sh
source utils.sh
source ocp_install_env.sh

if [ -z "${METAL3_DEV_ENV}" ]; then
  export REPO_PATH=${WORKING_DIR}
  sync_repo_and_patch metal3-dev-env https://github.com/metal3-io/metal3-dev-env.git
  METAL3_DEV_ENV="${REPO_PATH}/metal3-dev-env/"
fi
pushd ${METAL3_DEV_ENV}
./centos_install_requirements.sh
ansible-galaxy install -r vm-setup/requirements.yml
ANSIBLE_FORCE_COLOR=true ansible-playbook \
  -e "working_dir=$WORKING_DIR" \
  -e "virthost=$HOSTNAME" \
  -e "go_version=1.13.8" \
  -i vm-setup/inventory.ini \
  -b -vvv vm-setup/install-package-playbook.yml
popd

# needed if we are using locally built images
# We stop any systemd service so we can run in a container, since
# there's no RPM/systemd version available for RHEL8
if sudo systemctl is-active docker-distribution.service; then
  sudo systemctl disable --now docker-distribution.service
fi

# Install oc client - unless we're in openshift CI
if [[ -z "$OPENSHIFT_CI" ]]; then
  oc_tools_dir="${WORKING_DIR}/oc/${OPENSHIFT_VERSION}"
  oc_tools_local_file=openshift-client-${OPENSHIFT_VERSION}.tar.gz
  oc_download_url="https://mirror.openshift.com/pub/openshift-v4/clients/oc/${OPENSHIFT_VERSION}/linux/oc.tar.gz"
  mkdir -p ${oc_tools_dir}
  pushd ${oc_tools_dir}
  if [ ! -f "${oc_tools_local_file}" ]; then
    curl -L -o ${oc_tools_local_file} ${oc_download_url}
    tar xvzf ${oc_tools_local_file}
  fi
  sudo cp oc /usr/local/bin/
  oc version --client -o json
  popd
fi

if [ ! -z "${INSTALL_OPERATOR_SDK:-}" ]; then
    # Install operator-sdk
    if ! which operator-sdk 2>&1 >/dev/null ; then
        sudo wget https://github.com/operator-framework/operator-sdk/releases/download/v0.9.0/operator-sdk-v0.9.0-x86_64-linux-gnu -O /usr/local/bin/operator-sdk
        sudo chmod 755 /usr/local/bin/operator-sdk
    fi
fi

# Install Go dependency management tool
# Using pre-compiled binaries instead of installing from source
eval "$(go env)"
if ! which dep 2>&1 >/dev/null ; then
    mkdir -p $GOPATH/bin
    curl https://raw.githubusercontent.com/golang/dep/master/install.sh | sh
fi

if [[ ! -z "${MIRROR_IMAGES}" || $(env | grep "_LOCAL_IMAGE=") ]]; then
    setup_local_registry
fi
