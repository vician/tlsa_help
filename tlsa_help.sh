#!/bin/bash

### CONSTANTS ###
DEBUG=1
CHOSE_FIRST_MX=0
DNS_SERVER="@8.8.8.8"

### VARIABLES ###
USAGE=2
SELECTOR=1
MATCHING=1
DOMAIN=""
TARGET_SERVER=""
PORT=""
HASH_FUNCTION=""
SELECTOR_FUNCTION=""
SHOW_CERTIFICATES=0

function help {
    cat << EndOfHelp
Usage: $0 -u {0,1,2,3} -s {0,1} -m {0,1,2} domain port
    port: 443
          25
    -x TARGET_SERVER

EndOfHelp

    exit 0
}

function debug {
    if [ $DEBUG -ne 1 ]; then
        return 0
    fi
    echo "DEBUG: $*"
}

function select_mx {
    if [ "$PORT" != "25" ]; then
        TARGET_SERVER="$DOMAIN"
        return 0
    fi
    debug "Domain: $DOMAIN"
    if [ -n "$TARGET_SERVER" ]; then
        debug "Selected $TARGET_SERVER for testing"
        return 0
    fi

    mxs=( $(dig +short $DOMAIN MX | awk '{print $2}') )
    if [ $? -ne 0 ]; then
        echo "ERROR: Cannot load MX records for $DOMAIN."
        echo "TIP: You can use constant DEBUG_MX_SERVER for bypassing it"
        exit 1
    fi

    echo "found ${#mxs[@]} mx records for domain $DOMAIN: "

    i=0
    for mx in ${mxs[@]}; do
        echo -e "$i: ${mx::-1}"
        let i++
    done

    if [ $CHOSE_FIRST_MX -eq 1 ]; then
        selected=0 # Chose the first server
    else
        mx_count=${#mxs[@]}
        mx_count=$((mx_count - 1))
        echo "Select mail server for getting certificate [0-$mx_count]"
        read selected
    fi

    echo "You selected: $selected = ${mxs[$selected]}"

    TARGET_SERVER="${mxs[$selected]}"
}

function port_fix {
    if [ "$PORT" = "smtp" ] || [ "$PORT" = "25" ]; then
        PORT="25 -starttls smtp"
    fi

}

function which_hash {
    if [ "$MATCHING" = 0 ]; then
        HASH_FUNCTION="cat"
    elif [ "$MATCHING" = 1 ]; then
        HASH_FUNCTION="sha256sum"
    elif [ "$MATCHING" = 2 ]; then
        HASH_FUNCTION="sha512sum"
    else
        echo "ERROR: Unknow hashing function"
        exit 1
    fi
}

function which_selector {
    if [ "$SELECTOR" = 0 ]; then
        SELECTOR_FUNCTION="cat"
        DER_FUNCTION="openssl x509 -outform der"
    elif [ "$SELECTOR" = 1 ]; then
        #SELECTOR_FUNCTION="openssl rsa -pubin -outform der"
        SELECTOR_FUNCTION="openssl x509 -pubkey -noout"
        DER_FUNCTION="openssl rsa -pubin -outform der"
    fi
}

function get_end_certificate {
    port_fix
    which_hash
    which_selector

    openssl s_client -showcerts -connect $TARGET_SERVER:$PORT < /dev/null 2>/dev/null | $SELECTOR_FUNCTION | openssl x509 -outform der | $HASH_FUNCTION
}

function get_ca_certificate {

    port_fix

    openssl s_client -showcerts -connect $TARGET_SERVER:$PORT < /dev/null 2>/dev/null | grep 'CN' | grep 's:'

    echo ${certs}

    #echo "loaded `echo -e ${certs} | wc -l` for $DOMAIN:$PORT"

}

function get_certificate {
    debug "MAIL: $TARGET_SERVER HASH: $HASH_FUNCTION, SELECTOR: $SELECTOR_FUNCTION, DER: $DER_FUNCTION"


    if [ "$USAGE" = 3 ] || [ "$USAGE" = 1 ]; then
        nth=1
    else
        echo "Found these certificates"
        openssl s_client -showcerts -connect $TARGET_SERVER:$PORT < /dev/null 2>/dev/null | grep 'CN' | grep 's:'
        echo "Select the certificate [0-N]"
        read nth

        if [ "$nth" = 0 ]; then
            echo "WARNING: You chose end certificate, but selector was set to use Authority"
        fi
        let nth++
    fi
    #nth=1

    #openssl s_client -showcerts -connect $TARGET_SERVER:$PORT < /dev/null 2>/dev/null 
    #echo "==========================="
    [ $SHOW_CERTIFICATES -eq 1 ] && openssl s_client -showcerts -connect $TARGET_SERVER:$PORT < /dev/null 2>/dev/null | sed -nr "/-BEGIN CERTIFICATE/H;//,/-END CERTIFICATE-/G;s/\n(\n[^\n]*){$nth}$//p"
    
    # Print the certificate
    #openssl s_client -showcerts -connect $TARGET_SERVER:$PORT < /dev/null 2>/dev/null | sed -nr "/-BEGIN CERTIFICATE/H;//,/-END CERTIFICATE-/G;s/\n(\n[^\n]*){$nth}$//p"
    # Convert the certificate
    [ $SHOW_CERTIFICATES -eq 1 ] && openssl s_client -showcerts -connect $TARGET_SERVER:$PORT < /dev/null 2>/dev/null | sed -nr "/-BEGIN CERTIFICATE/H;//,/-END CERTIFICATE-/G;s/\n(\n[^\n]*){$nth}$//p" | $SELECTOR_FUNCTION
    openssl s_client -showcerts -connect $TARGET_SERVER:$PORT < /dev/null 2>/dev/null | sed -nr "/-BEGIN CERTIFICATE/H;//,/-END CERTIFICATE-/G;s/\n(\n[^\n]*){$nth}$//p" | $SELECTOR_FUNCTION | $DER_FUNCTION | $HASH_FUNCTION
   
}

OPTIND=1
while getopts 'u:s:m:hdn:x:c' opt; do
  case "$opt" in
    u)
      USAGE=$OPTARG ;;
    d)
      DEBUG=1
      debug "run: $0 $*"
      ;;
    s)
      SELECTOR=$OPTARG ;;
    m)
      MATCHING=$OPTARG ;;
    h)
      help ;;
    n)
      DNS_SERVER="$OPTARG";;
    x)
      TARGET_SERVER="$OPTARG";;
    c)
      SHOW_CERTIFICATES=1;;
    ?)
      echo "ERROR: Wrong arguments";;
  esac
done

debug "Usage: $USAGE, Selector: $SELECTOR, Matching: $MATCHING"

shift $(($OPTIND - 1)) # move to first non-option params

DOMAIN=$1
PORT=$2

if [ -z "$DOMAIN" ] || [ -z "$PORT" ]; then
    echo "ERROR: Wrong usage, please read help!"
    echo "TIP: Read help by runing $0 -h"
    exit 1
fi

select_mx

port_fix
which_hash
which_selector
get_certificate
