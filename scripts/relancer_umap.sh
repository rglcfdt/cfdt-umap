git pull
docker compose up -d --no-deps --force-recreate app
sleep 5
docker compose ps
docker compose logs --tail=100 app
