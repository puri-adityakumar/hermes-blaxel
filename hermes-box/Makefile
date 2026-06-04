build:
	docker build --platform=linux/amd64 -t blaxel-sandbox-scratch .

run:
	docker rm -f blaxel-sandbox-scratch || true
	docker run --platform=linux/amd64 -p 8080:8080 -p 3000:3000 --name blaxel-sandbox-scratch blaxel-sandbox-scratch
