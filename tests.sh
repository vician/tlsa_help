#!/bin/bash

PROTOCOL="tcp"
TEST="./tlsa_help.sh"

domains=("www.nic.cz:443" "www.cesnet.cz:443" "caletka.cz:443" "mail.cesnet.cz:25" "mail.nic.cz:25" "flexi.oskarcz.net:25" "www.vician.cz:443")

for domain_port in ${domains[@]}; do
    echo "---------------------------"
    domain="${domain_port%:*}"
    port="${domain_port#*:}"
    echo "- $domain : $port"
    
    tlsa=($( dig +short  _${port}._${PROTOCOL}.$domain TLSA ))
    if [ $? -ne 0 ]; then
        echo "ERROR: Cannot get TLSA for $domain:$port"
        continue
    fi

    if [ "${tlsa[0]}" != "0" ] && [ "${tlsa[0]}" != "1" ] && [ "${tlsa[0]}" != "2" ] && [ "${tlsa[0]}" != "3" ]; then
        tlsa=("${tlsa[@]:1}")
        echo "Cannot test it, skiping"
        #continue
    fi

    #echo "${tlsa[*]}"

    usage=${tlsa[0]}
    selector=${tlsa[1]}
    matching=${tlsa[2]}
    data=${tlsa[3]}${tlsa[4]}


    echo "Got: $usage | $selector | $matching | $data"

    index=""
    if [ "$usage" = "0" ] || [ "$usage" = "2" ]; then
        #echo "using index"
        index="-i 2"
    fi

    #$TEST -u $usage -s $selector -m $matching $index $domain $port | awk '{print $1}' | awk '{print toupper($0)}'
    computed=$($TEST -u $usage -s $selector -m $matching -f -x $domain $index $domain $port | awk '{print $1}' | awk '{print toupper($0)}' )
    if [ $? -ne 0 ]; then
        echo "ERROR: Test failed, cannot compute TLSA"
        continue
    fi
    #echo "Computed: $computed"

    diff <(echo "$data") <(echo "$computed")
    if [ $? -ne 0 ]; then
        #echo "Cmp: $usage | $selector | $matching | $computed"
        echo "ERROR: TLSA aren't the same!"
        continue
    fi
    echo "OK"
done
