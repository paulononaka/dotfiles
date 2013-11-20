#
# Variables
#
WFH_SOCKS_PORT="12345"

#
# K7
#
alias no-k7="no-spec-k7 && no-spinach-k7"
alias no-spec-k7="rm -rf spec/cassettes"
alias no-spinach-k7="rm -rf features/cassettes"

alias k7-less-rspec="no-spec-k7 && rspec"
alias k7-less-spinach="no-spinach-k7 && spinach"

alias rspeci="rspec --require rspec/instafail --format RSpec::Instafail"

check-iba-requirements(){
  identify --version 1> /dev/null || {
    echo "Missing requirement: imagemagick"
    return 1
  }
}

_has_wfh_proxy_up(){
  netstat -an | grep $WFH_SOCKS_PORT | grep -q LISTEN
}

_check_wfh_proxy_up(){
  _has_wfh_proxy_up || {
    echo "No socks proxy running."
    echo "Please, run 'iba-wfh-setup'."
    return 1
  }
}

# WFH
iba-wfh-setup() {
  [ -z "$NODE_ON_DEVCLOUD" ] && {
    echo "Missing configuration: NODE_ON_DEVCLOUD"
    return 1
  }

  _has_wfh_proxy_up || {
    echo "No socks proxy running at $WFH_SOCKS_PORT port!"
    echo "Connecting to $NODE_ON_DEVCLOUD"

    ssh -fND $WFH_SOCKS_PORT $NODE_ON_DEVCLOUD
  }

  _has_wfh_proxy_up && {
    echo "Everything is set up. Remember to use 'bundle-from-home' and 'morning-from-home' when needed."
  }
}

# Run bundle through a SOCKS v5 proxy
bundle-from-home() {
  _check_wfh_proxy_up

  # TODO: check if there is rvm-bundler gem. SHOULD NOT have

  echo "Running $(which bundle) $*"
  socksify_ruby localhost 12345 `which bundle` $*
}

# rake morning from home
morning-from-home() {
  _check_wfh_proxy_up

  git pull --rebase
  rake git:clone
  rake git:rebase
  rake foreach 'socksify_ruby localhost 12345 `which bundle` install'

  # must run orders through socksify
}

# Quick access
iba() { cd ~/tw/iba/$1;  }
_iba() { _files -W ~/tw/iba -/; }
compdef _iba iba

# Use the production dump locally
iba-production() {
  mongorestore --drop /tw/data/dump
  rake foreach:all "sed -i'_' 's/_development//g' config/mongoid.yml"
}

iba-development() {
  rake foreach:all "git co config/mongoid.yml && rm -rf config/mongoid.yml_"
}

run() {
  SERVER=$(basename $PWD)
  PORT=$(cd .. &>/dev/null && exec rake -D | grep -E "Start.*$SERVER.*port: .*" | sed -E 's/.*port: ([0-9]+).*/\1/')
  (cd .. &>/dev/null && rake "stop:$SERVER" &>/dev/null)
  bundle exec rackup -p $PORT -s thin
}

run-with-socks() {
  SERVER=$(basename $PWD)
  PORT=$(cd .. &>/dev/null && exec rake -D | grep -E "Start.*$SERVER.*port: .*" | sed -E 's/.*port: ([0-9]+).*/\1/')
  (cd .. &>/dev/null && rake "stop:$SERVER" &>/dev/null)
  socksify_ruby localhost 12345 `which bundle` exec rackup -p $PORT -s thin
}

restart() {
  SERVER=$(basename $PWD)
  (cd .. &>/dev/null && rake "restart:$SERVER" &>/dev/null)
}

iba-clean() {
  curl -u 'api_admin:password' --basic -X DELETE "http://localhost:5100/everything"
}

iba-seed() {
  curl -u 'api_admin:password' --basic "http://localhost:5100/seed?book_count=10&newspaper_count=10&magazine_count=10"
  curl -u 'api_admin:password' --basic "http://localhost:5500/seed"
}

iba-reseed(){
  iba-clean
  iba-seed
}

spinach-safe() {
  for feature in features/specifications/**/*.feature; do
    spinach $feature || {
      #say -v Agnes "Houston, we have a problem"
      terminal-notifier -message "The feature file:\n$feature\n\nFailed." -title "Spinach Failed"
    }
  done
}

