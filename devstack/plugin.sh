#!/usr/bin/env/ bash
# Plugin file for Solum services
#-------------------------------

# Dependencies:
# ``functions`` file
# ``DEST``, ``DATA_DIR``, ``STACK_USER`` must be defined
# ``ADMIN_{TENANT_NAME|PASSWORD}`` must be defined

# ``stack.sh`` calls the entry points in this order:
#
# install_solum
# install_solumclient
# configure_solum
# start_solum
# stop_solum

# Save trace setting
XTRACE=$(set +o | grep xtrace)
set -o xtrace

# Defaults
# --------

# Support entry points installation of console scripts
if [[ -d $SOLUM_DIR/bin ]]; then
    SOLUM_BIN_DIR=$SOLUM_DIR/bin
else
    SOLUM_BIN_DIR=$(get_python_exec_prefix)
fi

# Functions
# ---------

# create_solum_service_and_endpoint() - Set up required solum service and endpoint
function create_solum_service_and_endpoint() {
    SOLUM_UPDATE_ROLE=$(openstack role create \
        solum_assembly_update \
        | grep " id " | get_field 2)

    # Give the role to the demo and admin users so they can use git push
    # in either of the projects created by devstack
    openstack role add $SOLUM_UPDATE_ROLE --project demo --user demo
    openstack role add $SOLUM_UPDATE_ROLE --project demo --user admin
    openstack role add $SOLUM_UPDATE_ROLE --project admin --user admin

    if [[ "$KEYSTONE_CATALOG_BACKEND" = 'sql' ]]; then
        SOLUM_SERVICE=$(openstack service create application_deployment \
            --name=solum \
            --description="Solum" \
            | grep " id " | get_field 2)
        openstack endpoint create --region RegionOne $SOLUM_SERVICE public "$SOLUM_SERVICE_PROTOCOL://$SOLUM_SERVICE_HOST:$SOLUM_SERVICE_PORT"
        openstack endpoint create --region RegionOne $SOLUM_SERVICE admin "$SOLUM_SERVICE_PROTOCOL://$SOLUM_SERVICE_HOST:$SOLUM_SERVICE_PORT"
        openstack endpoint create --region RegionOne $SOLUM_SERVICE internal "$SOLUM_SERVICE_PROTOCOL://$SOLUM_SERVICE_HOST:$SOLUM_SERVICE_PORT"

        SOLUM_BUILDER_SERVICE=$(openstack service create image_builder \
            --name=solum \
            --description="Solum Image Builder" \
            | grep " id " | get_field 2)

        openstack endpoint create --region RegionOne $SOLUM_BUILDER_SERVICE public "$SOLUM_SERVICE_PROTOCOL://$SOLUM_SERVICE_HOST:$SOLUM_BUILDER_SERVICE_PORT"
        openstack endpoint create --region RegionOne $SOLUM_BUILDER_SERVICE admin "$SOLUM_SERVICE_PROTOCOL://$SOLUM_SERVICE_HOST:$SOLUM_BUILDER_SERVICE_PORT"
        openstack endpoint create --region RegionOne $SOLUM_BUILDER_SERVICE internal "$SOLUM_SERVICE_PROTOCOL://$SOLUM_SERVICE_HOST:$SOLUM_BUILDER_SERVICE_PORT"

    fi
}

