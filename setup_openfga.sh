#!/bin/bash

# 1. Creazione dello Store e cattura dell'ID
echo "Creazione del nuovo Store OpenFGA..."
STORE_RESPONSE=$(curl -s -X POST http://localhost:8081/stores \
  -H "Content-Type: application/json" \
  -d '{"name": "Astarte Pairing Store"}')

# Estraiamo l'ID dallo Store
STORE_ID=$(echo $STORE_RESPONSE | jq -r .id)
echo "✅ Store ID generato: $STORE_ID"

# 2. Creazione dell'Authorization Model e cattura dell'ID
#    "device.belongs_to" + "device_manager from belongs_to" e' una vera
#    relazione composta (tupleToUserset): un device_manager del realm eredita
#    i permessi su OGNI device del realm senza bisogno di una tupla diretta
#    per ciascuno.
echo "Creazione dell'Authorization Model..."
MODEL_RESPONSE=$(curl -s -X POST "http://localhost:8081/stores/${STORE_ID}/authorization-models" \
  -H "Content-Type: application/json" \
  -d '{
    "schema_version": "1.1",
    "type_definitions": [
      { "type": "user" },
      {
        "type": "realm",
        "relations": {
          "device_register": { "this": {} },
          "fdo_manage": { "this": {} },
          "fdo_read": { "this": {} },
          "device_manager": { "this": {} }
        },
        "metadata": {
          "relations": {
            "device_register": {
              "directly_related_user_types": [{ "type": "user" }]
            },
            "fdo_manage": {
              "directly_related_user_types": [{ "type": "user" }]
            },
            "fdo_read": {
              "directly_related_user_types": [{ "type": "user" }]
            },
            "device_manager": {
              "directly_related_user_types": [{ "type": "user" }]
            }
          }
        }
      },
      {
        "type": "device",
        "relations": {
          "belongs_to": { "this": {} },
          "can_unregister": {
            "union": {
              "child": [
                { "this": {} },
                {
                  "tupleToUserset": {
                    "tupleset": { "relation": "belongs_to" },
                    "computedUserset": { "relation": "device_manager" }
                  }
                }
              ]
            }
          },
          "can_obtain_credentials": {
            "union": {
              "child": [
                { "this": {} },
                {
                  "tupleToUserset": {
                    "tupleset": { "relation": "belongs_to" },
                    "computedUserset": { "relation": "device_manager" }
                  }
                }
              ]
            }
          },
          "can_verify_credentials": {
            "union": {
              "child": [
                { "this": {} },
                {
                  "tupleToUserset": {
                    "tupleset": { "relation": "belongs_to" },
                    "computedUserset": { "relation": "device_manager" }
                  }
                }
              ]
            }
          }
        },
        "metadata": {
          "relations": {
            "belongs_to": {
              "directly_related_user_types": [{ "type": "realm" }]
            },
            "can_unregister": {
              "directly_related_user_types": [{ "type": "user" }]
            },
            "can_obtain_credentials": {
              "directly_related_user_types": [{ "type": "user" }]
            },
            "can_verify_credentials": {
              "directly_related_user_types": [{ "type": "user" }]
            }
          }
        }
      }
    ]
  }')

# Estraiamo l'ID del Modello
MODEL_ID=$(echo $MODEL_RESPONSE | jq -r .authorization_model_id)
echo "✅ Authorization Model ID generato: $MODEL_ID"

# 3. Scrittura delle Tuple
echo "Scrittura delle tuple per il test_user_id..."
curl -s -X POST "http://localhost:8081/stores/${STORE_ID}/write" \
  -H "Content-Type: application/json" \
  -d '{
    "writes": {
      "tuple_keys": [
        {
          "user": "user:test_user_id",
          "relation": "device_register",
          "object": "realm:test"
        },
        {
          "user": "user:test_user_id",
          "relation": "can_unregister",
          "object": "device:f0VMRgIBAQAAAAAAAAAAAA"
        },
        {
          "user": "user:test_user_id",
          "relation": "can_obtain_credentials",
          "object": "device:f0VMRgIBAQAAAAAAAAAAAA"
        },
        {
          "user": "user:test_user_id",
          "relation": "can_verify_credentials",
          "object": "device:f0VMRgIBAQAAAAAAAAAAAA"
        },
        {
          "user": "user:test_user_id",
          "relation": "can_verify_credentials",
          "object": "device:Device_Con_Introspection"
        },
        {
          "user": "realm:test",
          "relation": "belongs_to",
          "object": "device:Device_Con_Introspection"
        }
      ]
    }
  }' > /dev/null
echo "✅ Tuple scritte con successo. Setup completato!"

# 4. Demo della relazione composta: device_manager_demo NON ha nessuna tupla
#    diretta sul device, solo "device_manager" sul realm. Il check dovrebbe
#    comunque risultare "allowed: true" su can_unregister grazie a
#    "device_manager from belongs_to".
echo "Scrittura della tupla di device_manager del realm per device_manager_demo..."
curl -s -X POST "http://localhost:8081/stores/${STORE_ID}/write" \
  -H "Content-Type: application/json" \
  -d '{
    "writes": {
      "tuple_keys": [
        {
          "user": "user:device_manager_demo",
          "relation": "device_manager",
          "object": "realm:test"
        }
      ]
    }
  }' > /dev/null
echo "✅ device_manager_demo e' ora device_manager di realm:test."

echo "Verifica della relazione ereditata (tupleToUserset)..."
curl -s -X POST "http://localhost:8081/stores/${STORE_ID}/check" \
  -H "Content-Type: application/json" \
  -d '{
    "tuple_key": {
      "user": "user:device_manager_demo",
      "relation": "can_unregister",
      "object": "device:Device_Con_Introspection"
    }
  }'
echo ""
echo "☝️ Se \"allowed\" e' true, device_manager_demo eredita il permesso senza tupla diretta sul device."
