#!/bin/bash

SEED_PATH='./vhosts.seed'
CONF_DIR='./conf.d/'
CONF_FILE='vhosts.conf'
PROXY_CONF_PATH='./proxy.conf'
CONF_FORMAT=$( cat << EOS
# %s
upstream %s {
	# %s
	server %s:80;
}
server {
	server_name %s;
	listen 80 ;
	location / {
		proxy_pass http://%s;
	}
}
EOS
)
log(){
	file_name=${BASH_SOURCE##*/}
	now=$(date '+%Y-%m-%d %H:%M:%S')
	echo -e "\e[38;5;08m[${now}](${file_name}:${BASH_LINENO})\e[m $@"
}
docker_api(){
	cmd='curl -s --unix-socket /var/run/docker.sock http:/v1.40'
	subcmd=''

	for arg in "$@"
	do
		subcmd+="/${arg}"
	done

	${cmd}${subcmd}
}
main(){
	log 'get gateways'
	gateways=($(ip route | awk '/^[1-9]/ {print $1}'))
	log 'gateways:'${gateways[@]}
	
	log 'get docker networks'
	belonging_dockernet_name=()
	for line in \
		$( docker_api networks | jq -c '.[] | [.IPAM.Config[].Subnet, .Name]')
	do
		maybe_subnet=$( echo $line | jq -r .[0] )
		echo ${gateways[@]} | grep -wq $maybe_subnet
		is_found=$?
		if [ ${is_found} == 0 ] ; then
			belonging_dockernet_name+=($( echo ${line} | jq -r .[1] ))
		fi
	done
	log 'networks belonging to:' ${belonging_dockernet_name[@]}
	
	log "get container's Name and IP addr"
	containers_json=''
	for net in ${belonging_dockernet_name[@]}
	do
		containers_json+=$(\
			docker_api networks ${net} \
			| jq '.Containers[] | {"Name":.Name, "IP":.IPv4Address}' \
			| sed 's!/[0-9]*!!'
		)
	done
	
	log 'containers:'
	echo ${containers_json} | jq -c . 
	
	log 'get containers VERTUAL HOST'
	vhosts_json=''
	while read line
	do
		vertual_host=''
		container_name=$( echo ${line} | jq -r '.Name' )
		vertual_host=$( \
			docker_api containers ${container_name} json | \
			jq -r '.Config.Env' | \
			sed -n -r 's/^.*VIRTUAL_HOST=(.*)".*$/"\1"/p'\
		)
	
		if [ ${vertual_host} ]; then
			vhosts_json+=$( echo ${line} | jq "{\"Name\":.Name, \"IP\":.IP, \"Host\":${vertual_host}}")
		fi
	done <<- EOS
	$( echo ${containers_json} | jq -c . )
	EOS
	log 'vhosts:'
	echo ${vhosts_json} | jq -c .
	
	is_same=0
	if [ -e ${SEED_PATH} ]; then
		while read line
		do
			grep -q -F "${line}" ${SEED_PATH}
			retval=$?
			if [ ${retval} == 0 ]; then
				:
			else
				is_same=1
				break
			fi
		done <<- EOS
		$( echo ${vhosts_json} | jq -c .)
		EOS
	fi
	if [ -e ${SEED_PATH} ] && [ ${is_same} == 0 ]; then
		log '\e[01;34mno changes\e[m'
	else
		log '\e[01;31msame changes detected\e[m'
		echo ${vhosts_json} | jq -c . > ${SEED_PATH}
	
		if [ ! -d ${CONF_DIR} ]; then
			mkdir ${CONF_DIR}
		fi
		if [ -e ${CONF_DIR}${CONF_FILE} ]; then
			rm ${CONF_DIR}${CONF_FILE}
		fi
		cat ${PROXY_CONF_PATH} > ${CONF_DIR}${CONF_FILE}
	
		registered=()
		for line in $( echo ${vhosts_json} | jq -c '.')
		do
			name=$( echo ${line} | jq -r '.Name') 
			ip=$( echo ${line} | jq -r '.IP') 
			host=$( echo ${line} | jq -r '.Host') 
	
			echo ${registered[@]} | grep -wq ${name}
			is_found=$?
			if [ $is_found != 0 ] ; then
				registered+=(${name})
	
				printf "${CONF_FORMAT}\n" \
					${host} \
					${host} \
					${name} \
					${ip} \
					${host} \
					${host} \
					>> ${CONF_DIR}${CONF_FILE}

				log "registered:"${name}
			fi
		done
	fi
}
main
