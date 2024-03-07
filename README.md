# decapod

로컬 환경에서 렌더링은 다음과 같이 수행할 수 있다.

- docker 설치 필요

```
$ sudo ./render.sh --cluster-id CLUSTER_ID \
 --use-render-container \
 --git-token GIT_TOKEN \
 --manifests-git CLUSTER-MANIFEST_REPO_URL

## (예)
$ sudo ./render.sh --cluster-id ckdtybp3u \
 --use-render-container \
 --git-token faaffe070ab202ae53d2332f9cf7f8daaf13a259 \
 --manifests-git http://localhost:3000/decapod10/ckdtybp3u-manifests.git

```

레퍼런스 사이트 렌더링 테스트만 필요하다면 아래와 같이 실행한다.

- `MANIFESTS_REPO_URL is empty, so we stop here. failed` 오류와 함께 종료되지만, 실제 렌더링 결과는 output 디렉토리에서 확인 할 수 있다.

```
$ sudo ./render.sh --cluster-id SITE_NAME \
 --use-render-container

## (예)
$ sudo ./render.sh --cluster-id aws-msa-reference \
 --use-render-container \
[2024-02-08 06:10:29] INFO     Starting build manifests for 'aws-msa-reference' site
...
[2024-02-08 06:12:14] INFO     Almost finished: changing namespace for cluster-resouces from argo to cluster-name..
[2024-02-08 06:12:14] ERROR     MANIFESTS_REPO_URL is empty, so we stop here. failed

$  tree output -L 2
output
└── aws-msa-reference
    ├── lma
    ├── policy
    ├── service-mesh
    └── tks-cluster
```