# configure_solum() - Set config files, create data dirs, etc
function configure_solum() {

    if [[ ! -d $SOLUM_CONF_DIR ]]; then
        sudo mkdir -p $SOLUM_CONF_DIR
    fi
    sudo chown $STACK_USER $SOLUM_CONF_DIR

    # To support private github repos, do not perform host key check for github.com
    # Need this change on solum-worker instances
    STACK_USER_SSH_DIR=/home/$STACK_USER/.ssh
    if [[ ! -d $STACK_USER_SSH_DIR ]]; then
        sudo mkdir -p $STACK_USER_SSH_DIR
    fi
    sudo chown $STACK_USER $STACK_USER_SSH_DIR
    echo -e "Host github.com\n\tStrictHostKeyChecking no\n" > $STACK_USER_SSH_DIR/config

    # Generate sample config and configure common parameters.
    mkdir -p /tmp/solum

    # TODO(devkulkarni): Commenting out config generation for now to get around following bug
    # https://bugs.launchpad.net/solum/+bug/1555788. Instead, including a sample config in the repo
    #pushd $SOLUM_DIR
    #    oslo-config-generator --config-file=${SOLUM_DIR}/etc/solum/config-generator.conf --output-file=/tmp/solum/solum.conf.sample
    #popd
    #cp /tmp/solum/solum.conf.sample $SOLUM_CONF_DIR/$SOLUM_CONF_FILE
    cp ${SOLUM_DIR}/devstack/solum.conf.sample $SOLUM_CONF_DIR/$SOLUM_CONF_FILE

    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE DEFAULT debug $SOLUM_DEBUG

    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE DEFAULT use_syslog $SYSLOG

    # make trace visible
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE DEFAULT logging_context_format_string "%(asctime)s.%(msecs)03d %(process)d %(levelname)s %(name)s [%(request_id)s] s%(message)s %(support_trace)s"

    # Setup keystone_authtoken section
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE keystone_authtoken auth_host $KEYSTONE_AUTH_HOST
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE keystone_authtoken auth_port $KEYSTONE_AUTH_PORT
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE keystone_authtoken auth_protocol $KEYSTONE_AUTH_PROTOCOL
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE keystone_authtoken cafile $KEYSTONE_SSL_CA
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE keystone_authtoken auth_uri $KEYSTONE_SERVICE_URI/v2.0
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE keystone_authtoken admin_tenant_name service
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE keystone_authtoken admin_user $SOLUM_USER
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE keystone_authtoken admin_password $ADMIN_PASSWORD
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE keystone_authtoken signing_dir $SOLUM_AUTH_CACHE_DIR

    # configure the database.
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE database connection `database_connection_url solum`

    # configure the api servers to listen on
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE api host $SOLUM_SERVICE_HOST
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE api port $SOLUM_SERVICE_PORT
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE builder host $SOLUM_SERVICE_HOST
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE builder port $SOLUM_BUILDER_SERVICE_PORT

    # configure assembly handler to create appropriate image format
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE api image_format $SOLUM_IMAGE_FORMAT

    # common rpc settings
    iniset_rpc_backend solum $SOLUM_CONF_DIR/$SOLUM_CONF_FILE DEFAULT

    # service rpc settings
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE conductor topic solum-conductor
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE deployer topic solum-deployer
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE deployer handler heat
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE worker topic solum-worker
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE worker handler shell
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE worker proj_dir $SOLUM_PROJ_DIR

    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE deployer max_attempts $SOLUM_MAX_ATTEMPTS
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE deployer wait_interval $SOLUM_WAIT_INTERVAL
    iniset $SOLUM_CONF_DIR/$SOLUM_CONF_FILE deployer growth_factor $SOLUM_GROWTH_FACTOR

    # configure AllHostsFilter in /etc/nova/nova.conf
    iniset $NOVA_CONF_DIR/$NOVA_CONF_FILE DEFAULT scheduler_default_filters AllHostsFilter

    # Integrate nova-docker with Devstack

    #git_clone $NOVADOCKER_REPO $NOVADOCKER_PROJ_DIR $NOVADOCKER_BRANCH
    #cp -R $NOVADOCKER_PROJ_DIR/contrib/devstack/lib/* ${DEVSTACK_DIR}/lib/
    #cp $NOVADOCKER_PROJ_DIR/contrib/devstack/extras.d/* ${DEVSTACK_DIR}/extras.d/

    # Install docker
    #echo deb http://get.docker.com/ubuntu docker main | sudo tee /etc/apt/sources.list.d/docker.list
    #sudo apt-key adv --keyserver pgp5.ai.mit.edu --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9
    #sudo apt-get install -y apt-transport-https
    #sudo apt-get update
    #sudo apt-get install -y --force-yes lxc-docker-1.7.0
    # sudo wget -qO- https://get.docker.com/ | sed 's/lxc-docker/lxc-docker-1.7.0/' | sh
    #sudo curl -sSL https://get.docker.com/ | sh
    sudo wget -O docker.deb https://apt.dockerproject.org/repo/pool/main/d/docker-engine/docker-engine_1.7.1-0~trusty_amd64.deb
    sudo dpkg -i docker.deb

    # Install docker driver
    cd /opt/stack/nova-docker
    sudo python setup.py install
    sudo gpasswd -a ${USER} docker
    sudo usermod -aG docker ${USER}
    sudo chmod o=rwx /var/run/docker.sock

    if [ ! -d $NOVA_CONF_DIR/rootwrap.d ] ; then
        mkdir -p $NOVA_CONF_DIR/rootwrap.d
    fi

    #cp $NOVADOCKER_PROJ_DIR/$NOVA_CONF_DIR/rootwrap.d/docker.filters $NOVA_CONF_DIR/rootwrap.d/docker.filters
    sudo cp /opt/stack/nova-docker/etc/nova/rootwrap.d/docker.filters /etc/nova/rootwrap.d/.

    # configure Virtdriver in /etc/nova/nova.conf
    iniset $NOVA_CONF_DIR/$NOVA_CONF_FILE DEFAULT compute_driver novadocker.virt.docker.driver.DockerDriver

}

