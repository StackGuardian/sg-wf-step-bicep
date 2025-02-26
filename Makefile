img_name := "workflow-steps/bicep"
timestamp := $(shell date +%s)

img_tag_timestamp := 790543352839.dkr.ecr.eu-central-1.amazonaws.com/$(img_name):$(timestamp)
img_tag_latest := 790543352839.dkr.ecr.eu-central-1.amazonaws.com/$(img_name):latest
build-ship-docker-image-nonprod:
	docker build --file Dockerfile  --platform="linux/amd64" \
		--tag $(img_tag_timestamp) .
	docker tag $(img_tag_timestamp) ${img_tag_latest}
	aws ecr get-login-password --region eu-central-1 --profile sg-nonprod-1 | docker login --username AWS --password-stdin 790543352839.dkr.ecr.eu-central-1.amazonaws.com
	docker push ${img_tag_latest}
	docker push $(img_tag_timestamp)

img_prod_name_timestamp := 476299211833.dkr.ecr.eu-central-1.amazonaws.com/$(img_name):$(timestamp)-v0.1.0-bicep
img_prod_tag_latest := 476299211833.dkr.ecr.eu-central-1.amazonaws.com/$(img_name):latest
build-ship-docker-image-prod:
	docker build --file Dockerfile  --platform="linux/amd64" \
		--tag $(img_prod_name_timestamp) .
	docker tag $(img_prod_name_timestamp) $(img_prod_tag_latest)
	aws ecr get-login-password --region eu-central-1 --profile sg-prod | docker login --username AWS --password-stdin 476299211833.dkr.ecr.eu-central-1.amazonaws.com
	docker push ${img_prod_tag_latest}
	docker push $(img_prod_name_timestamp)
