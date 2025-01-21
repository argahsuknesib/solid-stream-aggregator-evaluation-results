#!/bin/bash

# Machine details
REPLAYER_HOST="n078-06.wall1.ilabt.imec.be"
REPLAYER_USER="kbisenug"
SOLID_POD_HOST="n078-03.wall1.ilabt.imec.be"
SOLID_POD_USER="kbisenug"
CLIENT_HOST="n078-19.wall1.ilabt.imec.be"
CLIENT_USER="kbisenug"
AGGREGATOR_HOST="n078-22.wall1.ilabt.imec.be"
AGGREGATOR_USER="kbisenug"

PEM_FILE="/home/kush/Code/RSP/decentralized-stream-aggregator-evaluation-results/pem_file.pem"
BASTION_USER="fffkbisenug"
BASTION_HOST="bastion.ilabt.imec.be"

# Experiment constants
NUM_ITERATIONS=35
NOTIFICATION_FOLDER="/users/kbisenug/data2/.internal/notifications"
DATA_FOLDERS=("/users/kbisenug/data2/pod1/acc-x/" "/users/kbisenug/data2/pod1/acc-y/" "/users/kbisenug/data2/pod1/acc-z")
LOGS_REMOTE_PATHS=("/users/kbisenug/decentralized-stream-aggregator-evaluation/src/increasing-number-of-clients/without-aggregator/util/without-aggregator-0-client.csv" "/users/kbisenug/decentralized-stream-aggregator-evaluation/src/increasing-number-of-clients/without-aggregator/util/log-0.log" "/users/kbisenug/decentralized-stream-aggregator-evaluation/src/increasing-number-of-clients/without-aggregator/util/result-0-client.csv" "/users/kbisenug/decentralized-stream-aggregator-evaluation/src/increasing-number-of-clients/without-aggregator/util/logs/RSPEngine.log" "/users/kbisenug/decentralized-stream-aggregator-evaluation/src/increasing-number-of-clients/without-aggregator/util/logs/CSPARQLWindow.log")
LOGS_LOCAL_PATH="/home/kush/Code/RSP/decentralized-stream-aggregator-evaluation-results/logs/"
LOGS_LOCAL_PATH_REPLAYER="/users/kbisenug/replayer/replayer-log.csv"
SSH_OPTIONS="-o HostKeyAlgorithms=+ssh-rsa -o PubKeyAcceptedAlgorithms=+ssh-rsa -A -o ServerAliveInterval=120 -i ${PEM_FILE}"

# ProxyCommand as separate variable
PROXY_COMMAND="ssh -i ${PEM_FILE} -oPort=22 ${BASTION_USER}@${BASTION_HOST} -W %h:%p"

run_ssh_command() {
  local host="$1"
  local user="$2"
  local command="$3"
  ssh ${SSH_OPTIONS} -o ProxyCommand="${PROXY_COMMAND}" "${user}@${host}" "${command}"
}

download_logs() {
  local iteration="$1"
  local local_path="$2"
  mkdir -p "${local_path}/${iteration}"

  for remote_path in "${LOGS_REMOTE_PATHS[@]}"; do
    echo "Downloading ${remote_path} to ${local_path}/${iteration}/"
    scp ${SSH_OPTIONS} -o ProxyCommand="${PROXY_COMMAND}" "${CLIENT_USER}@${CLIENT_HOST}:${remote_path}" "${local_path}/${iteration}/"
  done
}

download_replayer_log(){
  local iteration="$1"
  local local_path="$2"
  echo "Downloading replayer log to ${local_path}/${iteration}/"
  scp ${SSH_OPTIONS} -o ProxyCommand="${PROXY_COMMAND}" "${REPLAYER_USER}@${REPLAYER_HOST}:${LOGS_LOCAL_PATH_REPLAYER}" "${local_path}/${iteration}/"
}


for iteration in $(seq 1 $NUM_ITERATIONS); do
  for path in "${LOGS_REMOTE_PATHS[@]}"; do
  run_ssh_command "$CLIENT_HOST" "$CLIENT_USER" "rm -rf ${path}"
  done
  echo "Starting iteration ${iteration}..."

  # Step 1: Prepare folders on the solid pod machine
  echo "Cleaning up and creating folders on solid pod machine..."
  run_ssh_command "$SOLID_POD_HOST" "$SOLID_POD_USER" "rm -rf ${NOTIFICATION_FOLDER}"
  for folder in "${DATA_FOLDERS[@]}"; do
    run_ssh_command "$SOLID_POD_HOST" "$SOLID_POD_USER" "rm -rf ${folder}"
  done

  # Step 2: Start the aggregator machine
  echo "Starting aggregator..."
  run_ssh_command "$CLIENT_HOST" "$CLIENT_USER" "cd /users/kbisenug/decentralized-stream-aggregator-evaluation && npx ts-node initialise-LDES.ts" &
  run_ssh_command "$AGGREGATOR_HOST" "$AGGREGATOR_USER" "cd /users/kbisenug/decentralized-stream-notifications-aggregator && npx ts-node start_notification_aggregator_process.ts" &

  # Step 3: Start the client script
  echo "Starting client script..."
  run_ssh_command "$CLIENT_HOST" "$CLIENT_USER" "cd /users/kbisenug/decentralized-stream-aggregator-evaluation/src/increasing-number-of-clients/without-aggregator/util/ && npx ts-node main.ts" &

  # Step 4: Start the replayer machine
  echo "Starting replayer..."
  run_ssh_command "$REPLAYER_HOST" "$REPLAYER_USER" "cd /users/kbisenug/replayer && npm run start" &

  # Step 5: Wait for processes to finish
  # (This is a simple sleep for now, but you can replace it with a more reliable process checking mechanism)
  echo "Waiting for replayer and client to finish..."
  sleep 720  # Consider replacing this with a more dynamic wait

  # Step 6: Download logs from client machine
  echo "Downloading logs from client machine..."
  
  download_logs "$iteration" "$LOGS_LOCAL_PATH"

  # Step 7: Downloading logs from the replayer machine

  download_replayer_log "$iteration" "$LOGS_LOCAL_PATH_REPLAYER"

  # Step 8: Clean up
  echo "Cleaning up and deleting the log files after they are downloaded..."
  for path in "${LOGS_REMOTE_PATHS[@]}"; do
  run_ssh_command "$CLIENT_HOST" "$CLIENT_USER" "rm -rf ${path}"
  done

  run_ssh_command "$REPLAYER_HOST" "$REPLAYER_USER" "rm -rf ${LOGS_LOCAL_PATH_REPLAYER}"

  echo "Iteration ${iteration} completed.\n"
done

echo "All iterations completed."
