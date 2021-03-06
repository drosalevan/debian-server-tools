#!/bin/bash
#
# Can-send-email triggers and checks.
#
# VERSION       :1.2.5
# DATE          :2015-08-01
# AUTHOR        :Viktor Szépe <viktor@szepe.net>
# URL           :https://github.com/szepeviktor/debian-server-tools
# LICENSE       :The MIT License (MIT)
# BASH-VERSION  :4.2+
# DEPENDS       :/usr/local/bin/txtlocal.py
# DEPENDS       :apt-get install mailx
# LOCATION      :/usr/local/sbin/can-send-email.sh
# CRON.D        :40 */6	* * *	daemon	/usr/local/sbin/can-send-email.sh trigger
# CRON.D        :50 *	* * *	daemon	/usr/local/sbin/can-send-email.sh check

# Adjust these variables.
#
ALERT_MOBILE=""
ALERT_ADDRESS="viktor@szepe.net"
CSE_ADDRESS="cse@worker.szepe.net"
WORK_DIR="/var/lib/can-send-email"
# 6 hours in seconds
FAILURE_INTERVAL="$((6 * 3600))"

HTTP_USER_AGENT="Can-send-email/1.1.0 (bash; Linux)"
# In UTC
NOW="$(date "+%s")"

# stderr goes to SMTP
Error() {
    local RET="$1"

    shift
    echo "ERROR: $*" 1>&2
    exit "$RET"
}

Sql() {
    sqlite3 -batch -init <(echo ".timeout 1000") "${WORK_DIR}/cse.sqlite3" "$(printf "$@")"
}

Init() {
    install -v -D \
        --owner="daemon" --group="daemon" --mode "600" \
        --target-directory "$WORK_DIR" ./cse.sqlite3
    Sql 'CREATE TABLE host ( "id" INTEGER PRIMARY KEY, "hostname" TEXT, "url" TEXT, "last" DATETIME );' \
        && echo "OK."
}

Is_host() {
    local HOSTNAME="$1"

    Sql 'SELECT "id" FROM host WHERE "hostname" = "%s";' \
        "$HOSTNAME"
}

Add_host() {
    local HOSTNAME="$1"
    local URL="$2"

    if [ -z "$HOSTNAME" ] || [ -z "$URL" ]; then
        Error 3 "Usage: $0 add SERVERNAME URL"
    fi
    if [ -n "$(Is_host "$HOSTNAME")" ]; then
        Error 4 "Host already exists!"
    fi

    Sql 'REPLACE INTO host ( "hostname", "url", "last" ) VALUES ( "%s", "%s", "%s" );' \
        "$HOSTNAME" "$URL" "$NOW"
}

Remove_host() {
    local HOSTNAME="$1"

    if [ -z "$HOSTNAME" ]; then
        Error 5 "Usage: $0 remove HOSTNAME"
    fi
    if [ -z "$(Is_host "$HOSTNAME")" ]; then
        Error 6 "Host does not exist!"
    fi

    Sql 'DELETE FROM host WHERE "hostname" = "%s";' \
        "$HOSTNAME"
}

List_hosts() {
    Sql 'SELECT "hostname", "url", "last" FROM host;'
}

Update_last() {
    local HOSTNAME="$1"
    local LAST="$2"

    if [ -z "$(Is_host "$HOSTNAME")" ]; then
        logger -t "can-send-email" "Host not found '${HOSTNAME}'"
        echo "501 Syntax error in parameters or arguments"
        return
    fi

    if Sql 'UPDATE host SET "last" = "%s" WHERE "hostname" = "%s";' "$LAST" "$HOSTNAME"; then
        logger -t "can-send-email" "Updated: '${HOSTNAME}' @${LAST}"
    else
        logger -t "can-send-email" "Update failed ($?) for host: '${HOSTNAME}'"
    fi
}

# pipe: list of URL-s
Trigger() {
    while read URL; do
        case "${URL:0:4}" in
            "http")
                wget -q -O- --max-redirect=0 --tries=1 --timeout=5 --user-agent="$HTTP_USER_AGENT" "$URL" \
                    || echo "Trigger failed ($?) for ${URL}"
                ;;
            "mail")
                RECIPIENT="${URL#mailto:}"
                # Hack to pass from address to sendmail
                #     mailx -- RECIPIENT -fSENDER
                echo -e "Ennek az üzenetnek vissza kéne pattannia.\nThis message should bounce back.\n" \
                    | mailx -s "[cse] bounce message / Email kézbesítés monitorozás" \
                    -S "from=${CSE_ADDRESS}" -- "$RECIPIENT" "-f${CSE_ADDRESS}" \
                    || echo "Trigger failed ($?) for ${URL}"
                ;;
        esac
    done
}

Get_urls() {
    Sql 'SELECT "url" FROM host;'
}

