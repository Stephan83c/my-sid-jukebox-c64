#!/bin/bash
# Appuie sur une touche du C64U par la matrice (API machine:input).
# appuie sur une touche par la matrice (machine:input) : key.sh space|plus|minus|q|r
for t in press release; do
  curl -s -X POST -H 'Content-Type: application/json' -d "{\"events\":[{\"kind\":\"keyboard\",\"transition\":\"$t\",\"inputs\":[\"$1\"]}]}" http://192.168.1.27/v1/machine:input >/dev/null
  sleep 0.25
done
