#!/usr/bin/env bash
# Upstream score/query/display/JSON functions, snapshot fetched 2026-10-18.
# Source: xykt/IPQuality ip.sh blob 086792f3be803fa0b1c0af6eb9247207abb7e182.
# Offline fixture only: tests mock all network and unrelated report functions.

db_maxmind(){
local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}Maxmind $Font_Suffix"
((ibar_step+=3))
show_progress_bar "$temp_info" $((40-8-${sinfo[ldatabase]}))&
bar_pid="$!"&&disown "$bar_pid"
trap "kill_progress_bar" RETURN
maxmind=()
local RESPONSE=$(curl $CurlARG -Ls -$1 -m 10 "https://ipinfo.check.place/$IP?lang=$YY")
echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
if [[ -z $RESPONSE ]];then
mode_lite=1
else
mode_lite=0
fi
maxmind[asn]=$(echo "$RESPONSE"|jq -r '.ASN.AutonomousSystemNumber')
maxmind[org]=$(echo "$RESPONSE"|jq -r '.ASN.AutonomousSystemOrganization')
maxmind[city]=$(echo "$RESPONSE"|jq -r '.City.Name')
maxmind[post]=$(echo "$RESPONSE"|jq -r '.City.PostalCode')
maxmind[lat]=$(echo "$RESPONSE"|jq -r '.City.Latitude')
maxmind[lon]=$(echo "$RESPONSE"|jq -r '.City.Longitude')
maxmind[rad]=$(echo "$RESPONSE"|jq -r '.City.AccuracyRadius')
maxmind[continentcode]=$(echo "$RESPONSE"|jq -r '.City.Continent.Code')
maxmind[continent]=$(echo "$RESPONSE"|jq -r '.City.Continent.Name')
maxmind[citycountrycode]=$(echo "$RESPONSE"|jq -r '.City.Country.IsoCode')
maxmind[citycountry]=$(echo "$RESPONSE"|jq -r '.City.Country.Name')
maxmind[timezone]=$(echo "$RESPONSE"|jq -r '.City.Location.TimeZone')
maxmind[subcode]=$(echo "$RESPONSE"|jq -r 'if .City.Subdivisions | length > 0 then .City.Subdivisions[0].IsoCode else "N/A" end')
maxmind[sub]=$(echo "$RESPONSE"|jq -r 'if .City.Subdivisions | length > 0 then .City.Subdivisions[0].Name else "N/A" end')
maxmind[countrycode]=$(echo "$RESPONSE"|jq -r '.Country.IsoCode')
maxmind[country]=$(echo "$RESPONSE"|jq -r '.Country.Name')
maxmind[regcountrycode]=$(echo "$RESPONSE"|jq -r '.Country.RegisteredCountry.IsoCode')
maxmind[regcountry]=$(echo "$RESPONSE"|jq -r '.Country.RegisteredCountry.Name')
if [[ $YY != "en" ]];then
local backup_response=$(curl $CurlARG -s -$1 -m 10 "https://ipinfo.check.place/$IP?lang=en")
[[ ${maxmind[asn]} == "null" ]]&&maxmind[asn]=$(echo "$backup_response"|jq -r '.ASN.AutonomousSystemNumber')
[[ ${maxmind[org]} == "null" ]]&&maxmind[org]=$(echo "$backup_response"|jq -r '.ASN.AutonomousSystemOrganization')
[[ ${maxmind[city]} == "null" ]]&&maxmind[city]=$(echo "$backup_response"|jq -r '.City.Name')
[[ ${maxmind[post]} == "null" ]]&&maxmind[post]=$(echo "$backup_response"|jq -r '.City.PostalCode')
[[ ${maxmind[lat]} == "null" ]]&&maxmind[lat]=$(echo "$backup_response"|jq -r '.City.Latitude')
[[ ${maxmind[lon]} == "null" ]]&&maxmind[lon]=$(echo "$backup_response"|jq -r '.City.Longitude')
[[ ${maxmind[rad]} == "null" ]]&&maxmind[rad]=$(echo "$backup_response"|jq -r '.City.AccuracyRadius')
[[ ${maxmind[continentcode]} == "null" ]]&&maxmind[continentcode]=$(echo "$backup_response"|jq -r '.City.Continent.Code')
[[ ${maxmind[continent]} == "null" ]]&&maxmind[continent]=$(echo "$backup_response"|jq -r '.City.Continent.Name')
[[ ${maxmind[citycountrycode]} == "null" ]]&&maxmind[citycountrycode]=$(echo "$backup_response"|jq -r '.City.Country.IsoCode')
[[ ${maxmind[citycountry]} == "null" ]]&&maxmind[citycountry]=$(echo "$backup_response"|jq -r '.City.Country.Name')
[[ ${maxmind[timezone]} == "null" ]]&&maxmind[timezone]=$(echo "$backup_response"|jq -r '.City.Location.TimeZone')
[[ ${maxmind[subcode]} == "null" ]]&&maxmind[subcode]=$(echo "$backup_response"|jq -r 'if .City.Subdivisions | length > 0 then .City.Subdivisions[0].IsoCode else "N/A" end')
[[ ${maxmind[sub]} == "null" ]]&&maxmind[sub]=$(echo "$backup_response"|jq -r 'if .City.Subdivisions | length > 0 then .City.Subdivisions[0].Name else "N/A" end')
[[ ${maxmind[countrycode]} == "null" ]]&&maxmind[countrycode]=$(echo "$backup_response"|jq -r '.Country.IsoCode')
[[ ${maxmind[country]} == "null" ]]&&maxmind[country]=$(echo "$backup_response"|jq -r '.Country.Name')
[[ ${maxmind[regcountrycode]} == "null" ]]&&maxmind[regcountrycode]=$(echo "$backup_response"|jq -r '.Country.RegisteredCountry.IsoCode')
[[ ${maxmind[regcountry]} == "null" ]]&&maxmind[regcountry]=$(echo "$backup_response"|jq -r '.Country.RegisteredCountry.Name')
fi
if [[ ${maxmind[lat]} != "null" && ${maxmind[lon]} != "null" ]];then
maxmind[dms]=$(generate_dms "${maxmind[lat]}" "${maxmind[lon]}")
maxmind[map]=$(generate_googlemap_url "${maxmind[lat]}" "${maxmind[lon]}" "${maxmind[rad]}")
else
maxmind[dms]="null"
maxmind[map]="null"
fi
}

