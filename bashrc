# Splunk environment helper for Macs
# Version 1.3

# Fixes in 1.1
# - fixed svm started, used to break if - or . was in the Splunk instance name

# Features new in 1.2
# - svm stop-all
# ---  stop all running Splunk instances
# - svm stop-others
# ---  stop all running Splunk instances except the current select Splunk instance

# Features new in 1.3
# - svm restart-all
# --- restarts all splunk instances 
# - svm rebase
# --- resets SPLUNK_BASE to the current directory
# - svm cmd-all <cmd>
# --- runs cmd in all splunk instances 
# - svm cmd-started <cmd>
# --- runs cmd in running splunk instances 
# - tab completion semi-fixes (still some TODO)

# Changes in 1.4
# 
# - Add create|install option to create a new Splunk instance in SPLUNK_BASE from
#   the compressed tar image indicated by SPLUNK_VERSION.
#   This command will assign new web and mgmt ports if other Splunk instances are installed
#   so that multiple versions of Splunk can be run if required.
#
# - Add stop option to stop current Splunk instance.
#
# - Add restart option to restart current Splunk instance.
#
# - Add remove option to remove current Splunk instance.
#
# - Add clean option to clean up Splunk processes.
#
# - Changed open option to start Splunk if it's not already running.
#
# - Changed the output of the list option to include a Running indicator.
#
# - Changed instance selection to cd to SPLUNK_HOME.
#
# - Fixed autocompletion rules.

# Change these 4 things if needed, plus maybe the PS1 setting and the shell edit mode
# towards the bottom (depending on terminal color)
# Where to locate Splunk software packages
SPLUNK_SOFTWARE=$HOME/SplunkSoftware
# The version of instances to create.
SPLUNK_VERSION=6.1.1-207789-darwin-64
# The instance to default to when starting a new shell
SPLUNK_DEFAULT=sandbox
# Where to find and create Splunk instances
SPLUNK_BASE=$HOME/SplunkDemo

_splunk="splunk --accept-license"

if [[ ! -d $SPLUNK_BASE ]]; then
  mkdir -p $SPLUNK_BASE
fi

