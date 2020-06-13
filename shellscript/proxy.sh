#!/bin/bash

docker_api(){
	subcmd=$1


	cmd='curl -s --unix-socket /var/run/docker.sock http:/v1.40/'
	cmd+=$subcmd

	${cmd}
}
#gateways=($(ip route | awk '/^[1-9]/ {print $1}' | sed -e 's!/.*$!!'))
gateways=($(ip route | awk '/^[1-9]/ {print $1}'))

for gateway in ${gateways[@]}
do
	echo $gateway
done


belonging_dockernet_name=()
for line in \
	$( docker_api networks | jq -c '.[] | [.IPAM.Config[].Subnet, .Name]')
do
	maybe_subnet=$( echo $line | jq -r .[0] )
	echo ${gateways[@]} | grep -wq $maybe_subnet
	is_found=$?
	if [ $is_found == 0 ] ; then
		belonging_dockernet_name+=($( echo $line | jq -r .[1] ))
	fi
done

echo ${belonging_dockernet_name[@]}

for net in ${belonging_dockernet_name[@]}
do
	docker_api networks/$net | jq
done

