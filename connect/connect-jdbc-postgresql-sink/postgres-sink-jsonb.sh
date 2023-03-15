#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Pre-create table "
docker exec -i postgres psql -U myuser -d postgres << EOF
CREATE TABLE public.orders (
	id int4 NOT NULL,
	product text NOT NULL,
	quantity int4 NOT NULL,
	price float4 NOT NULL,
	json_field json NULL,
	jsonb_field jsonb NULL
);
EOF


log "Creating JDBC PostgreSQL sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
               "topics": "orders",
               "auto.create": "true"
          }' \
     http://localhost:8083/connectors/postgres-sink/config | jq .


log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}, {"name":"json_field", "type": "string"}, {"name":"jsonb_field","type": "string"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50, "json_field": "{\"product\": \"foo\",\"quantity\":\"100\"}", "jsonb_field": "{\"product\": \"foo\",\"quantity\":\"100\"}"}
EOF

sleep 5

log "Show content of ORDERS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM ORDERS'" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "foo" /tmp/result.log | grep "100"