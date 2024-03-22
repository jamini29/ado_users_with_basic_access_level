#!/bin/bash

#set -xve
set -e

az --version

# global variables:
# AZURE_DEVOPS_EXT_PAT
# MAP_ORGANIZATION
# MAP_PROJECT

if [[ ${MAP_ORGANIZATION} != "hyperspace-pipelines" && ${MAP_ORGANIZATION} != "hyperspace-pipelines-2" ]]; then
    echo >&2 "Only 'hyperspace-pipelines' or 'hyperspace-pipelines-2' are allowed as organization"
    exit 1
fi
organization="https://dev.azure.com/${MAP_ORGANIZATION}/"

# check project and auth
if [[ -z ${MAP_PROJECT} ]]; then
    echo >&2 "Project cannot be empty, please check pipeline environments"
    exit 1
fi
project_id=$(az devops project show \
  --org ${organization} \
  --project ${MAP_PROJECT} \
  --query "[id]" \
  --output tsv)

if [[ -z $project_id ]]; then
    echo >&2 "Something went really wrong - no errors raised but project id empty, so I give up"
    exit 1
fi
project="${MAP_PROJECT}"

echo "Organization: ${organization}"
echo "Project: ${project}"

echo "-- List projects security groups, collect members:"
emails=()

while IFS=$'\t' read -r name descriptor; do
	echo -n "  Group: ${name} "

	count=0
	while read -r email; do
		count=$((count+1))
		emails+=($email)
	done < <(az devops security group membership list \
		--org ${organization} \
		--id ${descriptor} \
		--query "@.* | [? subjectKind=='user' && metaType!=null && mailAddress!='azureprod@global.corp.sap' && mailAddress!='azuretest@global.corp.sap'].[mailAddress]" \
		--output tsv)
	
	echo ", members collected: ${count}"
done < <(az devops security group list \
	--org ${organization} \
	--project=${project} \
	--query "graphGroups[? isCrossProject==null && isDeleted==null].[displayName, descriptor]" \
	--output tsv)

echo -e "\n  Total collected: ${#emails[@]}"

unique_emails=($(echo "${emails[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
echo "  Sorted unique emails: ${#unique_emails[@]}"

echo "-- Search for users with a license other than 'Stakeholder'.:"
echo "#### List of users on project '${project}' with license that includes features of Basic access level:" | tee results.md
i=0
for email in ${unique_emails[@]}; do
	IFS=$'\t' read -r email sapid name license <<< $(az devops user show \
		--org ${organization} \
		--user ${email} \
		--query "[[user.mailAddress, user.directoryAlias, user.displayName, accessLevel.licenseDisplayName]]" \
		--output tsv)

	if [[ ${license} = 'Stakeholder' || ${license} = 'Auto' ]]; then continue; fi # skip stakeholder license and users not in organization user list
	((++i))
	echo "- ${name} (${sapid}), ${email}, license type: ${license}" | tee -a results.md
done
if [[ $i -eq 0 ]]; then
  echo "- empty list :(" | tee -a results.md
fi

sed -E '1{s/#### (.*)/<html><body><h4>\1<\/h4><ul>/}; 2,${s/- (.*)/<li>\1<\/li>/}; $ {s/$/<\/ul><\/body><\/html>/}' results.md > results.html
