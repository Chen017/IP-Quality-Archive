#!/usr/bin/env bash
# DB-IP function snapshot from xykt/IPQuality main, fetched 2026-10-18.
# Used only with mocked curl; never source or run the upstream entry point.
db_dbip(){
local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}DB-IP $Font_Suffix"
((ibar_step+=3))
show_progress_bar "$temp_info" $((40-6-${sinfo[ldatabase]}))&
bar_pid="$!"&&disown "$bar_pid"
trap "kill_progress_bar" RETURN
dbip=()
local tmpcurlarg="$CurlARG"
if [[ $IP == *:* ]];then
tmpcurlarg=""
fi
local RESPONSE=$(curl $tmpcurlarg -sL -m 10 -H 'accept: */*' -H 'accept-language: en-US,en;q=0.9' -H 'content-type: text/html;charset=UTF-8' -H 'dnt: 1' -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36' "https://db-ip.com/api/core/")
local tmpurl=$(echo "$RESPONSE"|sed -n 's/.*data-api-key="\([^"]*\)".*/\1/p'|head -n 1)
RESPONSE=$(curl $tmpcurlarg -sL -m 10 -H 'accept: */*' -H 'accept-language: en-US,en;q=0.9' -H 'content-type: text/plain;charset=UTF-8' -H 'dnt: 1' -H 'origin: https://db-ip.com' -H 'priority: u=1, i' -H 'referer: https://db-ip.com/' -H 'sec-ch-ua: "Not=A?Brand";v="99", "Google Chrome";v="151", "Chromium";v="151"' -H 'sec-ch-ua-mobile: ?0' -H 'sec-ch-ua-platform: "Windows"' -H 'sec-fetch-dest: empty' -H 'sec-fetch-mode: cors' -H 'sec-fetch-site: same-site' -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36' --data-raw '[["11.49","EUR"],["139.90","EUR"],["699.90","EUR"]]' "https://api.db-ip.com/v2/$tmpurl/self?convertCurrencies")
echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
dbip[robot]=$(echo "$RESPONSE"|jq -r '.isCrawler')
dbip[proxy]=$(echo "$RESPONSE"|jq -r '.isProxy')
dbip[risktext]=$(echo "$RESPONSE"|jq -r '.threatLevel')
dbip[countrycode]=$(echo "$RESPONSE"|jq -r '.countryCode')
shopt -s nocasematch
case ${dbip[risktext]} in
"low")dbip[risk]="${sscore[low]}"
dbip[score]=0
;;
"medium")dbip[risk]="${sscore[medium]}"
dbip[score]=50
;;
"high")dbip[risk]="${sscore[high]}"
dbip[score]=100
esac
shopt -u nocasematch
}
