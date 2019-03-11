#!/bin/bash -e

# FIXME: should also patch tosca loader, although we skip it now being completed
NS="voltha default kube-system"
PI=
for ns in $NS; do
  echo "-> Scanning namespace ${ns}"
  for pod in $(kubectl get pods --no-headers -n "${ns}" \
               -o=custom-columns=NAME:.metadata.name); do
    echo "--> Scanning pod ${pod}"
    for con in $(kubectl get pods --no-headers -n "${ns}" "${pod}" \
                 -o=jsonpath='{range .spec.containers[*]}{.name}{"|"}{.image}{"\n"}{end}'); do
      pair=($(echo "$con" | tr '|' ' '))
      echo "---> Scanning container ${pair[0]} based on ${pair[1]}"
      set +e
      where=$(kubectl exec -n "${ns}" "${pod}" -c "${pair[0]}" -- sh -c \
              'find / -wholename "*packages/yaml" -type d 2>/dev/null')
      if [ $? -eq 0 ] && [ -n "${where}" ]; then
        echo "pyyaml found, monkey-patching the local image ${pair[1]} for:"
        echo "${where}"
        cat <<-EOF | tee Dockerfile
		FROM ${pair[1]}
		COPY pyyaml_force_c_bindings.patch /p.patch
		RUN patch --help > /dev/null || \
		    (apt update && apt install -y patch) || \
		    (yum install -y patch) && \
		    for dir in ${where}; do \
		      cd \${dir} && patch -p0 -R --dry-run < /p.patch || \
		      patch -p0 < /p.patch; \
		    done && rm -f /p.patch
		EOF
        sudo docker build -t ${pair[1]} .
        PI+=" ${pair[1]}"
        rm Dockerfile
      else
        echo 'pyyaml not found, skipping'
      fi
      set -e
    done
  done
done
echo "Patched images: ${PI}"
echo "DONE, don't forget to set pull policy to 'IfNotPresent' in helm charts"