# Tab completion for svm
_svm() {
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  opts="list li"
  insts=$(\ls $SPLUNK_BASE/*/bin/splunk | while read path; do
    echo "$(echo $path | sed "s|$SPLUNK_BASE/\([^\/]*\)/bin/splunk|\1|")"
  done)

  case "$prev" in
    list|li)
      COMPREPLY=($(compgen -W "installed running sourced" -- $cur))
      return 0
      ;;
    *)
      COMPREPLY=($(compgen -W "clean cmd cmd-all create home install latest list open remove restart restart-all started stop stop-all stop-others $insts" -- $cur))  
      return 0
      ;;
  esac
}

iterate_instances() {
  if [[ $(\ls $SPLUNK_BASE) ]]; then
    \ls $SPLUNK_BASE/*/bin/splunk | while read path; do
      webport=$(get_web_port $(dirname $(dirname $path)))
      mgmtport=$(get_mgmt_port $(dirname $(dirname $path)))
      instance=$(echo $path | sed "s|$SPLUNK_BASE/\([^\/]*\)/bin/splunk|\1|")
      version=$($path --accept-license version 2>/dev/null | sed "s/Splunk \([^ ]*\) (build \([^)]*\))/splunk-\1-\2/")

      if echo $(svm started) | grep -q $instance; then
        stat="Y"
      else
        stat="N"
      fi

      printf "%-20s %-20s %-10s %-10s %-10s\n" $instance $version $webport $mgmtport $stat
    done
  else
    echo ""
  fi
}

get_item() {
  regex="$1"
  path="$2"
  result=$(grep "$regex" $path/etc/system/local/web.conf 2>/dev/null)

  if [[ -z $result ]]; then
    result=$(grep "$regex" $path/etc/system/default/web.conf 2>/dev/null)
  fi

  echo "$result"
}

get_web_port() {
  get_item "^httpport *=" $1 | awk '{print $3}'
}

set_web_port() {
  hiport=$(iterate_instances | awk '{print $1}' | while read instance; do
      get_web_port $SPLUNK_BASE/$instance
    done | sort | tail -n 1)

  if [[ -z $hiport ]]; then
    echo ""
  else
    echo $((hiport+1))
  fi
}

get_mgmt_port() {
  get_item "^mgmtHostPort *=" $1 | awk -F: '{print $2}'
}

set_mgmt_port() {
  hiport=$(iterate_instances | awk '{print $1}' | while read instance; do
      get_mgmt_port $SPLUNK_BASE/$instance
    done | sort | tail -n 1)

  if [[ -z $hiport ]]; then
    echo ""
  else
    echo $((hiport+1))
  fi
}

svm_header() {
  printf "%-20s %-20s %-10s %-10s %-10s\n" "Name" "Version" "WebPort" "MgmtPort" "Running"
  printf "%-20s %-20s %-10s %-10s %-10s\n" "====" "=======" "=======" "========" "======="
}

svm() {
  if [[ $1 == list || $1 == li || $1 == status ]]; then

    if [[ -z $2 || $2 == installed ]]; then

      if [[ $1 == list || $1 == status ]]; then
        svm_header
      fi

      iterate_instances

    elif [[ $2 == sourced ]]; then
      basename $SPLUNK_HOME 2>/dev/null

    elif [[ $2 == running ]]; then
      # grab the management port from the process list
      ps -ef | grep "\[splunkd" | grep -v grep | grep -v search | awk '//{print $12}' | sort -u 
    fi

  elif [[ $1 == started ]]; then
    ps auxwwe | grep "\[splunkd" | grep -v search | grep -v grep | perl -wlne 'print $3 if /(SPLUNK_HOME=\/(\w+\/)*([\w\-\.]+))/'

  elif [[ $1 == latest ]]; then
    curl http://www.splunk.com/page/release_rss 2>/dev/null | xmllint --xpath "//channel/item[1]/title/text()" -   

  elif [[ $1 == create || $1 == install ]]; then
    if [[ -z $2 ]]; then
      echo "No instance name specified!"
    else
      OLDWD=$CWD
      if [[ $CWD != $SPLUNK_BASE ]]; then
        cd $SPLUNK_BASE
      fi
      # First check whether this instance already exists
      if [[ -d $2 ]]; then
        echo "Splunk instance $2 already exists!"
        cd $OLDWD
      else
        # Calculate new port numbers if instances already exist
        newwebport=$(set_web_port)
        newmgmtport=$(set_mgmt_port)

        # Create the directory and extract the image
        mkdir -p $SPLUNK_BASE/$2
        cd $SPLUNK_BASE/$2
        tar -xz --strip-components 1 -f $SPLUNK_SOFTWARE/splunk-$SPLUNK_VERSION.tgz

        # Set the svm context to the newly created instance
        svm $2

        # Run Splunk to accept the EULA
        $_splunk status > /dev/null

        # Set a new web and mgmt port number
        if [[ $newwebport != "" ]]; then
          $_splunk set web-port $newwebport
        fi
        if [[ $newmgmtport != "" ]]; then
          $_splunk set splunkd-port $newmgmtport
        fi
      fi
    fi

  elif [[ $1 == remove ]]; then
    result=$(svm started | grep "$(svm list sourced)")
    if [[ $result != "" ]]; then
      # The instance we're trying to remove is running, so let's stop it!
      $_splunk stop
    fi
    cd $SPLUNK_BASE
    rm -rf $(svm list sourced)
    # Reset SPLUNK_HOME
    unset SPLUNK_HOME

  elif [[ $1 == open ]]; then
    result=$(svm started | grep "$(svm list sourced)")
    if [[ $result == "" ]]; then
      # The instance we're trying to run is not started, so let's start it!
      $_splunk start
    fi
    # construct the URL path
    webport=$(get_web_port $SPLUNK_HOME)
    SSL=$($_splunk btool web list | grep enableSplunkWebSSL | awk '//{print $3}')
    [[ $SSL = "true" ]] && PROTO="https" || PROTO="http"
    # open the Splunk webpage
    open $PROTO://localhost:$webport

  elif [[ $1 == "stop" ]]; then
    $_splunk stop
  
  elif [[ $1 == "stop-all" ]]; then
    CURRENT=$(svm list sourced)
    for splunk in $(svm started)
    do
      svm $splunk
      $_splunk stop
    done
    svm $CURRENT

  elif [[ $1 == "stop-others" ]]; then
    CURRENT=$(svm list sourced)
    for splunk in $(svm started)
    do
      if [ "$splunk" != "$CURRENT" ]; then
        svm $splunk
        $_splunk stop
      fi
    done
    svm $CURRENT

  elif [[ $1 == "rebase" ]]; then
    SPLUNK_BASE=`pwd`

  elif [[ $1 == "cmd-started" ]]; then
    CURRENT=$(svm list sourced)

    for splunk in $(svm started)
    do
      svm $splunk
      ${@:2}
    done
    svm $CURRENT

  elif [[ $1 == "cmd-all" ]]; then
    CURRENT=$(svm list sourced)

    insts=$(\ls $SPLUNK_BASE/*/bin/splunk | while read path; do
      echo "$(echo $path | sed "s|$SPLUNK_BASE/\([^\/]*\)/bin/splunk|\1|")"
    done)
    for splunk in $insts
    do
      svm $splunk
      ${@:2}
    done
    svm $CURRENT

  elif [[ $1 == "restart" ]]; then
    $_splunk restart

  elif [[ $1 == "restart-all" ]]; then
    CURRENT=$(svm list sourced)
    for splunk in $(svm started)
    do
      svm $splunk
      $_splunk restart
    done
    svm $CURRENT

  elif [[ $1 == home && -n $SPLUNK_HOME ]]; then
    cd $SPLUNK_HOME

  elif [[ -n $1 && -d $SPLUNK_BASE/$1 ]]; then
    stripped_path=$(echo $PATH | sed "s|$SPLUNK_BASE/[^:]*:*||g")
    export SPLUNK_HOME=$SPLUNK_BASE/$1
    export PATH=$SPLUNK_HOME/bin:$stripped_path
    export CDPATH=.:~:$SPLUNK_BASE:$SPLUNK_HOME:$SPLUNK_HOME/etc:$SPLUNK_HOME/etc/apps
    svm home

  elif [[ $1 == clean ]]; then
    ps -ef | grep "splunkd" | grep -v "grep" | awk '{print $2}' | xargs kill
    ps -ef | grep "python" | grep -v "grep" | awk '{print $2}' | xargs kill

  else
    echo "Usage:"
    echo ""
    echo "svm <instance_name>        : switch selected instance"
    echo "svm list|status            : list all installed Splunk instances"
    echo "svm home                   : change current dir to SPLUNK_HOME"
    echo "svm started                : show currently started Splunk instances"
    echo "svm latest                 : check the internet for the latest release of Splunk"
    echo "svm create <instance_name> : create a new Splunk instance of <instance_name>"
    echo "svm install <instance_name>: synonym for svm create <instance_name>"
    echo "svm open                   : start & open Splunk instance in the default browser"
    echo "svm stop                   : stop Splunk instance"
    echo "svm stop-all               : stop all running Splunk instances"
    echo "svm stop-others            : stop all other running Splunk instances"
    echo "svm restart                : restarts current Splunk instance"
    echo "svm restart-all            : restarts all Splunk instances"
    echo "svm rebase                 : resets SPLUNK_BASE to the current directory"
    echo "svm cmd-all <cmd>          : runs cmd in all Splunk instances"
    echo "svm cmd-started <cmd>      : runs cmd in running Splunk instances"
    echo "svm clean                  : kill Splunk processes"

  fi
}

#creates a list of running management ports
active_sids() {
  svm list running | sed -e :a -e '$!N; s/\n/,/; ta'
}

show_hidden() {
  arg=TRUE
  [[ $1 == no || $1 == false ]] && arg=FALSE
  defaults write com.apple.finder AppleShowAllFiles $arg
  killall Finder
}

# for Emcas fans
set -o emacs
# for Vi fans
#set -o vi

# completion for svm (i.e. svm d<TAB> -> svm demo)
complete -F _svm svm 

# for dark terminals
export PS1="\n\[\e[0;40m\]\u:\[\e[0m\]\[\e[35;40m\](\$(active_sids))\[\e[0m\]\[\e[34;40m\][\$(svm list sourced)]\[\e[0m\]\[\e[0;40m\]:\w\[\e[0m\]> "
# for light terminals
#export PS1="\n\[\e[30;47m\]\u:\[\e[30m\]\[\e[35;47m\](\$(active_sids))\[\e[0m\]\[\e[34;47m\][\$(svm list sourced)]\[\e[0m\]\[\e[30;47m\]:\W\[\e[0m\]> "

# Change "demo" to your default instance
[[ -z $SPLUNK_HOME ]] && svm $SPLUNK_DEFAULT

export CLICOLOR=1
alias ls="ls -F"