db_scamalytics(){
local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}Scamalytics $Font_Suffix"
((ibar_step+=3))
show_progress_bar "$temp_info" $((40-12-${sinfo[ldatabase]}))&
bar_pid="$!"&&disown "$bar_pid"
trap "kill_progress_bar" RETURN
scamalytics=()
local RESPONSE=$(curl $CurlARG -sL -$1 -m 10 "https://ipinfo.check.place/$IP?db=scamalytics")
echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
scamalytics[countrycode]=$(echo "$RESPONSE"|jq -r '.external_datasources.maxmind_geolite2.ip_country_code')
scamalytics[proxy]=$(echo "$RESPONSE"|jq -r '.external_datasources.firehol.is_proxy')
scamalytics[tor]=$(echo "$RESPONSE"|jq -r '.external_datasources.x4bnet.is_tor')
scamalytics[vpn]=$(echo "$RESPONSE"|jq -r '.scamalytics.scamalytics_proxy.is_vpn')
scamalytics[server]=$(echo "$RESPONSE"|jq -r '.scamalytics.scamalytics_proxy.is_datacenter')
scamalytics[abuser]=$(echo "$RESPONSE"|jq -r '.scamalytics.is_blacklisted_external')
scamalytics[robot1]=$(echo "$RESPONSE"|jq -r '.external_datasources.x4bnet.is_blacklisted_spambot')
scamalytics[robot2]=$(echo "$RESPONSE"|jq -r '.external_datasources.x4bnet.is_bot_operamini')
scamalytics[robot3]=$(echo "$RESPONSE"|jq -r '.external_datasources.x4bnet.is_bot_semrush')
[[ ${scamalytics[robot1]} == "true" || ${scamalytics[robot2]} == "true" || ${scamalytics[robot3]} == "true" ]]&&scamalytics[robot]="true"
[[ ${scamalytics[robot1]} == "false" && ${scamalytics[robot2]} == "false" && ${scamalytics[robot3]} == "false" ]]&&scamalytics[robot]="false"
scamalytics[score]=$(echo "$RESPONSE"|jq -r '.scamalytics.scamalytics_score')
if [[ ${scamalytics[score]} -lt 20 ]];then
scamalytics[risk]="${sscore[low]}"
elif [[ ${scamalytics[score]} -lt 60 ]];then
scamalytics[risk]="${sscore[medium]}"
elif [[ ${scamalytics[score]} -lt 90 ]];then
scamalytics[risk]="${sscore[high]}"
elif [[ ${scamalytics[score]} -ge 90 ]];then
scamalytics[risk]="${sscore[veryhigh]}"
fi
}

db_ipapi(){
local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}ipapi $Font_Suffix"
((ibar_step+=3))
show_progress_bar "$temp_info" $((40-6-${sinfo[ldatabase]}))&
bar_pid="$!"&&disown "$bar_pid"
trap "kill_progress_bar" RETURN
ipapi=()
local RESPONSE=$(curl $CurlARG -sL -$1 -m 10 "https://ipinfo.check.place/$IP?db=ipapi")
echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
[[ -z $RESPONSE ]]&&return 1
ipapi[usetype]=$(echo "$RESPONSE"|jq -r '.asn.type')
ipapi[comtype]=$(echo "$RESPONSE"|jq -r '.company.type')
shopt -s nocasematch
case ${ipapi[usetype]} in
"business")ipapi[susetype]="${stype[business]}"
;;
"isp")ipapi[susetype]="${stype[isp]}"
;;
"hosting")ipapi[susetype]="${stype[hosting]}"
;;
"education")ipapi[susetype]="${stype[education]}"
;;
"government")ipapi[susetype]="${stype[government]}"
;;
"banking")ipapi[susetype]="${stype[banking]}"
;;
*)ipapi[susetype]="${stype[other]}"
esac
case ${ipapi[comtype]} in
"business")ipapi[scomtype]="${stype[business]}"
;;
"isp")ipapi[scomtype]="${stype[isp]}"
;;
"hosting")ipapi[scomtype]="${stype[hosting]}"
;;
"education")ipapi[scomtype]="${stype[education]}"
;;
"government")ipapi[scomtype]="${stype[government]}"
;;
"banking")ipapi[scomtype]="${stype[banking]}"
;;
*)ipapi[scomtype]="${stype[other]}"
esac
ipapi[scoretext]=$(echo "$RESPONSE"|jq -r '.company.abuser_score')
ipapi[scorenum]=$(echo "${ipapi[scoretext]}"|awk '{print $1}')
ipapi[risktext]=$(echo "${ipapi[scoretext]}"|awk -F'[()]' '{print $2}')
[[ -n ${ipapi[scorenum]} ]]&&ipapi[score]=$(awk "BEGIN {printf \"%.2f%%\", ${ipapi[scorenum]} * 100}")
case ${ipapi[risktext]} in
"Very Low")ipapi[risk]="${sscore[verylow]}"
;;
"Low")ipapi[risk]="${sscore[low]}"
;;
"Elevated")ipapi[risk]="${sscore[elevated]}"
;;
"High")ipapi[risk]="${sscore[high]}"
;;
"Very High")ipapi[risk]="${sscore[veryhigh]}"
esac
shopt -u nocasematch
ipapi[countrycode]=$(echo "$RESPONSE"|jq -r '.location.country_code')
ipapi[proxy]=$(echo "$RESPONSE"|jq -r '.is_proxy')
ipapi[tor]=$(echo "$RESPONSE"|jq -r '.is_tor')
ipapi[vpn]=$(echo "$RESPONSE"|jq -r '.is_vpn')
ipapi[server]=$(echo "$RESPONSE"|jq -r '.is_datacenter')
ipapi[abuser]=$(echo "$RESPONSE"|jq -r '.is_abuser')
ipapi[robot]=$(echo "$RESPONSE"|jq -r '.is_crawler')
}

