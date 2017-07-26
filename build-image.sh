version=v0.1
docker build --no-cache --build-arg cachet_ver=$version -t  cachet-baltha/docker:$version .
