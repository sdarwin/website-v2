# Copyright 2024 Sam Darwin
#
# Distributed under the Boost Software License, Version 1.0.
# (See accompanying file LICENSE_1_0.txt or copy at http://boost.org/LICENSE_1_0.txt)


param (
   [Parameter(Mandatory=$false)][alias("repo")][string]$repooption = "",
   [switch]$help = $false,
   [switch]${launch} = $false,
   [switch]${all} = $false
)

# set defaults:
${prereqsoption}="yes"
$scriptname="dev-bootstrap-win.ps1"
$pythonvirtenvpath="${HOME}\venvboostdocs"

# docker_mode either "native" or "desktop" (Docker Desktop). win only support "desktop" currently.
docker_mode="desktop"

if (${docker_mode} -eq "native")
{
    # Not supported on win currently, or ever.
    ${repo_path_base}="/opt/github"
    ${completion_message_1}="When doing development work, switch to the root user 'sudo su -', cd to that directory location, and run 'docker compose up -d'"
}
if (${docker_mode} -eq "desktop")
{
    ${repo_path_base}="${HOME}/github"
    ${completion_message_1}="When doing development work, cd to that directory location, and run 'docker compose up -d'"
}

# Set-PSDebug -Trace 1

if ($help) {

$helpmessage="
usage: $scriptname [-help] [-repo REPO] [-launch] [-all]

Builds library documentation.

optional arguments:
  -help                 Show this help message and exit
  -repo REPO            Name of repository to set up. Example: https://github.com/boostorg/website-v2. You should specify your own fork.
  -launch               Run docker-compose. No packages.
  -all                  Both packages and launch.
"

echo $helpmessage
exit 0
}

if ($launch) {
    ${launchoption} = "yes"
	${prereqsoption}="no"
 }

if ($all) {
    ${launchoption} = "yes"
	${prereqsoption}="yes"
}

pushd

function refenv {

    # Make `refreshenv` available right away, by defining the $env:ChocolateyInstall
    # variable and importing the Chocolatey profile module.
    # Note: Using `. $PROFILE` instead *may* work, but isn't guaranteed to.
    $env:ChocolateyInstall = Convert-Path "$((Get-Command choco).Path)\..\.."
    Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"

    # refreshenv might delete path entries. Return those to the path.
    $originalpath=$env:PATH
    refreshenv
    $joinedpath="${originalpath};$env:PATH"
    $joinedpath=$joinedpath.replace(';;',';')
    $env:PATH = ($joinedpath -split ';' | Select-Object -Unique) -join ';'
    }

# git is required. In the unlikely case it's not yet installed, moving that part of the package install process
# here to an earlier part of the script:


if ( -Not (Get-Command choco -errorAction SilentlyContinue) ) {
    echo "Install chocolatey"
    iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))
	refenv
}

if ( -Not (Get-Command git -errorAction SilentlyContinue) ) {
    echo "Install git"
    choco install -y --no-progress git
	refenv
}

function DownloadWithRetry([string] $url, [string] $downloadLocation, [int] $retries)
{
    while($true)
    {
        try
        {
	    # Invoke-WebRequest $url -OutFile $downloadLocation
	    Start-BitsTransfer -Source $url -Destination $downloadLocation
            break
        }
        catch
        {
            $exceptionMessage = $_.Exception.Message
            Write-Host "Failed to download '$url': $exceptionMessage"
            if ($retries -gt 0) {
                $retries--
                Write-Host "Waiting 10 seconds before retrying. Retries left: $retries"
                Start-Sleep -Seconds 10
 
            }
            else
            {
                $exception = $_.Exception
                throw $exception
            }
        }
    }
}

echo "Chosen options: pre: ${prereqsoption} launch: ${launchoption} repo: ${repooption}"

# Determine git repo

$originurl=git config --get remote.origin.url
if ($LASTEXITCODE -eq 0)  {
    ${detected_repo_url}=[io.path]::ChangeExtension($originurl, [NullString]::Value)
}
else {
    ${detected_repo_url}="empty"
}

## detected_repo_org=$(basename $(dirname "${detected_repo_url}"))

