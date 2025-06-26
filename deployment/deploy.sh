#!/bin/bash

set -e

# TEMP
BLUE_SERVICE="grepp-app-blue"
GREEN_SERVICE="grepp-app-green"
NGINX_SERVICE="grepp-web"

# CUSTOM
NGINX_CONF_INCLUDE_PATH="./lib/service-url.inc"

ACTIVE_SERVICE=$(awk -F'[/:;]' '/set \$service_url/ {print $4}' $NGINX_CONF_INCLUDE_PATH)


if [ "$ACTIVE_SERVICE" == "$BLUE_SERVICE" ]; then
  INACTIVE_SERVICE=$GREEN_SERVICE
else
  INACTIVE_SERVICE=$BLUE_SERVICE
fi

echo "현재 활성 서비스: $ACTIVE_SERVICE"
echo "배포 대상 서비스: $INACTIVE_SERVICE"

# TEMP
IMAGE_TAG=$1

if [ -z "$IMAGE_TAG" ]; then
  echo "에러: IMAGE_TAG 환경 변수가 설정되지 않았습니다."
  exit 1
fi


echo "'$INACTIVE_SERVICE'의 새 Docker 이미지를 가져옵니다."


echo "'$INACTIVE_SERVICE' 서비스를 시작합니다."
docker-compose up -d --no-deps $INACTIVE_SERVICE

echo "'$INACTIVE_SERVICE'의 Health Check를 수행합니다."

success=false
for i in {1..30}
do
  sleep 1
  echo "${i}번째 시도..."
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/)
  if [ "$STATUS" == "404" ]; then
    echo "컨테이너가 정상적으로 동작 중입니다. 포트 스위칭을 시작합니다."
    success=true
    break
  fi
done

if [ "$success" != "true" ]; then
  echo "컨테이너가 정상 기동되지 않았습니다. 롤백을 수행해야 합니다."
  exit 1
fi


echo "Nginx 트래픽을 '$INACTIVE_SERVICE'(으)로 전환합니다."

echo "set \$service_url http://$INACTIVE_SERVICE:8080;" > $NGINX_CONF_INCLUDE_PATH
echo "   Nginx 설정 파일 업데이트 완료."

docker-compose exec $NGINX_SERVICE nginx -s reload
echo "   Nginx 설정이 리로드되었습니다. 트래픽 전환 완료!"

echo "이전 버전 서비스 '$ACTIVE_SERVICE'를 중지/제거합니다."

docker-compose stop $ACTIVE_SERVICE
docker-compose rm -f $ACTIVE_SERVICE

echo "새로운 활성 서비스: $INACTIVE_SERVICE"
echo "배포 완료"