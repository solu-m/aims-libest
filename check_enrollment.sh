# Check what's actually in the certificate file
cat test-device-cert.p7

# Also check EST server logs for enrollment details
docker logs est-server-backend --tail 100 | grep -A 5 -B 5 "testing2"

# Check if there were any errors
docker logs est-server-backend --tail 50 | grep ERROR
