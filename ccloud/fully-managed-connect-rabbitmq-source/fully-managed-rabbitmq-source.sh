#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

if [ -z "$NGROK_AUTH_TOKEN" ]
then
     logerror "NGROK_AUTH_TOKEN is not set. Export it as environment variable or pass it as argument"
     logerror "Sign up at: https://dashboard.ngrok.com/signup"
     logerror "If you have already signed up, make sure your authtoken is installed."
     logerror "Your authtoken is available on your dashboard: https://dashboard.ngrok.com/get-started/your-authtoken"
     exit 1
fi

logwarn "🚨WARNING🚨"
logwarn "It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over internet using Ngrok (https://ngrok.com)."
logwarn "It is strongly encouraged to run it on a AWS EC2 instance where you'll use Confluent Static Egress IP Addresses (https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using EC2 Security Group."
logwarn ""
logwarn "Example in order to set EC2 Security Group with Confluent Static Egress IP Addresses and port 5672:"
logwarn "group=\$(aws ec2 describe-instances --instance-id <\$ec2-instance-id> --output=json | jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | jq -r '.SecurityGroups[] | .GroupName')"
logwarn "aws ec2 authorize-security-group-ingress --group-name "\$group" --protocol tcp --port 5672 --cidr 13.36.88.88/32"
logwarn "aws ec2 authorize-security-group-ingress --group-name "\$group" --protocol tcp --port 5672 --cidr 13.36.88.89/32"
logwarn "etc..."

check_if_continue

bootstrap_ccloud_environment



docker compose build
docker compose down -v --remove-orphans
docker compose up -d

sleep 5

log "Getting ngrok hostname and port"
NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

connector_name="RabbitMQSource_$USER"
set +e
log "Deleting fully managed connector $connector_name, it might fail..."
playground connector delete --connector $connector_name
set -e

sleep 3

log "Send message to RabbitMQ in myqueue"
docker exec rabbitmq_producer bash -c "python /producer.py myqueue 5"

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "RabbitMQSource",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "kafka.topic": "rabbitmq",
     "rabbitmq.host" : "$NGROK_HOSTNAME",
     "rabbitmq.port" : "$NGROK_PORT",
     "rabbitmq.username": "myuser",
     "rabbitmq.password" : "mypassword",
     "rabbitmq.queue": "myqueue",
     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 300

sleep 5

log "Verifying topic rabbitmq"
playground topic consume --topic rabbitmq --min-expected-messages 5 --timeout 60

# CreateTime:2024-03-26 16:38:53.274|Partition:0|Offset:4|Headers:rabbitmq.consumer.tag:amq.ctag-W89VdFXz19PMBPcz1rZb1g,rabbitmq.content.type:application/json,rabbitmq.content.encoding:utf-8,rabbitmq.delivery.mode:1,rabbitmq.priority:1,rabbitmq.correlation.id:null,rabbitmq.reply.to:null,rabbitmq.expiration:null,rabbitmq.message.id:4,rabbitmq.timestamp:null,rabbitmq.type:null,rabbitmq.user.id:null,rabbitmq.app.id:null,rabbitmq.delivery.tag:5,rabbitmq.redeliver:false,rabbitmq.exchange:,rabbitmq.routing.key:myqueue|Key:4|Value:{"id": 4, "body": "010101010101010101010101010101010101010101010101010101010101010101010"}|ValueSchemaId:

#log "Consume messages in RabbitMQ"
#docker exec -it rabbitmq_consumer bash -c "python /consumer.py myqueue"

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name