#register solum user in Keystone
function add_solum_user() {

    local SERVICE_TENANT=$(openstack project list | awk "/ $SERVICE_TENANT_NAME / { print \$2 }")
    echo "SERVICE_TENANT=$SERVICE_TENANT"

    # Register new service user as other services do
    SOLUM_USER_ID=$(openstack user create $SOLUM_USER \
       --password=$ADMIN_PASSWORD \
       --project $SERVICE_TENANT \
       --email=$SOLUM_USER@example.com \
       | grep " id " | get_field 2)

    local ADMIN_ROLE=$(openstack role list | awk "/ admin / { print \$2 }")
    echo "ADMIN_ROLE=$ADMIN_ROLE"

     openstack role add \
       --project $SERVICE_TENANT \
       --user $SOLUM_USER_ID \
       $ADMIN_ROLE
}

function add_additional_solum_users() {

    SOLUM_UPDATE_ROLE=$(openstack role show \
        solum_assembly_update \
        | grep " id " | get_field 2)

    ROLE_ID=$(openstack role create solum_user \
              | grep " id " | get_field 2)
    for _LETTER in a b c; do
        local TENANTNAME=solum_tenant_$_LETTER
        openstack project create \
            --description "Solum user tenant ${_LETTER^^}" \
            $TENANTNAME

        local USERNAME=solum_user_$_LETTER
        openstack user create \
            --password solum \
            --project $TENANTNAME \
            $USERNAME

        openstack role add $SOLUM_UPDATE_ROLE --project $TENANTNAME --user $USERNAME
        openstack role add $SOLUM_UPDATE_ROLE --project $TENANTNAME --user admin
    done
}