Get_failures() {
    Sql 'SELECT "hostname" FROM host WHERE "last" < ( "%s" - "%s" );' \
        "$NOW" "$FAILURE_INTERVAL"
}

Help() {
cat <<EOF
Usage: $0 COMMAND [ARGUMENT]

Can-send-email triggers and checks in one.

Commands:
    init                  Initialize database
    list                  List host names, URL-s and last successful update timestamps
    add HOSTNAME URL      Add a new host
    remove HOSTNAME       Remove a host
    trigger               Trigger email sending for all hosts
    trigger-url URL       Trigger email sending for a host
    check                 Check last update timestamp
    force-update          Update a host manually
    syslog                Watch syslog for can-send-email messages
    help                  display this help message

Without parameters receive message source from stdin.
EOF
}

case "$1" in
    # Initialize
    help)
        Help
        ;;

    # Initialize
    init)
        Init
        ;;

    # List hosts
    list)
        List_hosts
        ;;

    # Add new host
    add)
        shift
        Add_host "$@"
        ;;

    # Remove host
    remove|delete|del)
        shift
        Remove_host "$@"
        ;;

    # Trigger emails cron job
    trigger)
        Get_urls | Trigger 1>&2
        ;;

    # Trigger emails cron job
    trigger-url|triggerurl)
        echo "$2" | Trigger 1>&2
        ;;

    # Check failures cron job
    check)
        FAILURES="$(Get_failures)"
        if [ -n "$FAILURES" ]; then
            # 1. SMS
            SMSOK="$(/usr/local/bin/txtlocal.py "$ALERT_MOBILE" "Can-send-email failures: ${FAILURES}")"
            RET="$?"
            [ "$SMSOK" == "OK" ] || echo "SMS failure: ${RET}, ${SMSOK}" >&2
            # 2. E-mail
            echo "Failures: ${FAILURES}" | mailx -s "Can-send-email failure" "$ALERT_ADDRESS"
            # 3. Syslog
            logger -t "can-send-email" "Can-send-email failures: ${FAILURES}"
            # 4. Cron job output
            Error 10 "Failures: ${FAILURES}"
        fi
        ;;

    # Update a host manually
    force-update)
        Update_last "$2" "$NOW"
        ;;

    # Watch syslog for can-send-email messages
    syslog)
        tail -n 100 -f /var/log/syslog | grep "can-send-email"
        ;;

    # Receive message
    "")
        MSG_TMP="$(tempfile -d "$WORK_DIR")"
        trap "rm '$MSG_TMP' &> /dev/null" EXIT

        cat > "$MSG_TMP"

        # From http:
        HOSTNAME="$(grep -m1 -x "X-Host: \S\+" "$MSG_TMP")"
        if grep -q "^Subject: \[cse\]" "$MSG_TMP" \
            && [ -n "$HOSTNAME" ]; then
            HOSTNAME="${HOSTNAME#X-Host: }"
            Update_last "$HOSTNAME" "$NOW"
            exit 0
        fi

        # Bounce message (DSN)
        HOSTNAME="$(grep -m1 -i '^From: \S\+' "$MSG_TMP" | sed 's/^From: .*@\([^>]\+\).*$/\1/I')"
        if grep -q "^Subject: \[cse\]" "$MSG_TMP" \
            && [ -n "$HOSTNAME" ] \
            && ( grep -q -i '^From: .*mailer-daemon' "$MSG_TMP" \
                || grep -q -i '^Subject: .*mail delivery' "$MSG_TMP" \
                || grep -q -i '^Content-Type: .*\(report\|delivery\|status\)' "$MSG_TMP" \
                || grep -q -i '^X-Failed-Recipients: \S\+' "$MSG_TMP" \
            ); then
            Update_last "$HOSTNAME" "$NOW"
            exit 0
        fi

        # Forwarded message back to CSE_ADDRESS
        HOSTNAME="$(grep -m1 -i "^To: -f${CSE_ADDRESS}" "$MSG_TMP" | sed "s/^To: -f${CSE_ADDRESS}, \(.*\)$/\1/I")"
        if grep -q "^Subject: \[cse\]" "$MSG_TMP" \
            && [ -n "$HOSTNAME" ] \
            && grep -q -i -x "From: ${CSE_ADDRESS}" "$MSG_TMP"; then
            Update_last "$HOSTNAME" "$NOW"
            exit 0
        fi

        # Invalid email or spam
        MSG_PATH="${WORK_DIR}/$(date --utc "+%Y%m%d-%H%M%S")_${RANDOM}.eml"
        cp "$MSG_TMP" "$MSG_PATH"
        echo -e "\nX-SMTP-Recipient: ${RECIPIENT}\nX-SMTP-Sender: ${SENDER}\n" >> "$MSG_PATH"
        logger -t "can-send-email" "Invalid email headers in ${MSG_PATH}"
        echo "501 Syntax error in parameters or arguments"
        ;;
esac