db_abuseipdb(){
local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}AbuseIPDB $Font_Suffix"
((ibar_step+=3))
show_progress_bar "$temp_info" $((40-10-${sinfo[ldatabase]}))&
bar_pid="$!"&&disown "$bar_pid"
trap "kill_progress_bar" RETURN
abuseipdb=()
local RESPONSE=$(curl $CurlARG -sL -$1 -m 10 "https://ipinfo.check.place/$IP?db=abuseipdb")
echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
abuseipdb[usetype]=$(echo "$RESPONSE"|jq -r '.data.usageType')
shopt -s nocasematch
case ${abuseipdb[usetype]} in
"Commercial")abuseipdb[susetype]="${stype[business]}"
;;
"Data Center/Web Hosting/Transit")abuseipdb[susetype]="${stype[hosting]}"
;;
"University/College/School")abuseipdb[susetype]="${stype[education]}"
;;
"Government")abuseipdb[susetype]="${stype[government]}"
;;
"banking")abuseipdb[susetype]="${stype[banking]}"
;;
"Organization")abuseipdb[susetype]="${stype[organization]}"
;;
"Military")abuseipdb[susetype]="${stype[military]}"
;;
"Library")abuseipdb[susetype]="${stype[library]}"
;;
"Content Delivery Network")abuseipdb[susetype]="${stype[cdn]}"
;;
"Fixed Line ISP")abuseipdb[susetype]="${stype[lineisp]}"
;;
"Mobile ISP")abuseipdb[susetype]="${stype[mobile]}"
;;
"Search Engine Spider")abuseipdb[susetype]="${stype[spider]}"
;;
"Reserved")abuseipdb[susetype]="${stype[reserved]}"
;;
*)abuseipdb[susetype]="${stype[other]}"
esac
shopt -u nocasematch
abuseipdb[score]=$(echo "$RESPONSE"|jq -r '.data.abuseConfidenceScore')
if [[ ${abuseipdb[score]} -lt 25 ]];then
abuseipdb[risk]="${sscore[low]}"
elif [[ ${abuseipdb[score]} -lt 75 ]];then
abuseipdb[risk]="${sscore[high]}"
elif [[ ${abuseipdb[score]} -ge 75 ]];then
abuseipdb[risk]="${sscore[dos]}"
fi
}

db_ip2location(){
local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}IP2LOCATION $Font_Suffix"
((ibar_step+=3))
show_progress_bar "$temp_info" $((40-12-${sinfo[ldatabase]}))&
bar_pid="$!"&&disown "$bar_pid"
trap "kill_progress_bar" RETURN
ip2location=()
local RESPONSE=$(curl $CurlARG -sL -$1 -m 10 "https://ipinfo.check.place/$IP?db=ip2location")
echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
ip2location[usetype]=$(echo "$RESPONSE"|jq -r '.usage_type')
ip2location[comtype]=$(echo "$RESPONSE"|jq -r '.as_info.as_usage_type')
shopt -s nocasematch
local first_use="${ip2location[usetype]%%/*}"
case $first_use in
"COM")ip2location[susetype]="${stype[business]}"
;;
"DCH")ip2location[susetype]="${stype[hosting]}"
;;
"EDU")ip2location[susetype]="${stype[education]}"
;;
"GOV")ip2location[susetype]="${stype[government]}"
;;
"ORG")ip2location[susetype]="${stype[organization]}"
;;
"MIL")ip2location[susetype]="${stype[military]}"
;;
"LIB")ip2location[susetype]="${stype[library]}"
;;
"CDN")ip2location[susetype]="${stype[cdn]}"
;;
"ISP")ip2location[susetype]="${stype[lineisp]}"
;;
"MOB")ip2location[susetype]="${stype[mobile]}"
;;
"SES")ip2location[susetype]="${stype[spider]}"
;;
"RSV")ip2location[susetype]="${stype[reserved]}"
;;
*)ip2location[susetype]="${stype[other]}"
esac
first_use="${ip2location[comtype]%%/*}"
case $first_use in
"COM")ip2location[scomtype]="${stype[business]}"
;;
"DCH")ip2location[scomtype]="${stype[hosting]}"
;;
"EDU")ip2location[scomtype]="${stype[education]}"
;;
"GOV")ip2location[scomtype]="${stype[government]}"
;;
"ORG")ip2location[scomtype]="${stype[organization]}"
;;
"MIL")ip2location[scomtype]="${stype[military]}"
;;
"LIB")ip2location[scomtype]="${stype[library]}"
;;
"CDN")ip2location[scomtype]="${stype[cdn]}"
;;
"ISP")ip2location[scomtype]="${stype[lineisp]}"
;;
"MOB")ip2location[scomtype]="${stype[mobile]}"
;;
"SES")ip2location[scomtype]="${stype[spider]}"
;;
"RSV")ip2location[scomtype]="${stype[reserved]}"
;;
*)ip2location[scomtype]="${stype[other]}"
esac
shopt -u nocasematch
ip2location[countrycode]=$(echo "$RESPONSE"|jq -r '.country_code')
ip2location[proxy0]=$(echo "$RESPONSE"|jq -r '.is_proxy')
ip2location[proxy1]=$(echo "$RESPONSE"|jq -r '.proxy.is_public_proxy')
ip2location[proxy2]=$(echo "$RESPONSE"|jq -r '.proxy.is_web_proxy')
[[ ${ip2location[proxy0]} == "true" || ${ip2location[proxy1]} == "true" || ${ip2location[proxy2]} == "true" ]]&&ip2location[proxy]="true"
[[ ${ip2location[proxy0]} == "false" && ${ip2location[proxy1]} == "false" && ${ip2location[proxy2]} == "false" ]]&&ip2location[proxy]="false"
ip2location[tor]=$(echo "$RESPONSE"|jq -r '.proxy.is_tor')
ip2location[vpn]=$(echo "$RESPONSE"|jq -r '.proxy.is_vpn')
ip2location[server]=$(echo "$RESPONSE"|jq -r '.proxy.is_data_center')
ip2location[abuser]=$(echo "$RESPONSE"|jq -r '.proxy.is_spammer')
ip2location[robot1]=$(echo "$RESPONSE"|jq -r '.proxy.is_web_crawler')
ip2location[robot2]=$(echo "$RESPONSE"|jq -r '.proxy.is_scanner')
ip2location[robot3]=$(echo "$RESPONSE"|jq -r '.proxy.is_botnet')
[[ ${ip2location[robot1]} == "true" || ${ip2location[robot2]} == "true" || ${ip2location[robot3]} == "true" ]]&&ip2location[robot]="true"
[[ ${ip2location[robot1]} == "false" && ${ip2location[robot2]} == "false" && ${ip2location[robot3]} == "false" ]]&&ip2location[robot]="false"
ip2location[score]=$(echo "$RESPONSE"|jq -r '.fraud_score')
if [[ ${ip2location[score]} -lt 33 ]];then
ip2location[risk]="${sscore[low]}"
elif [[ ${ip2location[score]} -lt 66 ]];then
ip2location[risk]="${sscore[medium]}"
elif [[ ${ip2location[score]} -ge 66 ]];then
ip2location[risk]="${sscore[high]}"
fi
}