#create_solum_cache_dir() - Setup keystone signing folder
function create_solum_cache_dir() {
    sudo mkdir -p $SOLUM_AUTH_CACHE_DIR
    sudo chown $STACK_USER $SOLUM_AUTH_CACHE_DIR
    sudo chmod 700 $SOLUM_AUTH_CACHE_DIR
    rm -f $SOLUM_AUTH_CACHE_DIR/*
}

# init_solum() - Initialize databases, etc.
function init_solum() {
    recreate_database solum utf8
    # Run Solum db migrations
    solum-db-manage --config-file $SOLUM_CONF_DIR/$SOLUM_CONF_FILE upgrade head
    create_solum_cache_dir

    # NOTE (devkulkarni): Barbican is causing failures such as below
    # http://logs.openstack.org/33/206633/2/check/gate-solum-devstack-dsvm/933cbc3/logs/devstacklog.txt.gz#_2015-08-03_17_13_40_858
    # So temorarily commenting out barbican related code below.

    # if is_service_enabled barbican; then
    #    # Fix barbican configuration
    #    BARBICAN_API_CONF="/etc/barbican/barbican.conf"
    #    BARBICAN_HOST_HREF=$(iniget $BARBICAN_API_CONF DEFAULT host_href)
    #    BARBICAN_HOST_HREF=${BARBICAN_HOST_HREF/localhost/$SERVICE_HOST}
    #    iniset $BARBICAN_API_CONF DEFAULT host_href $BARBICAN_HOST_HREF
    #    if is_running barbican; then
    #        # NOTE(ravips): barbican.{pid,failure} is removed to overcome current
    #        # limitations of stop_barbican. stop_barbican calls screen_stop() only
    #        # to remove the pid but not to kill the process and this causes pkill
    #        # in screen_stop to return non-zero exit code which is trapped by
    #        # devstack/stack.sh
    #        if [ -f $SERVICE_DIR/$SCREEN_NAME/barbican.pid ]; then
    #            rm $SERVICE_DIR/$SCREEN_NAME/barbican.pid
    #        fi
    #        stop_barbican
    #        if [ -f $SERVICE_DIR/$SCREEN_NAME/barbican.failure ]; then
    #            rm $SERVICE_DIR/$SCREEN_NAME/barbican.failure
    #        fi
    #        start_barbican
    #    fi
    # fi
}

# install_solumclient() - Collect source and prepare
function install_solumclient {
    git_clone $SOLUMCLIENT_REPO $SOLUMCLIENT_DIR $SOLUMCLIENT_BRANCH
    setup_develop $SOLUMCLIENT_DIR
}

# install_solum() - Collect source and prepare
function install_solum() {
    # Install package requirements
    install_package expect

    git_clone $SOLUM_REPO $SOLUM_DIR $SOLUM_BRANCH
    # When solum is re-listed in openstack/requirements/projects.txt we
    # should change setup_package back to setup_develop.
    setup_package $SOLUM_DIR -e
}

# install_drone() - Install drone, but disable service
function install_drone() {
    if [[ $SOLUM_INSTALL_DRONE == 'True' ]]; then
        if [[ $os_VENDOR != 'Ubuntu' ]]; then
            echo 'Drone is currently only supported on Ubuntu'
            exit 1
        fi
        if [[ ! -e /usr/local/bin/drone ]]; then
            wget -O /tmp/drone.deb ${SOLUM_DRONE_URL}
            sudo dpkg -i /tmp/drone.deb
            rm /tmp/drone.deb
            sudo initctl stop drone || true
            sudo rm -f /etc/init/drone.conf || true
        fi
    fi
}

# install_docker() - Install Docker
function install_docker() {
    chmod +x $SOLUM_DIR/contrib/lp-cedarish/docker/get_docker_io.sh
    sudo $SOLUM_DIR/contrib/lp-cedarish/docker/get_docker_io.sh
    solum_install_docker_registry
}

# start_solum() - Start running processes, including screen
function start_solum() {
    screen_it solum-api "cd $SOLUM_DIR && $SOLUM_BIN_DIR/solum-api --config-file $SOLUM_CONF_DIR/$SOLUM_CONF_FILE"
    screen_it solum-conductor "cd $SOLUM_DIR && $SOLUM_BIN_DIR/solum-conductor --config-file $SOLUM_CONF_DIR/$SOLUM_CONF_FILE"
    screen_it solum-deployer "cd $SOLUM_DIR && $SOLUM_BIN_DIR/solum-deployer --config-file $SOLUM_CONF_DIR/$SOLUM_CONF_FILE"
    screen_it solum-worker "cd $SOLUM_DIR && $SOLUM_BIN_DIR/solum-worker --config-file $SOLUM_CONF_DIR/$SOLUM_CONF_FILE"

    if [[ $SOLUM_IMAGE_FORMAT == 'vm' ]]; then
        install_docker
        solum_install_start_docker_registry
        solum_install_core_os
    fi
}

# stop_solum() - Stop running processes
function stop_solum() {
    # Kill the solum screen windows
    screen -S $SCREEN_NAME -p solum-api -X kill
    screen -S $SCREEN_NAME -p solum-conductor -X kill
    screen -S $SCREEN_NAME -p solum-deployer -X kill
    screen -S $SCREEN_NAME -p solum-worker -X kill

    if [[ $SOLUM_IMAGE_FORMAT == 'vm' ]]; then
        solum_stop_docker_registry
    fi
}

# install_docker_registry() - Install and Start Docker Registry
# -------------------------------------------------------------
solum_install_start_docker_registry() {

 # install dependencies
   sudo apt-get update
   sudo apt-get -y install build-essential python-dev libevent-dev python-pip liblzma-dev git libssl-dev python-m2crypto swig

 # clone docker registry
   sudo git clone https://github.com/dotcloud/docker-registry.git /opt/docker-registry
   pushd /opt/docker-registry
   pip install -r requirements/main.txt
   popd

 # install docker
   curl -sSL https://get.docker.com/ubuntu/ | sudo sh

 # install docker registry
   pip_command=`which pip`
   pip_build_tmp=$(mktemp --tmpdir -d pip-build.XXXXX)
   $pip_command install /opt/docker-registry --build=${PIP_BUILD_TMP}

 # initialize config file
   cp /opt/docker-registry/docker_registry/lib/../../config/config_sample.yml /opt/docker-registry/docker_registry/lib/../../config/config.yml

 # start docker registry
   gunicorn --access-logfile - --debug -k gevent -b 0.0.0.0:5042 -w 1 docker_registry.wsgi:application &

}

solum_stop_docker_registry() {
    screen -S $SCREEN_NAME -p docker-registry -X kill
    rm -rf ${PIP_BUILD_TMP}
}

solum_install_core_os() {
  wget http://alpha.release.core-os.net/amd64-usr/current/coreos_production_openstack_image.img.bz2
  bunzip2 coreos_production_openstack_image.img.bz2
  glance image-create --name coreos --container-format bare --disk-format qcow2 --file coreos_production_openstack_image.img
}


# Main dispatcher
#----------------

if is_service_enabled solum-api solum-conductor solum-deployer solum-worker; then
    #echo "Checking for Docker"
    #if [ ! -f /usr/bin/docker ] ; then
    #   echo deb http://get.docker.com/ubuntu docker main | sudo tee /etc/apt/sources.list.d/docker.list
    #   sudo apt-key adv --keyserver pgp5.ai.mit.edu --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9
    #   sudo apt-get install -y apt-transport-https
    #   sudo apt-get update
    #   sudo apt-get install -y --force-yes lxc-docker-1.7.0
    #fi
    if [[ "$1" == "stack" && "$2" == "install" ]]; then
        echo_summary "Installing Solum"
        install_solum
        install_solumclient
    elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
        echo_summary "Configuring Solum"
        add_solum_user
        configure_solum

        if is_service_enabled key; then
           create_solum_service_and_endpoint
        fi
        add_additional_solum_users
    elif [[ "$1" == "stack" && "$2" == "extra" ]]; then
        echo_summary "Initializing Solum"
        init_solum
        start_solum
    fi

    if [[ "$1" == "unstack" ]]; then
        stop_solum
    fi
fi


# Restore xtrace
$XTRACE

# Local variables:
# mode: shell-script
# End:
