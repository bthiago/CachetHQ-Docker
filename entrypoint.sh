#!/bin/bash
set -eo pipefail

[[ "${CACHETHQ_DEBUG}" == true ]] && set -x

check_database_connection() {
  echo "Attempting to connect to database ..."
  case "${CACHETHQ_DB_DRIVER}" in
    mysql)
      prog="mysqladmin -h ${CACHETHQ_DB_HOST} -u ${CACHETHQ_DB_USERNAME} ${CACHETHQ_DB_PASSWORD:+-p$CACHETHQ_DB_PASSWORD} -P ${CACHETHQ_DB_PORT} status"
      ;;
    pgsql)
      prog="/usr/bin/pg_isready"
      prog="${prog} -h ${CACHETHQ_DB_HOST} -p ${CACHETHQ_DB_PORT} -U ${CACHETHQ_DB_USERNAME} -d ${CACHETHQ_DB_DATABASE} -t 1"
      ;;
  esac
  timeout=60
  while ! ${prog} >/dev/null 2>&1
  do
    timeout=$(( $timeout - 1 ))
    if [[ "$timeout" -eq 0 ]]; then
      echo
      echo "Could not connect to database server! Aborting..."
      exit 1
    fi
    echo -n "."
    sleep 1
  done
  echo
}

checkdbinitmysql() {
    table=sessions

    if [[ "$(mysql -N -s -h ${CACHETHQ_DB_HOST} -u ${CACHETHQ_DB_USERNAME} ${CACHETHQ_DB_PASSWORD:+-p$CACHETHQ_DB_PASSWORD} ${CACHETHQ_DB_DATABASE} -P ${CACHETHQ_DB_PORT} -e \
        "select count(*) from information_schema.tables where \
            table_schema='${CACHETHQ_DB_DATABASE}' and table_name='${CACHETHQ_DB_PREFIX}${table}';")" -eq 1 ]]; then
        echo "Table ${CACHETHQ_DB_PREFIX}${table} exists! ..."
    else
        echo "Table ${CACHETHQ_DB_PREFIX}${table} does not exist! ..."
        init_db
    fi

}

checkdbinitpsql() {
    table=sessions
    export PGPASSWORD=${CACHETHQ_DB_PASSWORD}

    if [[ "$(psql -h ${CACHETHQ_DB_HOST} -p ${CACHETHQ_DB_PORT} -U ${CACHETHQ_DB_USERNAME} -d ${CACHETHQ_DB_DATABASE} -c "SELECT to_regclass('${CACHETHQ_DB_PREFIX}${table}');" | grep -c "${CACHETHQ_DB_PREFIX}${table}")" -eq 1 ]]; then
        echo "Table ${CACHETHQ_DB_PREFIX}${table} exists! ..."
    else
        echo "Table ${CACHETHQ_DB_PREFIX}${table} does not exist! ..."
        init_db
    fi

}

check_configured() {
  case "${CACHETHQ_DB_DRIVER}" in
    mysql)
      checkdbinitmysql
      ;;
    pgsql)
      checkdbinitpsql
      ;;
  esac
}