db_ipqs(){
local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}IPQS $Font_Suffix"
((ibar_step+=3))
show_progress_bar "$temp_info" $((40-5-${sinfo[ldatabase]}))&
bar_pid="$!"&&disown "$bar_pid"
trap "kill_progress_bar" RETURN
ipqs=()
local RESPONSE=$(curl $CurlARG -sL -$1 -m 10 "https://ipinfo.check.place/$IP?db=ipqualityscore")
echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
ipqs[score]=$(echo "$RESPONSE"|jq -r '.fraud_score')
if [[ ${ipqs[score]} -lt 75 ]];then
ipqs[risk]="${sscore[low]}"
elif [[ ${ipqs[score]} -lt 85 ]];then
ipqs[risk]="${sscore[suspicious]}"
elif [[ ${ipqs[score]} -lt 90 ]];then
ipqs[risk]="${sscore[risky]}"
elif [[ ${ipqs[score]} -ge 90 ]];then
ipqs[risk]="${sscore[highrisk]}"
fi
ipqs[countrycode]=$(echo "$RESPONSE"|jq -r '.country_code')
ipqs[proxy]=$(echo "$RESPONSE"|jq -r '.proxy')
ipqs[tor]=$(echo "$RESPONSE"|jq -r '.tor')
ipqs[vpn]=$(echo "$RESPONSE"|jq -r '.vpn')
ipqs[abuser]=$(echo "$RESPONSE"|jq -r '.recent_abuse')
ipqs[robot]=$(echo "$RESPONSE"|jq -r '.bot_status')
}

show_score(){
echo -ne "\r${sscore[title]}\n"
echo -ne "\r${sscore[range]}\n"
if [[ -n ${ip2location[score]} && $mode_lite -eq 0 ]];then
sscore_text "${ip2location[score]}" ${ip2location[score]} 33 66 99 13
echo -ne "\r${Font_Cyan}IP2Location${sscore[colon]}$Font_White$Font_B${sscore[text1]}$Back_Green${sscore[text2]}$Back_Yellow${sscore[text3]}$Back_Red${sscore[text4]}$Font_Suffix${ip2location[risk]}\n"
fi
if [[ -n ${scamalytics[score]} ]];then
sscore_text "${scamalytics[score]}" ${scamalytics[score]} 20 60 100 13
echo -ne "\r${Font_Cyan}Scamalytics${sscore[colon]}$Font_White$Font_B${sscore[text1]}$Back_Green${sscore[text2]}$Back_Yellow${sscore[text3]}$Back_Red${sscore[text4]}$Font_Suffix${scamalytics[risk]}\n"
fi
if [[ -n ${ipapi[score]} ]];then
local tmp_score=$(echo "${ipapi[scorenum]} * 10000 / 1"|bc)
sscore_text "${ipapi[score]}" $tmp_score 85 300 10000 7
echo -ne "\r${Font_Cyan}ipapi${sscore[colon]}$Font_White$Font_B${sscore[text1]}$Back_Green${sscore[text2]}$Back_Yellow${sscore[text3]}$Back_Red${sscore[text4]}$Font_Suffix${ipapi[risk]}\n"
fi
if [[ $mode_lite -eq 0 ]];then
sscore_text "${abuseipdb[score]}" ${abuseipdb[score]} 25 25 100 11
[[ -n ${abuseipdb[score]} ]]&&echo -ne "\r${Font_Cyan}AbuseIPDB${sscore[colon]}$Font_White$Font_B${sscore[text1]}$Back_Green${sscore[text2]}$Back_Yellow${sscore[text3]}$Back_Red${sscore[text4]}$Font_Suffix${abuseipdb[risk]}\n"
if [ -n "${ipqs[score]}" ]&&[ "${ipqs[score]}" != "null" ];then
sscore_text "${ipqs[score]}" ${ipqs[score]} 75 85 100 6
echo -ne "\r${Font_Cyan}IPQS${sscore[colon]}$Font_White$Font_B${sscore[text1]}$Back_Green${sscore[text2]}$Back_Yellow${sscore[text3]}$Back_Red${sscore[text4]}$Font_Suffix${ipqs[risk]}\n"
fi
fi
sscore_text " " ${dbip[score]} 33 66 100 7
[[ -n ${dbip[risk]} ]]&&echo -ne "\r${Font_Cyan}DB-IP${sscore[colon]}$Font_White$Font_B${sscore[text1]}$Back_Green${sscore[text2]}$Back_Yellow${sscore[text3]}$Back_Red${sscore[text4]}$Font_Suffix${dbip[risk]}\n"
}

