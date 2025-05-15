#!/bin/bash

parse="
y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/
s/[[:space:]]\+/ /g; s/^[[:space:]]\+//; s/[[:space:]]\+$//;
s/\(^\|\s\)\(#\|\!\).*//;
s/^\(\(host\|domain\)\(-suffix\|\)\),//; s/,reject$//;
s:^\(address\|server\)=/::; s|\/0\.0\.0\.0$||;
s/^\(\(\(0\|127\)\.\([[:digit:]]\{1,3\}\.\)\{2\}[[:digit:]]\{1,3\}\)\|::\|0\)\s//;
s/[\^\$,]\(important\|empty\|first-party\|1p\|3p\|popup\|popunder\|third-party\|script\)//g;
s/[\^\$,]\(~third-party\|image\|media\|subdocument\|document\|doc\|object\|~object-subrequest\|frame\|all\|domain=in-addr\.arpa\)//g;
s/^\(\(||\)\{0,1\}\(|\)\{0,1\}\(\*\.\)\{0,1\}\(\.\)\{0,1\}\(=\)\{0,1\}\(-d\s\)\{0,1\}\)//;
:loop; s|[\*\^\/\?\|]$||; t loop;
/^[^.*\..]*$/d;
/\.\localdomain$/d;
/[^a-z0-9.\_-]/d;
/^[^a-z0-9]/d;
/[^a-z0-9]$/d;
"; trim() { sed -e "$parse" "$@"; }

prints() { sed -e '$a\' "$@"; }
deDuplicate() { awk '!visited[$0]++' "$@"; }
similarLines() { awk 'FNR==NR{a[$1];next}($1 in a){print}' "$@"; }
fRD() { awk -F'.' 'index($0,prev FS)!=1{ print; prev=$0 }' "$@"; }
debloat() { fRD <( cat - |rev | tr '.\1' '\1.' | sort | tr '.\1' '\1.') | rev; }

cURL() {
    curl -fsSL -A "$UA" "$@";
}

unset sources userAGs UAs rND UA index id IDs fileLoc scs Loc idURL file matchIDs matchId matchLoc matchURL fileMatch entrSum matchSum percent resMd resultMD resXT resultXT
userAGs=$(curl -fsSL https://assets.staticnetcontent.com/extension/useragents.txt |sed "s/^/\'/; s/$/\'/")
readarray -t UAs <<<"$userAGs"; rND=$(($RANDOM % ${#UAs[@]})); UA=("${UAs[$rND]}")
adlistFile='adlists.txt'

if [ $(dpkg-query -W -f='${Status}' parallel 2>/dev/null | grep -c "ok installed") -eq 0 ];
then
  sudo apt-get install parallel;
fi

if [ -f "$adlistFile" ]; then
    mapfile -t sources < "$adlistFile"
    export -f cURL
    rm -rf data && mkdir -p "$_"

    for URL in "${sources[@]}"; do
        index=$((index+1))
        id=$(echo "$URL" |md5sum |awk -F' ' '{print $1}')
        id="${index}_${id:24}"
        fileLoc="data/$id"
        IDs+=("$id")
        scs+=("$id,$URL,$fileLoc")
    done
    unset URL index id fileLoc

    echo "Downloading blocklists..."
    parallel -j10 --colsep "," cURL -o "data/'{1}'" '{2}' :::: <<< $(printf "%s\n" ${scs[@]})

    echo "Preparing blocklists..."
    for uid in "${IDs[@]}"; do
        newid=$(echo "$uid" |cut -f2 -d '_')
        eval '
        file'"$newid"'=$(trim "data/${uid}" |deDuplicate)
        filecon="file${newid}"; filec="${!filecon}"
        cl'"$newid"'=$(debloat <<< "$filec")
        '
    done
    unset uid newid filecon filec

    echo "Crosschecking..."
    unset indexQ
    rm -f results.txt results.md
    for id in "${IDs[@]}"; do
        mid=$(echo "$id" |cut -f2 -d '_')
        Loc="data/$id"
        indexQ=$((indexQ+1))
        idURL=$(grep -F "$Loc" <<< $(printf "%s\n" ${scs[@]}) |cut -f2 -d ",")

        echo "$indexQ/${#IDs[@]}: $idURL"
        if [ -f "$Loc" ]; then
            filevar="file$mid"
            file="${!filevar}"
            matchIDs=( "${IDs[@]/$id}" )
            echo -en "\n\n### $idURL\n| % coverage | Blocklist  |\n|---|---|\n" >>results.md
            echo -en "\n\n# $idURL\n-------------------------------------------------\n" >>results.txt

            for matchId in "${matchIDs[@]}"; do
                matchLoc="data/$matchId"
                if [ -f "$matchLoc" ]; then
                    mad=$(echo "$matchId" |cut -f2 -d '_')
                    matchURL=$(grep -F "$matchLoc" <<< $(printf "%s\n" ${scs[@]}) |cut -f2 -d ",")
                    fileMatchvar="cl${mad}"
                    fileMatch="${!fileMatchvar}"
                    entrSum=$(prints <<<"$fileMatch" |grep -c .)
                    matchSum=$(similarLines <(prints <<<"$file") <(prints <<<"$fileMatch") |grep -c .)
                    percent=$(echo "$matchSum $entrSum" |awk '{printf "%.0f", $1 * 100 / $2}')
                    readarray -t resMd < <(echo -e "| $percent | $matchURL |\n")
                    resultMD+=("$resMd")
                    percent="$percent%"
                    readarray -t resXT < <(echo -e "$percent\t$matchURL")
                    resultXT+=("$resXT")
                    unset matchId matchLoc mad matchURL fileMatchvar fileMatch entrSum matchSum percent resMd resXT
                fi
            done
            printf '%s\n' "${resultMD[@]}" >>results.md
            printf '%s\n' "${resultXT[@]}" >>results.txt
            unset resultMD resultXT
        else
            echo -e "$idURL is offline.\n" >>errors.txt
        fi
        unset id mid Loc idURL filevar file matchIDs
    done
    unset IDs indexQ scs
else
    echo "Blocklists file doesn't exist!"
fi

rm -rf data