$repopath=git rev-parse --show-toplevel
if ($LASTEXITCODE -eq 0)  {
    ${detected_repo_path}=$repopath | % {$_ -replace '/','\'} 
}
else {
    ${detected_repo_path}="nofolder"
}

${detected_repo_path_base}=[io.path]::GetDirectoryName($detected_repo_path)

if ( ${detected_repo_url} -and -not (${detected_repo_url} -eq "empty") -and ${repooption} ) {
    echo "You have specified a repo, but you are also running this script from within a repo."
    echo "This is indeterminate. Choose one or the other. Exiting."
    exit 1
    }
elseif ( ${detected_repo_url} -and -not (${detected_repo_url} -eq "empty") {
    echo "You are running the script from an existing repository. That will be used."
    ${repo_url}=${detected_repo_url}
    ${repo_name}=${detected_repo_name}
    ${repo_path}=${detected_repo_path}
    ${repo_path_base}=${detected_repo_path_base}
    echo "The repo path is ${repo_path}"
    cd "${repo_path}"
    if ( !(Test-Path .env ) { 
        cp env.template .env
        }
}
else {
    if (${repooption} ) {
        echo "You have specified a repository on the command line. That will be preferred. ${repooption}"
        ${repo_url}=${repooption}
	}
    else {
        $repo_url = Read-Host "Please enter a full git repository url with a format such as https:://github.com/_your_name_/website-v2"
    }

	if ($repo_url)  {
        ${repo_name}=[io.path]::GetFileNameWithoutExtension($repo_url)
    else {
        ${detected_repo_url}="empty"
    }
	
	${repo_org_part_1}=[io.path]::GetDirectoryName($repo_url) 
    ${repo_org}=[io.path]::GetFileNameWithoutExtension($repo_org_part_1)
    ${repo_path_base}="${repo_path_base}/${repo_org}"
    ${repo_path}="${repo_path_base}/${repo_name}"
    echo "The path will be ${repo_path}"
    mkdir -p "${repo_path_base}"
    cd "${repo_path_base}"
    if ! (Test-Path -Path ${repo_path}) {
        git clone "${repo_url}"
    }
    cd "${repo_name}"
     if ! (Test-Path .env) {
        cp env.template .env
	 }
	}

# Check .env file


$searchresults = Select-String -pattern "STATIC_CONTENT_AWS_ACCESS_KEY_ID" .env | Select-String -pattern "changeme"
if ($searchresults -eq $null) {
    # "No matches found"
	% 'foo'
} else {
    "Matches found in the following files"
    $unsetawskey="yes"
}

$searchresults = Select-String -pattern "STATIC_CONTENT_AWS_SECRET_ACCESS_KEY" .env | Select-String -pattern "changeme"
if ($searchresults -eq $null) {
    # "No matches found"
	% 'foo'
} else {
    "Matches found in the following files"
    $unsetawskey="yes"
}

if ($unsetawskey) { 
    echo "There appears to be aws keys in your .env file that says 'changeme'. Please set them before proceeding."
    echo "Talk to an administrator or other developer to get the keys."
	$REPLY = Read-Host "Do you want to continue? y/n"
    if (($REPLY -eq "y") -or ($REPLY -eq "Y")) {
        echo "we are continuing"
	}
    else {
        echo "did not receive a Yy. Exiting."
        exit 1
    }
}

if ($prereqsoption -eq "yes") {

    if ( -Not (Get-Command just -errorAction SilentlyContinue) )
        choco install -y --no-progress just
    }

    if ( -Not (Get-Command python -errorAction SilentlyContinue) )
        choco install -y --no-progress python
    }

    if ( -Not (Get-Command nvm -errorAction SilentlyContinue) )
		choco install -y --no-progress nvm
        nvm install 20
        nvm use 20
        echo "Run . ~/.zprofile to enable nvm"
    }

    if ( -Not (Get-Command yarn -errorAction SilentlyContinue) )
        npm install -g yarn
    }
	
    if ( -Not (Get-Command docker -errorAction SilentlyContinue) )
        echo "Installing Docker Desktop"
        choco install -y --no-progress docker-desktop
		
        # echo "The Docker Desktop dmg package has been installed."
        # echo "The next step is to go to a desktop GUI window on the Mac, run Docker Desktop, and complete the installation."
        # echo "Then return here."
        # read -r -p "Do you want to continue? y/n" -n 1 -r
        # echo    # (optional) move to a new line
        # if [[ $REPLY =~ ^[Yy]$ ]]
        # then
        #     echo "we are continuing"
        # else
        #     echo "did not receive a Yy. Exiting. You may re-run the script."
        #     exit 1
        # fi
    }

    echo "The 'installation' section of this script is complete."
    echo "The location of your docker compose installation is ${repo_path}."
    echo ""
    if [[ "$launchoption" != "yes" ]]; then
        echo "You may run this script again with the --launch option, to launch docker compose and run db migrations".
        echo ""
    fi
    echo ${completion_message_1}
fi

if [[ "$launchoption" == "yes" ]]; then
    if ! command -v nvm &> /dev/null
    then
        . ~/.zprofile
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