factor_bool(){
local tmp_txt=""
if [[ $1 == "true" ]];then
tmp_txt+=".Factor |= . * { $3: { $2: true } } | "
elif [[ $1 == "false" ]];then
tmp_txt+=".Factor |= . * { $3: { $2: false } } | "
elif [ ${#1} -eq 2 ];then
tmp_txt+=".Factor |= . * { $3: { $2: \"$1\" } } | "
else
tmp_txt+=".Factor |= . * { $3: { $2: null } } | "
fi
[[ -z $tmp_txt ]]&&tmp_txt="null"
echo "$tmp_txt"
}

clean_ansi(){
local input="$1"
input=$(echo "$input"|sed 's/\\033/\x1b/g')
input=$(echo "$input"|sed 's/\x1b\[[0-9;]*m//g')
input=$(echo "$input"|sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
echo -n "$input"
}

save_json(){
local head_updates=""
local basic_updates=""
local type_updates=""
local score_updates=""
local factor_updates=""
local media_updates=""
local mail_updates=""
if [ $fullIP -eq 1 ];then
head_updates+=".Head |= . + { IP: \"${IP:-null}\" } | "
else
head_updates+=".Head |= . + { IP: \"${IPhide:-null}\" } | "
fi
head_updates+=".Head |= . + { Command: \"${shead[bash]:-null}\" } | "
head_updates+=".Head |= . + { GitHub: \"${shead[git]:-null}\" } | "
head_updates+=".Head |= . + { Time: \"${shead[time_raw]:-null}\" } | "
head_updates+=".Head |= . + { Version: \"${script_version:-null}\" } | "
if [ $mode_lite -eq 0 ];then
basic_updates+=".Info |= . + { ASN: \"${maxmind[asn]:-null}\" } | "
basic_updates+=".Info |= . + { Organization: \"${maxmind[org]:-null}\" } | "
basic_updates+=".Info |= . + { Latitude: \"${maxmind[lat]:-null}\" } | "
basic_updates+=".Info |= . + { Longitude: \"${maxmind[lon]:-null}\" } | "
basic_updates+=".Info |= . + { DMS: \"${maxmind[dms]:-null}\" } | "
basic_updates+=".Info |= . + { Map: \"${maxmind[map]:-null}\" } | "
basic_updates+=".Info |= . + { TimeZone: \"${maxmind[timezone]:-null}\" } | "
basic_updates+=".Info |= . * { City: { Name: \"${maxmind[city]:-null}\" } } | "
basic_updates+=".Info |= . * { City: { PostalCode: \"${maxmind[post]:-null}\" } } | "
basic_updates+=".Info |= . * { City: { SubCode: \"${maxmind[subcode]:-null}\" } } | "
basic_updates+=".Info |= . * { City: { Subdivisions: \"${maxmind[sub]:-null}\" } } | "
basic_updates+=".Info |= . * { Region: { Code: \"${maxmind[countrycode]:-null}\" } } | "
basic_updates+=".Info |= . * { Region: { Name: \"${maxmind[country]:-null}\" } } | "
basic_updates+=".Info |= . * { Continent: { Code: \"${maxmind[continentcode]:-null}\" } } | "
basic_updates+=".Info |= . * { Continent: { Name: \"${maxmind[continent]:-null}\" } } | "
basic_updates+=".Info |= . * { RegisteredRegion: { Code: \"${maxmind[regcountrycode]:-null}\" } } | "
basic_updates+=".Info |= . * { RegisteredRegion: { Name: \"${maxmind[regcountry]:-null}\" } } | "
if [[ -n ${maxmind[countrycode]} && ${maxmind[countrycode]} != "null" ]];then
if [ "${maxmind[countrycode]}" == "${maxmind[regcountrycode]}" ];then
basic_updates+=".Info |= . + { Type: \"$(clean_ansi "${sbasic[type0]:-null}")\" } | "
else
basic_updates+=".Info |= . + { Type: \"$(clean_ansi "${sbasic[type1]:-null}")\" } | "
fi
else
basic_updates+='.Info |= . + { Type: "null" } | '
fi
else
basic_updates+=".Info |= . + { ASN: \"${ipinfo[asn]:-null}\" } | "
basic_updates+=".Info |= . + { Organization: \"${ipinfo[org]:-null}\" } | "
basic_updates+=".Info |= . + { Latitude: \"${ipinfo[lat]:-null}\" } | "
basic_updates+=".Info |= . + { Longitude: \"${ipinfo[lon]:-null}\" } | "
basic_updates+=".Info |= . + { DMS: \"${ipinfo[dms]:-null}\" } | "
basic_updates+=".Info |= . + { Map: \"${ipinfo[map]:-null}\" } | "
basic_updates+=".Info |= . + { TimeZone: \"${ipinfo[timezone]:-null}\" } | "
basic_updates+=".Info |= . * { City: { Name: \"${ipinfo[city]:-null}\" } } | "
basic_updates+=".Info |= . * { City: { PostalCode: \"${ipinfo[post]:-null}\" } } | "
basic_updates+='.Info |= . * { City: { SubCode: "null" } } | '
basic_updates+='.Info |= . * { City: { Subdivisions: "null" } } | '
basic_updates+=".Info |= . * { Region: { Code: \"${ipinfo[countrycode]:-null}\" } } | "
basic_updates+=".Info |= . * { Region: { Name: \"${ipinfo[country]:-null}\" } } | "
basic_updates+='.Info |= . * { Continent: { Code: "null" } } | '
basic_updates+=".Info |= . * { Continent: { Name: \"${ipinfo[continent]:-null}\" } } | "
basic_updates+=".Info |= . * { RegisteredRegion: { Code: \"${ipinfo[regcountrycode]:-null}\" } } | "
basic_updates+=".Info |= . * { RegisteredRegion: { Name: \"${ipinfo[regcountry]:-null}\" } } | "
if [[ -n ${ipinfo[countrycode]} && ${ipinfo[countrycode]} != "null" ]];then
if [ "${ipinfo[countrycode]}" == "${ipinfo[regcountrycode]}" ];then
basic_updates+=".Info |= . + { Type: \"$(clean_ansi "${sbasic[type0]:-null}")\" } | "
else
basic_updates+=".Info |= . + { Type: \"$(clean_ansi "${sbasic[type1]:-null}")\" } | "
fi
else
basic_updates+='.Info |= . + { Type: "null" } | '
fi
fi
type_updates+=".Type |= . * { Usage: { IPinfo: \"$(clean_ansi "${ipinfo[susetype]:-null}")\" } } | "
type_updates+=".Type |= . * { Usage: { ipregistry: \"$(clean_ansi "${ipregistry[susetype]:-null}")\" } } | "
type_updates+=".Type |= . * { Usage: { ipapi: \"$(clean_ansi "${ipapi[susetype]:-null}")\" } } | "
type_updates+=".Type |= . * { Usage: { AbuseIPDB: \"$(clean_ansi "${abuseipdb[susetype]:-null}")\" } } | "
type_updates+=".Type |= . * { Usage: { IP2LOCATION: \"$(clean_ansi "${ip2location[susetype]:-null}")\" } } | "
type_updates+=".Type |= . * { Company: { IPinfo: \"$(clean_ansi "${ipinfo[scomtype]:-null}")\" } } | "
type_updates+=".Type |= . * { Company: { ipregistry: \"$(clean_ansi "${ipregistry[scomtype]:-null}")\" } } | "
type_updates+=".Type |= . * { Company: { ipapi: \"$(clean_ansi "${ipapi[scomtype]:-null}")\" } } | "
type_updates+=".Type |= . * { Company: { IP2LOCATION: \"$(clean_ansi "${ip2location[scomtype]:-null}")\" } } | "
score_updates+=".Score |= . + { IP2LOCATION: \"${ip2location[score]:-null}\" } | "
score_updates+=".Score |= . + { SCAMALYTICS: \"${scamalytics[score]:-null}\" } | "
score_updates+=".Score |= . + { ipapi: \"${ipapi[score]:-null}\" } | "
score_updates+=".Score |= . + { AbuseIPDB: \"${abuseipdb[score]:-null}\" } | "
score_updates+=".Score |= . + { IPQS: \"${ipapi[ipqs]:-null}\" } | "
score_updates+=".Score |= . + { DBIP: \"${dbip[score]:-null}\" } | "
factor_updates+=$(factor_bool "${ip2location[countrycode]}" "IP2LOCATION" "CountryCode")
factor_updates+=$(factor_bool "${ipapi[countrycode]}" "ipapi" "CountryCode")
factor_updates+=$(factor_bool "${ipregistry[countrycode]}" "ipregistry" "CountryCode")
factor_updates+=$(factor_bool "${ipqs[countrycode]}" "IPQS" "CountryCode")
factor_updates+=$(factor_bool "${scamalytics[countrycode]}" "SCAMALYTICS" "CountryCode")
factor_updates+=$(factor_bool "${ipdata[countrycode]}" "ipdata" "CountryCode")
factor_updates+=$(factor_bool "${ipinfo[countrycode]}" "IPinfo" "CountryCode")
factor_updates+=$(factor_bool "${ipwhois[countrycode]}" "IPWHOIS" "CountryCode")
factor_updates+=$(factor_bool "${dbip[countrycode]}" "DBIP" "CountryCode")
factor_updates+=$(factor_bool "${ip2location[proxy]}" "IP2LOCATION" "Proxy")
factor_updates+=$(factor_bool "${ipapi[proxy]}" "ipapi" "Proxy")
factor_updates+=$(factor_bool "${ipregistry[proxy]}" "ipregistry" "Proxy")
factor_updates+=$(factor_bool "${ipqs[proxy]}" "IPQS" "Proxy")
factor_updates+=$(factor_bool "${scamalytics[proxy]}" "SCAMALYTICS" "Proxy")
factor_updates+=$(factor_bool "${ipdata[proxy]}" "ipdata" "Proxy")
factor_updates+=$(factor_bool "${ipinfo[proxy]}" "IPinfo" "Proxy")
factor_updates+=$(factor_bool "${ipwhois[proxy]}" "IPWHOIS" "Proxy")
factor_updates+=$(factor_bool "${dbip[proxy]}" "DBIP" "Proxy")
factor_updates+=$(factor_bool "${ip2location[tor]}" "IP2LOCATION" "Tor")
factor_updates+=$(factor_bool "${ipapi[tor]}" "ipapi" "Tor")
factor_updates+=$(factor_bool "${ipregistry[tor]}" "ipregistry" "Tor")
factor_updates+=$(factor_bool "${ipqs[tor]}" "IPQS" "Tor")
factor_updates+=$(factor_bool "${scamalytics[tor]}" "SCAMALYTICS" "Tor")
factor_updates+=$(factor_bool "${ipdata[tor]}" "ipdata" "Tor")
factor_updates+=$(factor_bool "${ipinfo[tor]}" "IPinfo" "Tor")
factor_updates+=$(factor_bool "${ipwhois[tor]}" "IPWHOIS" "Tor")
factor_updates+=$(factor_bool "${dbip[tor]}" "DBIP" "Tor")
factor_updates+=$(factor_bool "${ip2location[vpn]}" "IP2LOCATION" "VPN")
factor_updates+=$(factor_bool "${ipapi[vpn]}" "ipapi" "VPN")
factor_updates+=$(factor_bool "${ipregistry[vpn]}" "ipregistry" "VPN")
factor_updates+=$(factor_bool "${ipqs[vpn]}" "IPQS" "VPN")
factor_updates+=$(factor_bool "${scamalytics[vpn]}" "SCAMALYTICS" "VPN")
factor_updates+=$(factor_bool "${ipdata[vpn]}" "ipdata" "VPN")
factor_updates+=$(factor_bool "${ipinfo[vpn]}" "IPinfo" "VPN")
factor_updates+=$(factor_bool "${ipwhois[vpn]}" "IPWHOIS" "VPN")
factor_updates+=$(factor_bool "${dbip[vpn]}" "DBIP" "VPN")
factor_updates+=$(factor_bool "${ip2location[server]}" "IP2LOCATION" "Server")
factor_updates+=$(factor_bool "${ipapi[server]}" "ipapi" "Server")
factor_updates+=$(factor_bool "${ipregistry[server]}" "ipregistry" "Server")
factor_updates+=$(factor_bool "${ipqs[server]}" "IPQS" "Server")
factor_updates+=$(factor_bool "${scamalytics[server]}" "SCAMALYTICS" "Server")
factor_updates+=$(factor_bool "${ipdata[server]}" "ipdata" "Server")
factor_updates+=$(factor_bool "${ipinfo[server]}" "IPinfo" "Server")
factor_updates+=$(factor_bool "${ipwhois[server]}" "IPWHOIS" "Server")
factor_updates+=$(factor_bool "${dbip[server]}" "DBIP" "Server")
factor_updates+=$(factor_bool "${ip2location[abuser]}" "IP2LOCATION" "Abuser")
factor_updates+=$(factor_bool "${ipapi[abuser]}" "ipapi" "Abuser")
factor_updates+=$(factor_bool "${ipregistry[abuser]}" "ipregistry" "Abuser")
factor_updates+=$(factor_bool "${ipqs[abuser]}" "IPQS" "Abuser")
factor_updates+=$(factor_bool "${scamalytics[abuser]}" "SCAMALYTICS" "Abuser")
factor_updates+=$(factor_bool "${ipdata[abuser]}" "ipdata" "Abuser")
factor_updates+=$(factor_bool "${ipinfo[abuser]}" "IPinfo" "Abuser")
factor_updates+=$(factor_bool "${ipwhois[abuser]}" "IPWHOIS" "Abuser")
factor_updates+=$(factor_bool "${dbip[abuser]}" "DBIP" "Abuser")
factor_updates+=$(factor_bool "${ip2location[robot]}" "IP2LOCATION" "Robot")
factor_updates+=$(factor_bool "${ipapi[robot]}" "ipapi" "Robot")
factor_updates+=$(factor_bool "${ipregistry[robot]}" "ipregistry" "Robot")
factor_updates+=$(factor_bool "${ipqs[robot]}" "IPQS" "Robot")
factor_updates+=$(factor_bool "${scamalytics[robot]}" "SCAMALYTICS" "Robot")
factor_updates+=$(factor_bool "${ipdata[robot]}" "ipdata" "Robot")
factor_updates+=$(factor_bool "${ipinfo[robot]}" "IPinfo" "Robot")
factor_updates+=$(factor_bool "${ipwhois[robot]}" "IPWHOIS" "Robot")
factor_updates+=$(factor_bool "${dbip[robot]}" "DBIP" "Robot")
media_updates+=".Media |= . * { TikTok: { Status: \"$(clean_ansi "${tiktok[ustatus]:-null}")\" } } | "
media_updates+=".Media |= . * { DisneyPlus: { Status: \"$(clean_ansi "${disney[ustatus]:-null}")\" } } | "
media_updates+=".Media |= . * { Netflix: { Status: \"$(clean_ansi "${netflix[ustatus]:-null}")\" } } | "
media_updates+=".Media |= . * { Youtube: { Status: \"$(clean_ansi "${youtube[ustatus]:-null}")\" } } | "
media_updates+=".Media |= . * { AmazonPrimeVideo: { Status: \"$(clean_ansi "${amazon[ustatus]:-null}")\" } } | "
media_updates+=".Media |= . * { Reddit: { Status: \"$(clean_ansi "${reddit[ustatus]:-null}")\" } } | "
media_updates+=".Media |= . * { ChatGPT: { Status: \"$(clean_ansi "${chatgpt[ustatus]:-null}")\" } } | "
media_updates+=".Media |= . * { TikTok: { Region: \"$(clean_ansi "${tiktok[uregion]//[][]/}")\" } } | "
media_updates+=".Media |= . * { DisneyPlus: { Region: \"$(clean_ansi "${disney[uregion]//[][]/}")\" } } | "
media_updates+=".Media |= . * { Netflix: { Region: \"$(clean_ansi "${netflix[uregion]//[][]/}")\" } } | "
media_updates+=".Media |= . * { Youtube: { Region: \"$(clean_ansi "${youtube[uregion]//[][]/}")\" } } | "
media_updates+=".Media |= . * { AmazonPrimeVideo: { Region: \"$(clean_ansi "${amazon[uregion]//[][]/}")\" } } | "
media_updates+=".Media |= . * { Reddit: { Region: \"$(clean_ansi "${reddit[uregion]//[][]/}")\" } } | "
media_updates+=".Media |= . * { ChatGPT: { Region: \"$(clean_ansi "${chatgpt[uregion]//[][]/}")\" } } | "
media_updates+=".Media |= . * { TikTok: { Type: \"$(clean_ansi "${tiktok[utype]:-null}")\" } } | "
media_updates+=".Media |= . * { DisneyPlus: { Type: \"$(clean_ansi "${disney[utype]:-null}")\" } } | "
media_updates+=".Media |= . * { Netflix: { Type: \"$(clean_ansi "${netflix[utype]:-null}")\" } } | "
media_updates+=".Media |= . * { Youtube: { Type: \"$(clean_ansi "${youtube[utype]:-null}")\" } } | "
media_updates+=".Media |= . * { AmazonPrimeVideo: { Type: \"$(clean_ansi "${amazon[utype]:-null}")\" } } | "
media_updates+=".Media |= . * { Reddit: { Type: \"$(clean_ansi "${reddit[utype]:-null}")\" } } | "
media_updates+=".Media |= . * { ChatGPT: { Type: \"$(clean_ansi "${chatgpt[utype]:-null}")\" } } | "
if [[ ${smail[local]} -eq 1 ]];then
mail_updates+=".Mail |= . + { Port25: true } | "
for service in "${services[@]}";do
if [[ ${smailstatus[$service]} == "true" ]];then
mail_updates+=".Mail |= . + { \"$service\": true } | "
else
mail_updates+=".Mail |= . + { \"$service\": false } | "
fi
done
elif [[ ${smail[local]} -eq 2 ]];then
mail_updates+=".Mail |= . + { Port25: null } | "
for service in "${services[@]}";do
mail_updates+=".Mail |= . + { \"$service\": null } | "
done
else
mail_updates+=".Mail |= . + { Port25: false } | "
for service in "${services[@]}";do
mail_updates+=".Mail |= . + { \"$service\": false } | "
done
fi
mail_updates+=".Mail |= . * { DNSBlacklist: { Total: ${smail[t]:-null} } } | "
mail_updates+=".Mail |= . * { DNSBlacklist: { Clean: ${smail[c]:-null} } } | "
mail_updates+=".Mail |= . * { DNSBlacklist: { Marked: ${smail[m]:-null} } } | "
mail_updates+=".Mail |= . * { DNSBlacklist: { Blacklisted: ${smail[b]:-null} } } | "
ipjson=$(echo "$ipjson"|jq "$head_updates$basic_updates$type_updates$score_updates$factor_updates$media_updates$mail_updates.")
}

check_IP(){
IP=$1
ibar_step=0
ipjson='{
      "Head": {},
      "Info": {},
      "Type": {},
      "Score": {},
      "Factor": {},
      "Media": {},
      "Mail": {}
    }'
[[ $2 -eq 4 ]]&&hide_ipv4 $IP
[[ $2 -eq 6 ]]&&hide_ipv6 $IP
countRunTimes
db_maxmind $2
db_ipinfo
[[ $mode_lite -eq 0 ]]&&db_scamalytics $2||scamalytics=()
db_ipregistry $2
db_ipapi $2
[[ $mode_lite -eq 0 ]]&&db_abuseipdb $2||abuseipdb=()
[[ $mode_lite -eq 0 ]]&&db_ip2location $2||ip2location=()
db_dbip
[[ $mode_lite -eq 0 ]]&&db_ipdata $2||ipdata=()
[[ $mode_lite -eq 0 ]]&&db_ipqs $2||ipqs=()
MediaUnlockTest_TikTok $2
MediaUnlockTest_DisneyPlus $2
MediaUnlockTest_Netflix $2
MediaUnlockTest_YouTube_Premium $2
MediaUnlockTest_PrimeVideo_Region $2
MediaUnlockTest_Reddit $2
OpenAITest $2
check_mail
[[ $2 -eq 4 ]]&&check_dnsbl "$IP" 50
echo -ne "$Font_LineClear" 1>&2
if [ $2 -eq 4 ]||[[ $IPV4work -eq 0 || $IPV4check -eq 0 ]];then
for ((i=0; i<ADLines; i++));do
echo -ne "$Font_LineUp" 1>&2
echo -ne "$Font_LineClear" 1>&2
done
fi
if [[ $mode_lite -eq 0 ]];then
local ip_report=$(show_head
show_basic
show_type
show_score
show_factor
show_media
show_mail $2
show_tail)
else
local ip_report=$(show_head
show_basic_lite
show_type_lite
show_score
show_factor_lite
show_media
show_mail $2
show_tail)
fi
local report_link=""
[[ mode_json -eq 1 || mode_output -eq 1 || mode_privacy -eq 0 ]]&&save_json
[[ $mode_lite -eq 0 && mode_privacy -eq 0 ]]&&report_link=$(curl -$2 -s -X POST https://upload.check.place -d "type=ip" --data-urlencode "json=$ipjson" --data-urlencode "content=$ip_report")
[[ mode_json -eq 0 ]]&&echo -ne "\r$ip_report\n"
[[ mode_json -eq 0 && mode_privacy -eq 0 && $report_link == *"https://Report.Check.Place/"* ]]&&echo -ne "\r${stail[link]}$report_link$Font_Suffix\n"
[[ mode_json -eq 1 ]]&&echo -ne "\r$ipjson\n"
echo -ne "\r\n"
if [[ mode_output -eq 1 ]];then
case "$outputfile" in
*.[aA][nN][sS][iI])echo "$ip_report" >>"$outputfile" 2>/dev/null
;;
*.[jJ][sS][oO][nN])echo "$ipjson" >>"$outputfile" 2>/dev/null
;;
*)echo -e "$ip_report"|sed 's/\x1b\[[0-9;]*[mGKHF]//g' >>"$outputfile" 2>/dev/null
esac
fi
}