initialize_system() {
  echo "Initializing Cachet container ..."

  CACHETHQ_APP_KEY=${CACHETHQ_APP_KEY:-null}
  CACHETHQ_APP_ENV=${CACHETHQ_APP_ENV:-development}
  CACHETHQ_APP_DEBUG=${CACHETHQ_APP_DEBUG:-true}
  CACHETHQ_APP_URL=${CACHETHQ_APP_URL:-http://localhost}

  CACHETHQ_DB_DRIVER=${CACHETHQ_DB_DRIVER:-pgsql}
  CACHETHQ_DB_HOST=${CACHETHQ_DB_HOST:-postgres}
  CACHETHQ_DB_DATABASE=${CACHETHQ_DB_DATABASE:-cachet}
  CACHETHQ_DB_PREFIX=${CACHETHQ_DB_PREFIX}
  CACHETHQ_DB_USERNAME=${CACHETHQ_DB_USERNAME:-postgres}
  CACHETHQ_DB_PASSWORD=${CACHETHQ_DB_PASSWORD:-postgres}

  if [[ "${CACHETHQ_DB_DRIVER}" = "pgsql" ]]; then
    CACHETHQ_DB_PORT=${CACHETHQ_DB_PORT:-5432}
  fi

  if [[ "${CACHETHQ_DB_DRIVER}" = "mysql" ]]; then
    CACHETHQ_DB_PORT=${CACHETHQ_DB_PORT:-3306}
  fi

  CACHETHQ_DB_PORT=${CACHETHQ_DB_PORT}

  CACHETHQ_CACHE_DRIVER=${CACHETHQ_CACHE_DRIVER:-apc}
  CACHETHQ_SESSION_DRIVER=${CACHETHQ_SESSION_DRIVER:-cookie}
  CACHETHQ_SESSION_DOMAIN=${CACHETHQ_SESSION_DOMAIN:-null}
  CACHETHQ_QUEUE_DRIVER=${CACHETHQ_QUEUE_DRIVER:-database}
  CACHETHQ_CACHET_EMOJI=${CACHETHQ_CACHET_EMOJI:-false}
  CACHETHQ_CACHET_BEACON=${CACHETHQ_CACHET_BEACON:-true}
  CACHETHQ_CACHET_AUTO_TWITTER=${CACHETHQ_CACHET_AUTO_TWITTER:-true}

  CACHETHQ_MAIL_DRIVER=${CACHETHQ_MAIL_DRIVER:-smtp}
  CACHETHQ_MAIL_HOST=${CACHETHQ_MAIL_HOST:-localhost}
  CACHETHQ_MAIL_PORT=${CACHETHQ_MAIL_PORT:-25}
  CACHETHQ_MAIL_USERNAME=${CACHETHQ_MAIL_USERNAME:-null}
  CACHETHQ_MAIL_PASSWORD=${CACHETHQ_MAIL_PASSWORD:-null}
  CACHETHQ_MAIL_ADDRESS=${CACHETHQ_MAIL_ADDRESS:-null}
  CACHETHQ_MAIL_NAME=${CACHETHQ_MAIL_NAME:-null}
  CACHETHQ_MAIL_ENCRYPTION=${CACHETHQ_MAIL_ENCRYPTION:-null}

  CACHETHQ_REDIS_HOST=${CACHETHQ_REDIS_HOST:-null}
  CACHETHQ_REDIS_DATABASE=${CACHETHQ_REDIS_DATABASE:-null}
  CACHETHQ_REDIS_PORT=${CACHETHQ_REDIS_PORT:-null}
  CACHETHQ_REDIS_PASSWORD=${CACHETHQ_REDIS_PASSWORD:-null}

  CACHETHQ_GITHUB_TOKEN=${CACHETHQ_GITHUB_TOKEN:-null}

  CACHETHQ_NEXMO_KEY=${CACHETHQ_NEXMO_KEY:-null}
  CACHETHQ_NEXMO_SECRET=${CACHETHQ_NEXMO_SECRET:-null}
  CACHETHQ_NEXMO_SMS_FROM=${CACHETHQ_NEXMO_SMS_FROM:-Cachet}

  CACHETHQ_GOOGLE_CLIENT_ID=${CACHETHQ_GOOGLE_CLIENT_ID:-null}
  CACHETHQ_GOOGLE_CLIENT_SECRET=${CACHETHQ_GOOGLE_CLIENT_SECRET:-null}
  CACHETHQ_GOOGLE_REDIRECT_URL=${CACHETHQ_GOOGLE_REDIRECT_URL:-null}
  CACHETHQ_GOOGLE_ENABLED_DOMAIN=${CACHETHQ_GOOGLE_ENABLED_DOMAIN:-null}


  CACHETHQ_PHP_MAX_CHILDREN=${CACHETHQ_PHP_MAX_CHILDREN:-5}

  # configure env file
  if [[ "${CACHETHQ_APP_KEY}" == null ]]; then
    keygen="$(sudo php artisan key:generate)"
    echo "${keygen}"
    appkey=$(echo ${keygen} | grep -oP '(?<=\[).*(?=\])')
    #echo "Please set ${appkey} as your APP_KEY variable in the environment or docker-compose.yml and re-launch"
    #exit 1
    CACHETHQ_APP_KEY=$(echo ${keygen} | cut -d' ' -f3 | sed 's/\[//g' | sed 's/\]//g')
    echo "Setting APP_KEY to ${CACHETHQ_APP_KEY}"
  fi

  sed 's,{{APP_KEY}},'${CACHETHQ_APP_KEY}',g' -i /var/www/html/.env

  sed 's,{{APP_ENV}},'"${CACHETHQ_APP_ENV}"',g' -i /var/www/html/.env
  sed 's,{{APP_DEBUG}},'"${CACHETHQ_APP_DEBUG}"',g' -i /var/www/html/.env
  sed 's,{{APP_URL}},'"${CACHETHQ_APP_URL}"',g' -i /var/www/html/.env

  sed 's,{{DB_DRIVER}},'"${CACHETHQ_DB_DRIVER}"',g' -i /var/www/html/.env
  sed 's,{{DB_HOST}},'"${CACHETHQ_DB_HOST}"',g' -i /var/www/html/.env
  sed 's,{{DB_DATABASE}},'"${CACHETHQ_DB_DATABASE}"',g' -i /var/www/html/.env
  sed 's,{{DB_PREFIX}},'"${CACHETHQ_DB_PREFIX}"',g' -i /var/www/html/.env
  sed 's,{{DB_USERNAME}},'"${CACHETHQ_DB_USERNAME}"',g' -i /var/www/html/.env
  sed 's,{{DB_PASSWORD}},'"${CACHETHQ_DB_PASSWORD}"',g' -i /var/www/html/.env
  sed 's,{{DB_PORT}},'"${CACHETHQ_DB_PORT}"',g' -i /var/www/html/.env

  sed 's,{{CACHE_DRIVER}},'"${CACHETHQ_CACHE_DRIVER}"',g' -i /var/www/html/.env
  sed 's,{{SESSION_DRIVER}},'"${CACHETHQ_SESSION_DRIVER}"',g' -i /var/www/html/.env
  sed 's,{{SESSION_DOMAIN}},'"${CACHETHQ_SESSION_DOMAIN}"',g' -i /var/www/html/.env
  sed 's,{{QUEUE_DRIVER}},'"${CACHETHQ_QUEUE_DRIVER}"',g' -i /var/www/html/.env
  sed 's,{{CACHET_EMOJI}},'"${CACHETHQ_CACHET_EMOJI}"',g' -i /var/www/html/.env
  sed 's,{{CACHET_BEACON}},'"${CACHETHQ_CACHET_BEACON}"',g' -i /var/www/html/.env
  sed 's,{{CACHET_AUTO_TWITTER}},'"${CACHETHQ_CACHET_AUTO_TWITTER}"',g' -i /var/www/html/.env

  sed 's,{{MAIL_DRIVER}},'"${CACHETHQ_MAIL_DRIVER}"',g' -i /var/www/html/.env
  sed 's,{{MAIL_HOST}},'"${CACHETHQ_MAIL_HOST}"',g' -i /var/www/html/.env
  sed 's,{{MAIL_PORT}},'"${CACHETHQ_MAIL_PORT}"',g' -i /var/www/html/.env
  sed 's,{{MAIL_USERNAME}},'"${CACHETHQ_MAIL_USERNAME}"',g' -i /var/www/html/.env
  sed 's,{{MAIL_PASSWORD}},'"${CACHETHQ_MAIL_PASSWORD}"',g' -i /var/www/html/.env
  sed 's,{{MAIL_ADDRESS}},'"${CACHETHQ_MAIL_ADDRESS}"',g' -i /var/www/html/.env
  sed 's,{{MAIL_NAME}},'"${CACHETHQ_MAIL_NAME}"',g' -i /var/www/html/.env
  sed 's,{{MAIL_ENCRYPTION}},'"${CACHETHQ_MAIL_ENCRYPTION}"',g' -i /var/www/html/.env

  sed 's,{{REDIS_HOST}},'"${CACHETHQ_REDIS_HOST}"',g' -i /var/www/html/.env
  sed 's,{{REDIS_DATABASE}},'"${CACHETHQ_REDIS_DATABASE}"',g' -i /var/www/html/.env
  sed 's,{{REDIS_PORT}},'"${CACHETHQ_REDIS_PORT}"',g' -i /var/www/html/.env
  sed 's,{{REDIS_PASSWORD}},'"${CACHETHQ_REDIS_PASSWORD}"',g' -i /var/www/html/.env

  sed 's,{{GITHUB_TOKEN}},'"${CACHETHQ_GITHUB_TOKEN}"',g' -i /var/www/html/.env

  sed 's,{{NEXMO_KEY}},'"${CACHETHQ_NEXMO_KEY}"',g' -i /var/www/html/.env
  sed 's,{{NEXMO_SECRET}},'"${CACHETHQ_NEXMO_SECRET}"',g' -i /var/www/html/.env
  sed 's,{{NEXMO_SMS_FROM}},'"${CACHETHQ_NEXMO_SMS_FROM}"',g' -i /var/www/html/.env

  sed 's,{{GOOGLE_CLIENT_ID}},'"$CACHETHQ_GOOGLE_CLIENT_ID"',g' -i /var/www/html/.env
  sed 's,{{GOOGLE_CLIENT_SECRET}},'"${CACHETHQ_GOOGLE_CLIENT_SECRET}"',g' -i /var/www/html/.env
  sed 's,{{GOOGLE_REDIRECT_URL}},'"${CACHETHQ_GOOGLE_REDIRECT_URL}"',g' -i /var/www/html/.env
  sed 's,{{GOOGLE_ENABLED_DOMAIN}},'"${CACHETHQ_GOOGLE_ENABLED_DOMAIN}"',g' -i /var/www/html/.env

  sudo sed 's,{{PHP_MAX_CHILDREN}},'"${CACHETHQ_PHP_MAX_CHILDREN}"',g' -i /etc/php7/php-fpm.d/www.conf
  sudo sed 's,{{DB_DRIVER}},'"${CACHETHQ_DB_DRIVER}"',g' -i /etc/php7/php-fpm.d/www.conf
  sudo sed 's,{{DB_HOST}},'"${CACHETHQ_DB_HOST}"',g' -i /etc/php7/php-fpm.d/www.conf
  sudo sed 's,{{DB_DATABASE}},'"${CACHETHQ_DB_DATABASE}"',g' -i /etc/php7/php-fpm.d/www.conf
  sudo sed 's,{{DB_PREFIX}},'"${CACHETHQ_DB_PREFIX}"',g' -i /etc/php7/php-fpm.d/www.conf
  sudo sed 's,{{DB_USERNAME}},'"${CACHETHQ_DB_USERNAME}"',g' -i /etc/php7/php-fpm.d/www.conf
  sudo sed 's,{{DB_PASSWORD}},'"${CACHETHQ_DB_PASSWORD}"',g' -i /etc/php7/php-fpm.d/www.conf
  sudo sed 's,{{DB_PORT}},'"${CACHETHQ_DB_PORT}"',g' -i /etc/php7/php-fpm.d/www.conf
  sudo sed 's,{{CACHE_DRIVER}},'"${CACHETHQ_CACHE_DRIVER}"',g' -i /etc/php7/php-fpm.d/www.conf

  #sed 's,",,g' -i /var/www/html/.env

  #cat /etc/php7/php-fpm.d/www.conf
  #cat /var/www/html/.env

  rm -rf bootstrap/cache/*
  chmod -R 777 storage
  chmod -R 777 /var/www
  #chmod -R 777 /tmp
  sudo mkdir -p /var/lib/php/session
  sudo chmod -R 777 /var/lib/php/session
  sudo chmod 777 /dev/urandom

}

init_db() {
  echo "Initializing Cachet database ..."
  php artisan app:install
  check_configured
}

start_system() {
  initialize_system
  check_database_connection
  check_configured
  echo "Starting Cachet! ..."
  php artisan config:cache
  /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
}

start_system

exit 0
