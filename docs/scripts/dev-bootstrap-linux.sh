#!/bin/bash

# Copyright 2024 Sam Darwin
#
# Distributed under the Boost Software License, Version 1.0.
# (See accompanying file LICENSE_1_0.txt or copy at http://boost.org/LICENSE_1_0.txt)

set -e
# set -x
# shopt -s extglob
# shopt -s dotglob

scriptname="dev-bootstrap-linux.sh"

# set defaults:
prereqsoption="yes"
repo_path_base=${HOME}/github
shell_startup_script=.bashrc

# READ IN COMMAND-LINE OPTIONS

TEMP=$(getopt -o h:: --long repo:,help::,launch::,prereqs::,all:: -- "$@")
eval set -- "$TEMP"

# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -h|--help)
            helpmessage="""
usage: $scriptname [-h] [--repo REPO] [--launch] [--all]

Install all required packages (this is the default action), launch docker-compose, or both. 

optional arguments:
  -h, --help            Show this help message and exit
  --repo REPO           Name of repository to set up. Example: https://github.com/boostorg/website-v2. You should specify your own fork.
  --launch              Run docker-compose. No packages.
  --all			Both packages and launch.
"""

            echo ""
	    echo "$helpmessage" ;
	    echo ""
            exit 0
            ;;
        --repo)
            case "$2" in
                "") repooption="" ; shift 2 ;;
                 *) repooption=$2 ; shift 2 ;;
            esac ;;
	--launch)
	    launchoption="yes" ; prereqsoption="no" ; shift 2 ;;
	--all)
	    prereqsoption="yes" ; launchoption="yes" ; shift 2 ;;
        --) shift ; break ;;
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

echo "Chosen options: pre: $prereqsoption launch: $launchoption repo: $repooption"

# Determine git repo

detected_repo_url=$(git config --get remote.origin.url 2> /dev/null || echo "empty")
detected_repo_name=$(basename -s .git "$(git config --get remote.origin.url)" 2> /dev/null || echo "empty")
detected_repo_org=$(basename $(dirname "${detected_repo_url}"))
detected_repo_path=$(git rev-parse --show-toplevel 2> /dev/null || echo "nofolder")
detected_repo_path_base=$(dirname "${detected_repo_path}")

if [[ -n "${detected_repo_url}" && "${detected_repo_url}" != "empty" && -n "${repooption}" ]]; then
    echo "You have specified a repo, but you are also running this script from within a repo."
    echo "This is indeterminate. Choose one or the other. Exiting."
    exit 1
elif [[ -n "${detected_repo_url}" && "${detected_repo_url}" != "empty" ]]; then
    echo "You are running the script from an existing repository. That will be used."
    repo_url=${detected_repo_url}
    repo_name=${detected_repo_name}
    repo_path=${detected_repo_path}
    repo_path_base=${detected_repo_path_base}
    echo "The repo path is ${repo_path}"
    cd "${repo_path}"
    if [ ! -f .env ]; then
        cp env.template .env
    fi
else
    if [ -n "${repooption}" ]; then
        echo "You have specified a repository on the command line. That will be preferred. ${repooption}"
        repo_url=${repooption}
    else 
        echo "Please enter a full git repository url with a format such as https:://github.com/boostorg/website-v2"
        read -r repo_url
    fi
    repo_name=$(basename -s .git "$repo_url" 2> /dev/null || echo "empty")
    repo_org=$(basename $(dirname "${repo_url}"))
    repo_path_base="${repo_path_base}/${repo_org}"
    repo_path="${repo_path_base}/${repo_name}"
    echo "The path will be ${repo_path}"
    mkdir -p "${repo_path_base}"
    cd "${repo_path_base}"
    if [ ! -d "${repo_name}" ]; then
        git clone "${repo_url}"
    fi
    cd "${repo_name}"
    if [ ! -f .env ]; then
        cp env.template .env
    fi
fi

# Check .env file

if grep STATIC_CONTENT_AWS_ACCESS_KEY_ID .env | grep changeme; then
    unsetawskey="yes"
fi
if grep STATIC_CONTENT_AWS_SECRET_ACCESS_KEY .env | grep changeme; then
    unsetawskey="yes"
fi

if [[ $unsetawskey == "yes" ]]; then
    echo "There appears to be aws keys in your .env file that says 'changeme'. Please set them before proceeding."
    echo "Talk to an administrator or other developer to get the keys."
    read -r -p "Do you want to continue? " -n 1 -r
    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        echo "we are continuing"
    else
        echo "did not receive a Yy. Exiting."
        exit 1
    fi
fi

if [[ "$prereqsoption" == "yes" ]]; then

    # sudo apt-get update
    x="\$nrconf{restart} = 'a';"
    echo "$x" | sudo tee /etc/needrestart/conf.d/90-autorestart.conf

    if ! command -v makedeb &> /dev/null
    then
        echo "Installing makdeb"
        MAKEDEB_RELEASE=makedeb bash -ci "$(wget -qO - 'https://shlink.makedeb.org/install')"
    fi
    if ! command -v git &> /dev/null
    then
        echo "Installing git"
        sudo apt-get install -y git
    fi

    if ! command -v python3 &> /dev/null
    then
        echo "Installing python3"
        sudo apt-get install -y python3
    fi
    if ! command -v just &> /dev/null
    then
        echo "Installing just"
        startdir=$(pwd)
        sudo mkdir -p /opt/justinstall
        CURRENTUSER=$(whoami)
        sudo chown "$CURRENTUSER" /opt/justinstall
        chmod 777 /opt/justinstall
        cd /opt/justinstall
        git clone 'https://mpr.makedeb.org/just'
        cd just
        makedeb -si
        cd "$startdir"
    fi

    if ! command -v nvm &> /dev/null
    then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
        . ${shell_startup_script}
        nvm install 20
        nvm use 20
        echo "Run . ${shell_startup_script} to enable nvm"
    fi

    if ! command -v yarn &> /dev/null
    then
        npm install -g yarn
    fi

    if ! docker compose &> /dev/null ; then
        echo "Installing docker-compose"
        sudo apt-get install -y ca-certificates curl gnupg
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo \
          deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    # "Add current user to docker group"
    sudo usermod -aG docker "$USER"

    if ! id | grep docker; then
        echo "Your user account has just been added to the 'docker' group. Please log out and log in again. Check groups with the id command."
        echo "The installation section of this script is complete. After logging in again, you may proceed to manually running docker compose."
	echo "Or run this script again with --launch to start containers."
    fi

    echo "The installation section of this script is complete."
fi

if [[ "$launchoption" == "yes" ]]; then
    if ! command -v nvm &> /dev/null
    then
        . ${shell_startup_script}
    fi

    cd "${repo_path}"
    echo "Launching docker compose"
    echo "Let's wait for that to run. Sleeping 60 seconds."
    docker compose up -d
    sleep 60
    echo "Creating superuser"
    docker compose run --rm web python manage.py createsuperuser
    echo "Creating database migrations"
    docker compose run --rm web python manage.py makemigrations 
    echo "running database migrations"
    docker compose run --rm web python manage.py migrate
    echo "Running yarn"
    yarn
    yarn build
    cp static/css/styles.css static_deploy/css/styles.css
    echo "In your browser, visit http://localhost:8000"
    echo "Later, to shut down: docker compose down"
fi

